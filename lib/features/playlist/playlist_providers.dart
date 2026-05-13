import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/local/connectivity_provider.dart';

final playlistProvider = FutureProvider.autoDispose
    .family<PlaylistDetail, String>((ref, playlistId) async {
      final keepAlive = ref.keepAlive();
      try {
        if (ref.watch(isOfflineProvider)) {
          final offlinePlaylist = _buildOfflinePlaylist(
            playlistId,
            ref.watch(downloadManagerProvider),
          );
          if (offlinePlaylist != null) return offlinePlaylist;
          throw Exception('Playlist is not downloaded.');
        }
        return await ref.read(jellyfinRepositoryProvider).playlist(playlistId);
      } finally {
        keepAlive.close();
      }
    });

final likedSongsPlaylistProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
});

final playlistsProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).playlists();
});

PlaylistDetail? _buildOfflinePlaylist(
  String playlistId,
  DownloadsState downloads,
) {
  final saved = downloads.playlists[playlistId];
  if (saved == null) return null;
  final tracks = saved.trackIds
      .map((id) => downloads.tracks[id])
      .whereType<DownloadedTrack>()
      .map((track) => track.toTrack())
      .toList();
  if (tracks.isEmpty) return null;
  return PlaylistDetail(
    id: playlistId,
    name: saved.name,
    imageTag: saved.imageTag,
    tracks: tracks,
  );
}
