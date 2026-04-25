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

  Future<void> playTracks(
    List<jf.Track> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final mediaItems = tracks.map(_toMediaItem).toList();
    await handler.loadQueue(mediaItems, initialIndex: startIndex);
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

  Future<void> setVolume(double v) => handler.setAppVolume(v);

  Future<void> toggleMute() => handler.toggleAppMute();

  bool get isEffectivelyMuted => handler.isEffectivelyMuted;

  Future<void> cycleRepeatMode() => handler.cycleLoopMode();

  Future<void> toggleShuffle() => handler.toggleShuffle();

  MediaItem _toMediaItem(jf.Track t) {
    final art = repo.imageUrl(t.imageItemId, imageTag: t.imageTag, size: 600);
    final localPath = downloads.localPath(t.id);
    final streamUrl =
        localPath != null ? Uri.file(localPath).toString() : repo.streamUrl(t.id);
    return MediaItem(
      id: t.id,
      title: t.name,
      album: t.albumName,
      artist: t.artistName,
      duration: t.duration,
      artUri: Uri.parse(art),
      extras: {
        'streamUrl': streamUrl,
        'jellyfinId': t.id,
        'isOffline': localPath != null,
      },
    );
  }
}
