import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart' as jf;
import '../remote/remote_player_controller.dart';
import '../syncplay/syncplay_controller.dart';
import 'audio_player_handler.dart';
import 'media_item_mapper.dart';

final audioHandlerProvider = Provider<JellymusicAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden in main() with the AudioService.init() result.',
  );
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem.stream;
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState.stream;
});

final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue.stream;
});

final positionProvider = StreamProvider<Duration>((ref) {
  return AudioService.position;
});

/// Currently displayed item — local mediaItem, or a synthesized MediaItem
/// reflecting the remote session's now-playing.
final effectiveMediaItemProvider = Provider<MediaItem?>((ref) {
  final remoteId = ref.watch(activeRemoteSessionIdProvider);
  if (remoteId == null) return ref.watch(currentMediaItemProvider).value;
  final session = ref.watch(activeRemoteSessionProvider).value;
  if (session == null || session.nowPlayingItemId == null) return null;
  final repo = ref.watch(jellyfinRepositoryProvider);
  return MediaItem(
    id: session.nowPlayingItemId!,
    title: session.nowPlayingTitle ?? '',
    artist: session.nowPlayingArtist,
    duration: session.duration,
    artUri: Uri.parse(repo.imageUrl(session.nowPlayingItemId!, size: 600)),
    extras: const {'isRemote': true},
  );
});

/// Whether playback is currently active (local or remote).
final effectivePlayingProvider = Provider<bool>((ref) {
  if (ref.watch(activeRemoteSessionIdProvider) == null) {
    return ref.watch(playbackStateProvider).value?.playing ?? false;
  }
  final session = ref.watch(activeRemoteSessionProvider).value;
  return session?.hasNowPlaying == true && !session!.isPaused;
});

final effectivePositionProvider = Provider<Duration>((ref) {
  if (ref.watch(activeRemoteSessionIdProvider) == null) {
    return ref.watch(positionProvider).value ?? Duration.zero;
  }
  return ref.watch(activeRemoteSessionProvider).value?.position ??
      Duration.zero;
});

final effectiveDurationProvider = Provider<Duration>((ref) {
  if (ref.watch(activeRemoteSessionIdProvider) == null) {
    return ref.watch(currentMediaItemProvider).value?.duration ?? Duration.zero;
  }
  return ref.watch(activeRemoteSessionProvider).value?.duration ??
      Duration.zero;
});

/// App mixer volume 0.0–1.0 (from [AudioPlayer]).
final playerVolumeProvider = StreamProvider<double>((ref) {
  return ref.watch(audioHandlerProvider).player.volumeStream;
});

/// [LoopMode] for UI; mirrors `just_audio` / notification repeat.
final playerLoopModeProvider = StreamProvider<LoopMode>((ref) {
  return ref.watch(audioHandlerProvider).player.loopModeStream;
});

final playerShuffleEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioHandlerProvider).player.shuffleModeEnabledStream;
});

/// Surfaces playback errors so UI can react (e.g. snackbar).
final playerErrorProvider = StreamProvider<PlayerError>((ref) {
  return ref.watch(audioHandlerProvider).errorStream;
});

/// Jellyfin IDs of tracks added by the user via "Add to queue" / "Play next".
/// Empty whenever a new playback queue is loaded from an album/artist/playlist.
final userQueuedIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(audioHandlerProvider).userQueuedIdsStream;
});

final playerControllerProvider = Provider<PlayerController>((ref) {
  return PlayerController(
    ref: ref,
    handler: ref.watch(audioHandlerProvider),
    repo: ref.watch(jellyfinRepositoryProvider),
    downloads: ref.watch(downloadManagerProvider.notifier),
  );
});

class PlayerController {
  PlayerController({
    required this.ref,
    required this.handler,
    required this.repo,
    required this.downloads,
  });

  final Ref ref;
  final JellymusicAudioHandler handler;
  final JellyfinRepository repo;
  final DownloadManager downloads;

  String? get _remoteId => ref.read(activeRemoteSessionIdProvider);
  bool get isRemote => _remoteId != null;
  bool get isSyncPlay =>
      ref.read(syncPlayControllerProvider).activeGroup != null;
  RemotePlayerController get _remote =>
      ref.read(remotePlayerControllerProvider);
  SyncPlayController get _syncPlay =>
      ref.read(syncPlayControllerProvider.notifier);

  /// Load [tracks] and play from [startIndex] onwards.
  ///
  /// If [contextId] is supplied (an album, artist, or playlist ID) and the
  /// currently playing item belongs to the same context, this resumes without
  /// reloading — preserving the existing queue. Tracks before [startIndex] are
  /// not added to the queue so the queue always starts at the intended song.
  Future<void> playTracks(
    List<jf.Track> tracks, {
    int startIndex = 0,
    String? contextId,
    bool selectedTrack = false,
    bool randomizeStart = true,
    bool forceReload = false,
  }) async {
    if (tracks.isEmpty) return;

    if (isSyncPlay && !isRemote) {
      await _syncPlay.playTracks(tracks, startIndex: startIndex);
      return;
    }

    if (isRemote) {
      // Local handler must be silent while remote is playing.
      if (handler.playbackState.value.playing) await handler.pause();
      await _remote.playTracks(tracks, startIndex: startIndex);
      return;
    }

    // Play-all / shuffle-all path: resume without reloading if we're already
    // in this context. Safe because the caller has no specific target track.
    if (!forceReload &&
        !selectedTrack &&
        startIndex == 0 &&
        contextId != null) {
      final current = handler.mediaItem.value;
      if ((current?.extras?['contextId'] as String?) == contextId) {
        if (!handler.playbackState.value.playing) await handler.play();
        return;
      }
    }

    // Specific track tapped — try to jump within the existing queue first.
    if (!forceReload && selectedTrack && contextId != null) {
      final current = handler.mediaItem.value;
      final sameContext =
          (current?.extras?['contextId'] as String?) == contextId;
      if (sameContext) {
        final target = tracks[startIndex];
        final q = handler.queue.value;
        final idxInQueue = q.indexWhere(
          (m) => (m.extras?['jellyfinId'] as String?) == target.id,
        );
        if (idxInQueue >= 0) {
          await handler.skipToQueueItem(idxInQueue);
          return;
        }
      }
    }

    // Only queue tracks from startIndex onwards — no past songs in the queue.
    final toLoad = tracks
        .sublist(startIndex)
        .map((t) => _toMediaItem(t, contextId: contextId))
        .toList();
    await handler.loadQueue(
      toLoad,
      initialIndex: 0,
      randomizeStart: randomizeStart && !selectedTrack,
    );
  }

  Future<void> togglePlay() async {
    if (isSyncPlay && !isRemote) return _syncPlay.togglePlay();
    if (isRemote) return _remote.togglePlay();
    final playing = handler.playbackState.value.playing;
    if (playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> stop() => isSyncPlay && !isRemote
      ? _syncPlay.stop()
      : isRemote
      ? _remote.stop()
      : handler.stop();

  Future<void> next() => isSyncPlay && !isRemote
      ? _syncPlay.next()
      : isRemote
      ? _remote.next()
      : handler.skipToNext();
  Future<void> previous() => isSyncPlay && !isRemote
      ? _syncPlay.previous()
      : isRemote
      ? _remote.previous()
      : handler.skipToPrevious();
  Future<void> seek(Duration p) => isSyncPlay && !isRemote
      ? _syncPlay.seek(p)
      : isRemote
      ? _remote.seek(p)
      : handler.seek(p);
  Future<void> skipToIndex(int i) => isSyncPlay && !isRemote
      ? _syncPlay.skipToIndex(i)
      : handler.skipToQueueItem(i);
  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      isSyncPlay && !isRemote
      ? Future.value()
      : handler.reorderQueue(oldIndex, newIndex);

  Future<void> setVolume(double v) =>
      isRemote ? _remote.setVolume(v) : handler.setAppVolume(v);

  Future<void> toggleMute() async {
    if (isRemote) {
      // Best effort: read last known mute from session stream cache; default
      // to "muting" since we have no synchronous access here.
      final session = ref.read(activeRemoteSessionProvider).value;
      await _remote.setMuted(!(session?.isMuted ?? false));
      return;
    }
    await handler.toggleAppMute();
  }

  bool get isEffectivelyMuted {
    if (isRemote) {
      return ref.read(activeRemoteSessionProvider).value?.isMuted ?? false;
    }
    return handler.isEffectivelyMuted;
  }

  Future<void> cycleRepeatMode() =>
      isSyncPlay && !isRemote ? Future.value() : handler.cycleLoopMode();

  Future<void> toggleShuffle() =>
      isSyncPlay && !isRemote ? Future.value() : handler.toggleShuffle();

  /// Insert [track] immediately after the current track.
  Future<void> playNext(jf.Track track) async {
    if (isSyncPlay && !isRemote) return _syncPlay.playNext(track);
    if (isRemote) return _remote.playNext(track);
    final item = _toMediaItem(track);
    if (handler.queue.value.isEmpty) {
      await handler.loadQueue([item], initialIndex: 0, autoPlay: false);
      return;
    }
    await handler.insertNextInQueue(item);
  }

  /// Add [track] to the user-priority queue segment. Never auto-plays.
  Future<bool> addToQueue(jf.Track track) async {
    await addTracksToQueue([track]);
    return true;
  }

  /// Append [tracks] to the end of the queue **without** marking them as
  /// user-queued. Used to extend Instant Mix playback automatically; these
  /// items participate in shuffle and don't take "Play next" priority slots.
  Future<void> appendTracks(List<jf.Track> tracks, {String? contextId}) async {
    if (tracks.isEmpty || isRemote || isSyncPlay) return;
    final items = tracks
        .map((t) => _toMediaItem(t, contextId: contextId))
        .toList();
    await handler.appendItems(items);
  }

  /// Add [tracks] to the user-priority queue segment.
  ///
  /// Items are inserted after the currently playing track and after any
  /// existing user-queued items, keeping app-provided items after them.
  Future<int> addTracksToQueue(List<jf.Track> tracks) async {
    if (tracks.isEmpty) return 0;
    if (isSyncPlay && !isRemote) {
      for (final track in tracks) {
        await _syncPlay.addToQueue(track);
      }
      return tracks.length;
    }
    if (isRemote) {
      for (final t in tracks) {
        await _remote.addToQueue(t);
      }
      return tracks.length;
    }
    final currentQueue = handler.queue.value;
    final items = tracks.map(_toMediaItem).toList();
    if (currentQueue.isEmpty) {
      await handler.loadQueue(items, initialIndex: 0, autoPlay: false);
    } else {
      await handler.insertUserQueuedItems(items);
    }
    return tracks.length;
  }

  MediaItem _toMediaItem(jf.Track t, {String? contextId}) {
    return mediaItemForTrack(
      ref: ref,
      repo: repo,
      downloads: downloads,
      track: t,
      contextId: contextId,
    );
  }
}
