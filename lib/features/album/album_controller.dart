import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../../data/local/connectivity_provider.dart';

final albumProvider = FutureProvider.autoDispose.family<Album, String>((
  ref,
  id,
) {
  if (ref.watch(isOfflineProvider)) {
    final offlineAlbum = _buildOfflineAlbum(
      id,
      ref.watch(downloadManagerProvider),
    );
    if (offlineAlbum != null) return offlineAlbum;
    throw Exception('Album is not downloaded.');
  }
  return ref.watch(jellyfinRepositoryProvider).album(id);
});

typedef MoreAlbumsByArtistRequest = ({String artistId, String excludeAlbumId});
typedef SimilarAlbumsRequest = ({String albumId, String artistName});

final moreAlbumsByArtistProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, MoreAlbumsByArtistRequest>((ref, request) {
      if (ref.watch(isOfflineProvider)) return const [];
      return ref
          .watch(jellyfinRepositoryProvider)
          .moreAlbumsByArtist(
            artistId: request.artistId,
            excludeAlbumId: request.excludeAlbumId,
          );
    });

final similarAlbumsProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, SimilarAlbumsRequest>((ref, request) {
      if (ref.watch(isOfflineProvider)) return const [];
      return ref
          .watch(jellyfinRepositoryProvider)
          .similarAlbums(
            request.albumId,
            excludeArtistName: request.artistName,
          );
    });

Album? _buildOfflineAlbum(String albumId, DownloadsState downloads) {
  final tracks = downloads.tracks.values
      .where((track) => track.albumId == albumId)
      .toList();
  if (tracks.isEmpty) return null;
  tracks.sort((a, b) {
    final disc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
    if (disc != 0) return disc;
    return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
  });
  final first = tracks.first;
  return Album(
    id: albumId,
    name: first.albumName ?? 'Unknown Album',
    artistName: first.artistName,
    artistId: null,
    year: null,
    imageTag: first.imageTag,
    tracks: tracks.map((track) => track.toTrack()).toList(),
  );
}
