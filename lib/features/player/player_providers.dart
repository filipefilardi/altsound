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

  /// If [tracks] match the currently loaded queue (by Jellyfin id), just
  /// jump to [startIndex] — avoids reloading audio sources and the brief
  /// playback gap / loading flash that comes with it.
  Future<void> playTracks(
    List<jf.Track> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final mediaItems = tracks.map(_toMediaItem).toList();
    final currentQueue = handler.queue.value;
    final sameQueue = currentQueue.length == mediaItems.length &&
        List<int>.generate(mediaItems.length, (i) => i).every(
          (i) =>
              currentQueue[i].extras?['jellyfinId'] ==
              mediaItems[i].extras?['jellyfinId'],
        );
    if (sameQueue) {
      await handler.skipToQueueItem(startIndex);
    } else {
      await handler.loadQueue(mediaItems, initialIndex: startIndex);
    }
  }

  Future<void> togglePlay() async {
    final playing = handler.playbackState.value.playing;
    if (playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

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

  Future<void> addTrackToQueue(jf.Track track) async {
    final item = _toMediaItem(track);
    final currentQueue = handler.queue.value;
    if (currentQueue.isEmpty) {
      await handler.loadQueue([item], initialIndex: 0);
      return;
    }
    final exists = currentQueue
        .any((q) => q.extras?['jellyfinId'] == item.extras?['jellyfinId']);
    if (exists) return;
    await handler.appendToQueue(item);
  }

  MediaItem _toMediaItem(jf.Track t) {
    final art = (t.imageTag == null || t.imageTag!.isEmpty)
        ? null
        : repo.imageUrl(t.imageItemId, imageTag: t.imageTag, size: 600);
    final localPath = downloads.localPath(t.id);
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
        'artistId': t.artistId,
        'isOffline': localPath != null,
      },
    );
  }
}
