import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class JellymusicAudioHandler extends BaseAudioHandler with SeekHandler {
  JellymusicAudioHandler() {
    _player.playbackEventStream.listen((_) => _syncPlaybackState(), onError: (_) {});
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
    });
    _player.volumeStream.listen((_) => _syncPlaybackState());
    _player.loopModeStream.listen((_) => _syncPlaybackState());
    _player.shuffleModeEnabledStream.listen((_) => _syncPlaybackState());
  }

  final AudioPlayer _player = AudioPlayer();

  /// Volume to restore on unmute (last non-zero before mute).
  double _volumeBeforeMute = 1.0;

  AudioPlayer get player => _player;

  /// Effective mute: player volume is ~0 and we are not in a drag state that sets 0.
  bool get isEffectivelyMuted => _player.volume < 0.001;

  Future<void> setAppVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    await _player.setVolume(v);
  }

  /// Mute / unmute app output (independent of system volume on mobile).
  Future<void> toggleAppMute() async {
    if (_player.volume < 0.001) {
      await _player.setVolume(_volumeBeforeMute.clamp(0.0, 1.0));
    } else {
      _volumeBeforeMute = _player.volume;
      await _player.setVolume(0);
    }
  }

  /// UI: cycle none → all → one → off.
  Future<void> cycleLoopMode() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
  }

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
  }

  Future<void> loadQueue(
    List<MediaItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    queue.add(items);
    mediaItem.add(items[initialIndex]);
    final sources = items
        .map((m) => AudioSource.uri(
              Uri.parse(m.extras!['streamUrl'] as String),
              tag: m,
            ))
        .toList();
    await _player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    final q = queue.value;
    if (index < 0 || index >= q.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.off,
    };
    await _player.setLoopMode(mode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _syncPlaybackState() {
    final playing = _player.playing;
    final loopMode = _player.loopMode;
    final audioRepeatMode = switch (loopMode) {
      LoopMode.off => AudioServiceRepeatMode.none,
      LoopMode.one => AudioServiceRepeatMode.one,
      LoopMode.all => AudioServiceRepeatMode.all,
    };
    final audioShuffleMode = _player.shuffleModeEnabled
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;

    final systemActions = {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.setRepeatMode,
      MediaAction.setShuffleMode,
    };

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: systemActions,
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
      repeatMode: audioRepeatMode,
      shuffleMode: audioShuffleMode,
    ));
  }
}
