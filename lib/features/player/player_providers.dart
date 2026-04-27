import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart' as jf;
import 'audio_player_handler.dart';

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
    handler: ref.watch(audioHandlerProvider),
    repo: ref.watch(jellyfinRepositoryProvider),
    downloads: ref.watch(downloadManagerProvider.notifier),
  );
});

class PlayerController {
  PlayerController({
    required this.handler,
    required this.repo,
    required this.downloads,
  });

  final JellymusicAudioHandler handler;
  final JellyfinRepository repo;
  final DownloadManager downloads;

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
  }) async {
    if (tracks.isEmpty) return;

    // Resume without reloading if we're already in this context.
    if (startIndex == 0 && contextId != null) {
      final current = handler.mediaItem.value;
      if ((current?.extras?['contextId'] as String?) == contextId) {
        if (!handler.playbackState.value.playing) await handler.play();
        return;
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
      randomizeStart: !selectedTrack,
    );
  }

  Future<void> togglePlay() async {
    final playing = handler.playbackState.value.playing;
    if (playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> stop() => handler.stop();

  Future<void> next() => handler.skipToNext();
  Future<void> previous() => handler.skipToPrevious();
  Future<void> seek(Duration p) => handler.seek(p);
  Future<void> skipToIndex(int i) => handler.skipToQueueItem(i);
  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      handler.reorderQueue(oldIndex, newIndex);

  Future<void> setVolume(double v) => handler.setAppVolume(v);

  Future<void> toggleMute() => handler.toggleAppMute();

  bool get isEffectivelyMuted => handler.isEffectivelyMuted;

  Future<void> cycleRepeatMode() => handler.cycleLoopMode();

  Future<void> toggleShuffle() => handler.toggleShuffle();

  /// Insert [track] immediately after the current track.
  Future<void> playNext(jf.Track track) async {
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

  /// Add [tracks] to the user-priority queue segment.
  ///
  /// Items are inserted after the currently playing track and after any
  /// existing user-queued items, keeping app-provided items after them.
  Future<int> addTracksToQueue(List<jf.Track> tracks) async {
    if (tracks.isEmpty) return 0;
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
    final localPath = downloads.localPath(t.id);
    final localArtPath = downloads.localArtworkPath(t.id);
    final art = (t.imageTag == null || t.imageTag!.isEmpty)
        ? null
        : (localArtPath != null
            ? Uri.file(localArtPath).toString()
            : repo.imageUrl(t.imageItemId, imageTag: t.imageTag, size: 600));
    final streamUrl =
        localPath != null ? Uri.file(localPath).toString() : repo.streamUrl(t.id);
    return MediaItem(
      id: t.id,
      title: t.name,
      album: t.albumName,
      artist: t.artistName,
      duration: t.duration,
      artUri: art == null ? null : Uri.parse(art),
      extras: {
        'streamUrl': streamUrl,
        'jellyfinId': t.id,
        'albumId': t.albumId,
        'artistId': t.artistId,
        'isOffline': localPath != null,
        if (contextId != null) 'contextId': contextId,
      },
    );
  }
}
