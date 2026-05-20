import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

/// 120×120 playlist cover. When the playlist has 2+ unique album covers,
/// renders a 2×2 mosaic of those album arts; otherwise falls back to the
/// first track's art (or a placeholder if no artwork available).
class PlaylistArtwork extends ConsumerWidget {
  const PlaylistArtwork({required this.playlist, super.key});

  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(jellyfinRepositoryProvider);
    final uniqueAlbumTracks = <Track>[];
    final seenAlbumIds = <String>{};

    for (final track in playlist.tracks) {
      final albumId = track.albumImageItemId ?? track.albumId ?? track.id;
      if (seenAlbumIds.add(albumId)) {
        uniqueAlbumTracks.add(track);
      }
      if (uniqueAlbumTracks.length == 4) break;
    }

    if (uniqueAlbumTracks.length > 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 120,
          height: 120,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
            ),
            itemCount: 4,
            itemBuilder: (_, index) {
              final track = uniqueAlbumTracks[index % uniqueAlbumTracks.length];
              if (track.imageTag == null || track.imageTag!.isEmpty) {
                return const ArtworkPlaceholder(icon: PiconsRegular.queue);
              }
              final artId = track.albumImageItemId ?? track.id;
              final imageUrl = repo.imageUrl(
                artId,
                imageTag: track.imageTag,
                size: 300,
              );
              return CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: AppColors.surfaceElevated),
                errorWidget: (_, _, _) =>
                    const ArtworkPlaceholder(icon: PiconsRegular.queue),
              );
            },
          ),
        ),
      );
    }

    final firstTrack = playlist.tracks.firstOrNull;
    final artId = firstTrack?.albumImageItemId ?? firstTrack?.id ?? playlist.id;
    final artTag = firstTrack?.imageTag ?? playlist.imageTag;
    final imageUrl = (artTag == null || artTag.isEmpty)
        ? null
        : repo.imageUrl(artId, imageTag: artTag, size: 300);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 120,
        height: 120,
        child: imageUrl == null
            ? const ArtworkPlaceholder(icon: PiconsRegular.queue)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: AppColors.surfaceElevated),
                errorWidget: (_, _, _) =>
                    const ArtworkPlaceholder(icon: PiconsRegular.queue),
              ),
      ),
    );
  }
}
