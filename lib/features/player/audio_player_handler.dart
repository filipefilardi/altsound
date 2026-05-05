import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

class PlayerError {
  PlayerError({required this.title, required this.message});
  final String title;
  final String message;
}

class JellymusicAudioHandler extends BaseAudioHandler with SeekHandler {
  JellymusicAudioHandler({bool gaplessPlayback = true})
    : _player = AudioPlayer(useLazyPreparation: !gaplessPlayback) {
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

  final AudioPlayer _player;
  final _errors = PublishSubject<PlayerError>();
  final _userQueuedIds = BehaviorSubject<Set<String>>.seeded(const {});

  // Original (un-shuffled) item order from the last loadQueue call.
  // Used to restore order when the user turns shuffle off.
  List<MediaItem> _originalItems = [];

  /// Stream of playback errors. Listeners typically show a snackbar / banner.
  Stream<PlayerError> get errorStream => _errors.stream;

  /// IDs of tracks added by the user (via "Add to queue" / "Play next").
  /// Cleared whenever a new playback queue is loaded.
  Stream<Set<String>> get userQueuedIdsStream => _userQueuedIds.stream;

  /// Volume to restore on unmute. Never 0; never decreases below current
  /// non-muted level after explicit user volume changes.
  double _volumeBeforeMute = 1.0;

  /// Past this point, "previous" jumps to the start of the current track
  /// instead of the queue item before it (common music-player behaviour).
  static const _skipPreviousRestartThreshold = Duration(seconds: 3);

  AudioPlayer get player => _player;

  Map<String, dynamic>? buildPersistenceSnapshot() {
    final currentQueue = queue.value;
    if (currentQueue.isEmpty) return null;
    return {
      'schema': 1,
      'queue': currentQueue.map(_encodeMediaItem).toList(growable: false),
      'currentIndex': _player.currentIndex ?? 0,
      'positionMs': _player.position.inMilliseconds,
      'playing': _player.playing,
      'volume': _player.volume,
      'volumeBeforeMute': _volumeBeforeMute,
      'shuffleEnabled': _player.shuffleModeEnabled,
      'loopMode': _player.loopMode.name,
      'userQueuedIds': _userQueuedIds.value.toList(growable: false),
    };
  }

  Future<bool> restorePersistenceSnapshot(Map<String, dynamic> snapshot) async {
    final rawQueue = snapshot['queue'];
    if (rawQueue is! List || rawQueue.isEmpty) return false;
    final restored = rawQueue
        .whereType<Map>()
        .map((m) => _decodeMediaItem(Map<String, dynamic>.from(m)))
        .whereType<MediaItem>()
        .toList(growable: false);
    if (restored.isEmpty) return false;

    final sources = restored
        .map((m) {
          final streamUrl = m.extras?['streamUrl'];
          if (streamUrl is! String || streamUrl.isEmpty) return null;
          return AudioSource.uri(Uri.parse(streamUrl), tag: m);
        })
        .whereType<AudioSource>()
        .toList(growable: false);
    if (sources.isEmpty) return false;

    final savedIndex = snapshot['currentIndex'];
    final initialIndex = savedIndex is int
        ? savedIndex.clamp(0, sources.length - 1)
        : 0;
    final savedPositionMs = snapshot['positionMs'];
    final initialPosition = savedPositionMs is int && savedPositionMs > 0
        ? Duration(milliseconds: savedPositionMs)
        : Duration.zero;

    await _player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );

    _originalItems = List<MediaItem>.from(restored);
    queue.add(restored);
    mediaItem.add(restored[initialIndex]);

    final savedUserQueued = snapshot['userQueuedIds'];
    if (savedUserQueued is List) {
      _userQueuedIds.add(savedUserQueued.whereType<String>().toSet());
    } else {
      _userQueuedIds.add(const {});
    }

    final savedVolume = snapshot['volume'];
    if (savedVolume is num) {
      await _player.setVolume(savedVolume.toDouble().clamp(0.0, 1.0));
    }
    final savedVolumeBeforeMute = snapshot['volumeBeforeMute'];
    if (savedVolumeBeforeMute is num) {
      _volumeBeforeMute = savedVolumeBeforeMute.toDouble().clamp(0.0, 1.0);
    }

    final savedLoopMode = snapshot['loopMode'];
    final loopMode = switch (savedLoopMode) {
      'one' => LoopMode.one,
      'all' => LoopMode.all,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(loopMode);

    final savedShuffle = snapshot['shuffleEnabled'];
    if (savedShuffle is bool) {
      await _player.setShuffleModeEnabled(savedShuffle);
    }

    final shouldPlay = snapshot['playing'] == true;
    if (shouldPlay) {
      await _player.play();
    } else {
      await _player.pause();
    }
    _syncPlaybackState();
    return true;
  }

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

  /// Toggle shuffle. Physically reorders the queue so the display reflects
  /// the change immediately. Only items that were *not* added manually by
  /// the user ("Add to queue" / "Play next") get reordered — user-queued
  /// items keep their slot positions. Uses moveAudioSource to avoid audio
  /// interruption.
  Future<void> toggleShuffle() async {
    final currentIdx = _player.currentIndex ?? 0;
    final currentQueue = List<MediaItem>.from(queue.value);

    if (currentQueue.isEmpty) {
      await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
      return;
    }

    final wasEnabled = _player.shuffleModeEnabled;
    final tail = currentQueue.sublist(currentIdx + 1);
    final userIds = _userQueuedIds.value;

    // Tail slots occupied by non-user items — these are the ones we reorder.
    final nonUserPositions = <int>[];
    final nonUserItems = <MediaItem>[];
    for (var i = 0; i < tail.length; i++) {
      final id = tail[i].extras?['jellyfinId'] as String?;
      if (id != null && userIds.contains(id)) continue;
      nonUserPositions.add(i);
      nonUserItems.add(tail[i]);
    }

    if (nonUserItems.isEmpty) {
      await _player.setShuffleModeEnabled(!wasEnabled);
      return;
    }

    final List<MediaItem> reordered;
    if (!wasEnabled) {
      reordered = List<MediaItem>.from(nonUserItems)..shuffle(Random());
    } else {
      final origIndexById = <String, int>{};
      for (var i = 0; i < _originalItems.length; i++) {
        final id = _originalItems[i].extras?['jellyfinId'] as String?;
        if (id != null) origIndexById[id] = i;
      }
      reordered = List<MediaItem>.from(nonUserItems)
        ..sort((a, b) {
          final ai =
              origIndexById[a.extras?['jellyfinId'] as String?] ??
              _originalItems.length;
          final bi =
              origIndexById[b.extras?['jellyfinId'] as String?] ??
              _originalItems.length;
          return ai.compareTo(bi);
        });
    }

    final newTail = List<MediaItem>.from(tail);
    for (var i = 0; i < nonUserPositions.length; i++) {
      newTail[nonUserPositions[i]] = reordered[i];
    }

    await _rearrangeAfter(currentIdx, newTail);
    await _player.setShuffleModeEnabled(!wasEnabled);
  }

  /// Rearranges items after [currentIdx] to match [newOrder] using
  /// moveAudioSource so playback is not interrupted.
  Future<void> _rearrangeAfter(int currentIdx, List<MediaItem> newOrder) async {
    final working = List<MediaItem>.from(queue.value);
    final startPos = currentIdx + 1;
    for (int i = 0; i < newOrder.length; i++) {
      final targetPos = startPos + i;
      if (targetPos >= working.length) break;
      final wantedId = newOrder[i].extras?['jellyfinId'] as String?;
      int sourcePos = -1;
      for (int j = targetPos; j < working.length; j++) {
        if ((working[j].extras?['jellyfinId'] as String?) == wantedId) {
          sourcePos = j;
          break;
        }
      }
      if (sourcePos > targetPos) {
        await _player.moveAudioSource(sourcePos, targetPos);
        final item = working.removeAt(sourcePos);
        working.insert(targetPos, item);
      }
    }
    queue.add(working);
  }

  Future<void> loadQueue(
    List<MediaItem> items, {
    int initialIndex = 0,
    bool autoPlay = true,
    bool randomizeStart = false,
  }) async {
    if (items.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, items.length - 1);
    _originalItems = List<MediaItem>.from(items);

    // If shuffle is already active, shuffle remaining tracks.
    // Only pick a random starting track when the caller didn't select one.
    final List<MediaItem> toLoad;
    final int loadInitialIndex;
    if (_player.shuffleModeEnabled && items.length > 1) {
      final startIdx = randomizeStart
          ? Random().nextInt(items.length)
          : safeIndex;
      final startItem = items[startIdx];
      final rest = List<MediaItem>.from(items)
        ..removeAt(startIdx)
        ..shuffle(Random());
      toLoad = [startItem, ...rest];
      loadInitialIndex = 0;
    } else {
      toLoad = items;
      loadInitialIndex = safeIndex;
    }

    final sources = toLoad
        .map(
          (m) => AudioSource.uri(
            Uri.parse(m.extras!['streamUrl'] as String),
            tag: m,
          ),
        )
        .toList();
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: loadInitialIndex,
        initialPosition: Duration.zero,
      );
      queue.add(toLoad);
      mediaItem.add(toLoad[loadInitialIndex]);
      _userQueuedIds.add(const {});
      if (autoPlay) await _player.play();
    } catch (e) {
      _emitError(e, title: toLoad[loadInitialIndex].title);
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

  Future<void> appendToQueue(MediaItem item) async {
    final q = List<MediaItem>.from(queue.value)..add(item);
    queue.add(q);
    _userQueuedIds.add({
      ..._userQueuedIds.value,
      item.extras!['jellyfinId'] as String,
    });
    await _player.addAudioSource(
      AudioSource.uri(
        Uri.parse(item.extras!['streamUrl'] as String),
        tag: item,
      ),
    );
  }

  /// Append [items] to the end of the queue without marking them as user-queued.
  /// Used by automatic mix extension so they participate in shuffle and don't
  /// hold "Play next" priority slots.
  Future<void> appendItems(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final q = List<MediaItem>.from(queue.value)..addAll(items);
    queue.add(q);
    _originalItems = [..._originalItems, ...items];
    for (final item in items) {
      await _player.addAudioSource(
        AudioSource.uri(
          Uri.parse(item.extras!['streamUrl'] as String),
          tag: item,
        ),
      );
    }
  }

  Future<void> insertUserQueuedItems(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final q = List<MediaItem>.from(queue.value);
    if (q.isEmpty) return;

    int insertAt = (_player.currentIndex ?? 0) + 1;
    while (insertAt < q.length) {
      final id = q[insertAt].extras?['jellyfinId'] as String?;
      if (id == null || !_userQueuedIds.value.contains(id)) break;
      insertAt++;
    }

    for (int i = 0; i < items.length; i++) {
      final target = insertAt + i;
      final item = items[i];
      q.insert(target, item);
      await _player.insertAudioSource(
        target,
        AudioSource.uri(
          Uri.parse(item.extras!['streamUrl'] as String),
          tag: item,
        ),
      );
    }

    queue.add(q);
    _userQueuedIds.add({
      ..._userQueuedIds.value,
      ...items
          .map((m) => m.extras?['jellyfinId'] as String?)
          .whereType<String>(),
    });
  }

  Future<void> insertNextInQueue(MediaItem item) async {
    final insertAt = (_player.currentIndex ?? 0) + 1;
    final q = List<MediaItem>.from(queue.value)..insert(insertAt, item);
    queue.add(q);
    _userQueuedIds.add({
      ..._userQueuedIds.value,
      item.extras!['jellyfinId'] as String,
    });
    await _player.insertAudioSource(
      insertAt,
      AudioSource.uri(
        Uri.parse(item.extras!['streamUrl'] as String),
        tag: item,
      ),
    );
  }

  /// When [LoopMode.one] is active, just_audio reports `nextIndex` /
  /// `previousIndex` as the **current** index so skips only restart the same
  /// track. Users still expect hardware / UI next & previous to move in the
  /// queue (repeat-one should only affect automatic replay at track end).
  Future<void> _runSkipIgnoringRepeatOne(Future<void> Function() skip) async {
    final saved = _player.loopMode;
    if (saved == LoopMode.one) {
      await _player.setLoopMode(LoopMode.off);
    }
    try {
      await skip();
    } finally {
      if (saved == LoopMode.one) {
        await _player.setLoopMode(LoopMode.one);
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() =>
      _runSkipIgnoringRepeatOne(() => _player.seekToNext());

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > _skipPreviousRestartThreshold) {
      await _player.seek(Duration.zero);
      return;
    }
    await _runSkipIgnoringRepeatOne(() => _player.seekToPrevious());
  }

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
    _errors.add(
      PlayerError(title: "Couldn't play “$current”", message: e.toString()),
    );
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

    playbackState.add(
      playbackState.value.copyWith(
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
      ),
    );
  }

  Map<String, dynamic> _encodeMediaItem(MediaItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'album': item.album,
      'artist': item.artist,
      'durationMs': item.duration?.inMilliseconds,
      'artUri': item.artUri?.toString(),
      'extras': item.extras ?? const <String, dynamic>{},
    };
  }

  MediaItem? _decodeMediaItem(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String || id.isEmpty || title.isEmpty) {
      return null;
    }
    final durationMs = json['durationMs'];
    final artUriString = json['artUri'];
    final extrasRaw = json['extras'];
    return MediaItem(
      id: id,
      title: title,
      album: json['album'] as String?,
      artist: json['artist'] as String?,
      duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
      artUri: artUriString is String && artUriString.isNotEmpty
          ? Uri.tryParse(artUriString)
          : null,
      extras: extrasRaw is Map
          ? Map<String, dynamic>.from(extrasRaw.cast<dynamic, dynamic>())
          : const <String, dynamic>{},
    );
  }
}
