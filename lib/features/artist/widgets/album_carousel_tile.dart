import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

/// 150-wide tile shown inside the artist's horizontal albums carousel.
class AlbumCarouselTile extends ConsumerWidget {
  const AlbumCarouselTile({required this.album, super.key});

  final BrowseItem album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = (album.imageTag == null || album.imageTag!.isEmpty)
        ? null
        : repo.imageUrl(album.id, imageTag: album.imageTag, size: 400);
    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.push('/album/${album.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: imageUrl == null
                    ? const ArtworkPlaceholder()
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.surfaceElevated),
                        errorWidget: (_, __, ___) => const ArtworkPlaceholder(),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              album.subtitle ?? 'Album',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
