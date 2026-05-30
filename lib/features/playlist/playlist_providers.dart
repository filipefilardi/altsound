import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
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
          final downloads = ref.watch(downloadManagerProvider);
          final offlinePlaylist = _buildOfflinePlaylist(playlistId, downloads);
          if (offlinePlaylist != null) return offlinePlaylist;
          throw Exception('Playlist is not downloaded.');
        }
        try {
          final playlist = await ref
              .read(jellyfinRepositoryProvider)
              .playlist(playlistId);
          await ref
              .read(downloadManagerProvider.notifier)
              .cachePlaylistMetadata(playlist);
          return playlist;
        } catch (error) {
          final downloads = ref.read(downloadManagerProvider);
          final offlinePlaylist = _buildOfflinePlaylist(playlistId, downloads);
          if (offlinePlaylist != null && _isServerUnavailableError(error)) {
            _scheduleRetry(ref);
            return offlinePlaylist;
          }
          rethrow;
        }
      } finally {
        keepAlive.close();
      }
    });

final likedSongsPlaylistProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(isOfflineProvider)) return null;
  try {
    return await ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
  } catch (error) {
    if (_isServerUnavailableError(error)) return null;
    rethrow;
  }
});

final playlistsProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(isOfflineProvider)) {
    final downloads = ref.watch(downloadManagerProvider);
    return _offlinePlaylistsFromDownloads(downloads);
  }
  try {
    return await ref.read(jellyfinRepositoryProvider).playlists();
  } catch (error) {
    if (_isServerUnavailableError(error)) {
      final downloads = ref.read(downloadManagerProvider);
      _scheduleRetry(ref);
      return _offlinePlaylistsFromDownloads(downloads);
    }
    rethrow;
  }
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

List<BrowseItem> _offlinePlaylistsFromDownloads(DownloadsState downloads) {
  final playlists =
      downloads.playlists.values
          .where((playlist) => playlist.trackIds.any(downloads.isDownloaded))
          .map(
            (playlist) => BrowseItem(
              id: playlist.id,
              name: playlist.name,
              kind: MediaKind.playlist,
              subtitle: 'Playlist',
              imageTag: playlist.imageTag,
              childCount: playlist.trackIds.length,
            ),
          )
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return playlists;
}

bool _isServerUnavailableError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return true;
    }
    return error.error is SocketException;
  }
  return error is SocketException;
}

void _scheduleRetry(Ref ref) {
  final timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}
