import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

class PlayerError {
  PlayerError({required this.title, required this.message});
  final String title;
  final String message;
}

class JellymusicAudioHandler extends BaseAudioHandler with SeekHandler {
  JellymusicAudioHandler() {
    _player.playbackEventStream.listen(
      (_) => _syncPlaybackState(),
      onError: (Object e, StackTrace st) => _emitError(e),
    );
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
  final _errors = PublishSubject<PlayerError>();

  /// Stream of playback errors. Listeners typically show a snackbar / banner.
  Stream<PlayerError> get errorStream => _errors.stream;

  /// Volume to restore on unmute. Never 0; never decreases below current
  /// non-muted level after explicit user volume changes.
  double _volumeBeforeMute = 1.0;

  AudioPlayer get player => _player;

  /// Effective mute: player volume is essentially 0.
  bool get isEffectivelyMuted => _player.volume < 0.001;

  Future<void> setAppVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    if (v > 0.001) {
      _volumeBeforeMute = v;
    }
    await _player.setVolume(v);
  }

  Future<void> toggleAppMute() async {
    if (isEffectivelyMuted) {
      final restore = _volumeBeforeMute < 0.05 ? 1.0 : _volumeBeforeMute;
      await _player.setVolume(restore);
    } else {
      _volumeBeforeMute = _player.volume;
      await _player.setVolume(0);
    }
  }

  /// UI: cycle off → all → one → off.
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
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
      await _player.play();
    } catch (e) {
      _emitError(e, title: items[initialIndex].title);
    }
  }

  /// Reorder a single item in the queue. Keeps `audio_service`'s mirror in sync.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final q = List<MediaItem>.from(queue.value);
    if (oldIndex < 0 ||
        oldIndex >= q.length ||
        newIndex < 0 ||
        newIndex > q.length) {
      return;
    }
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = q.removeAt(oldIndex);
    q.insert(adjusted, item);
    queue.add(q);
    await _player.moveAudioSource(oldIndex, adjusted);
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

  void _emitError(Object e, {String? title}) {
    final current = title ?? mediaItem.value?.title ?? 'this track';
    _errors.add(PlayerError(
      title: "Couldn't play “$current”",
      message: e.toString(),
    ));
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
