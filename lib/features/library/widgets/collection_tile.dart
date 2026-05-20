import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

/// Row in the library albums/artists collection list. Artists use a circular
/// avatar leading shape; albums use a rounded rectangle. Tapping navigates to
/// `/artist/{id}` or `/album/{id}`.
class CollectionTile extends ConsumerWidget {
  const CollectionTile({required this.item, required this.isArtist, super.key});

  final BrowseItem item;
  final bool isArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = item.imageTag == null
        ? null
        : repo.imageUrl(item.id, imageTag: item.imageTag, size: 200);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(isArtist ? 28 : 6),
        child: SizedBox(
          width: 52,
          height: 52,
          child: LocalOrNetworkImage(
            source: imageUrl,
            placeholderBuilder: (_) =>
                const ColoredBox(color: AppColors.surfaceElevated),
            errorBuilder: (_) => ColoredBox(
              color: AppColors.surfaceElevated,
              child: Icon(
                isArtist ? PiconsRegular.user : PiconsRegular.disc,
                color: AppColors.textTertiary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        item.subtitle ?? (isArtist ? 'Artist' : 'Album'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      onTap: () =>
          context.push(isArtist ? '/artist/${item.id}' : '/album/${item.id}'),
    );
  }
}
