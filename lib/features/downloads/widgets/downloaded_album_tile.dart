import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';

enum _DownloadAction { remove }

/// Album-level entry in the Downloads screen list. Tappable when the album
/// is known (so it can open the album page); offers a "Remove download"
/// action via popup menu that confirms before deleting from disk.
class DownloadedAlbumTile extends ConsumerWidget {
  const DownloadedAlbumTile({
    required this.albumId,
    required this.trackCount,
    required this.totalSize,
    required this.totalDuration,
    required this.albumName,
    required this.artistName,
    required this.imageItemId,
    required this.imageTag,
    super.key,
  });

  final String albumId;
  final int trackCount;
  final int totalSize;
  final Duration totalDuration;
  final String albumName;
  final String artistName;
  final String imageItemId;
  final String? imageTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    final canOpen = albumId != 'unknown';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canOpen ? () => context.push('/album/$albumId') : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: CachedNetworkImage(
                      imageUrl: repo.imageUrl(
                        imageItemId,
                        imageTag: imageTag,
                        size: 200,
                      ),
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, _, _) => const Icon(
                        PhosphorIconsRegular.disc,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        albumName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '$trackCount tracks · ${formatLongDuration(totalDuration)} · ${formatBytes(totalSize)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PopupMenuButton<_DownloadAction>(
                  icon: const Icon(
                    PhosphorIconsRegular.dotsThreeVertical,
                    color: AppColors.textSecondary,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _DownloadAction.remove:
                        _confirmDelete(context, manager);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _DownloadAction.remove,
                      child: ListTile(
                        leading: Icon(
                          PhosphorIconsRegular.trash,
                          color: AppColors.error,
                        ),
                        title: Text('Remove download'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DownloadManager manager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove download'),
        content: Text('Remove "$albumName" from your downloads?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) manager.deleteAlbum(albumId);
  }
}
