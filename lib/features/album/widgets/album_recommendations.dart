import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/album/album_controller.dart';
import 'package:altsound/features/album/widgets/recommendation_shelf.dart';

/// "More from this artist" + "More Like This" rails shown below an album.
class AlbumRecommendations extends ConsumerWidget {
  const AlbumRecommendations({required this.album, super.key});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistId = album.artistId;
    final moreFromArtist = artistId == null || artistId.isEmpty
        ? const AsyncValue<List<BrowseItem>>.data([])
        : ref.watch(
            moreAlbumsByArtistProvider((
              artistId: artistId,
              excludeAlbumId: album.id,
            )),
          );
    final similarAlbums = ref.watch(
      similarAlbumsProvider((albumId: album.id, artistName: album.artistName)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (artistId != null && artistId.isNotEmpty)
          RecommendationShelf(
            title: 'More from ${album.artistName}',
            items: moreFromArtist,
          ),
        RecommendationShelf(title: 'More Like This', items: similarAlbums),
      ],
    );
  }
}
