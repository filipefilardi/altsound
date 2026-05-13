import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Downloads aren't available on web",
          message: 'Open AltSound on iOS or Android to download for offline.',
        ),
      );
    }

    final byAlbum = <String, List<DownloadedTrack>>{};
    for (final t in downloads.tracks.values) {
      byAlbum.putIfAbsent(t.albumId ?? 'unknown', () => []).add(t);
    }
    final albumIds = byAlbum.keys.toList()
      ..sort((a, b) {
        final aDate = byAlbum[a]!
            .map((t) => t.downloadedAt)
            .reduce((x, y) => x.isAfter(y) ? x : y);
        final bDate = byAlbum[b]!
            .map((t) => t.downloadedAt)
            .reduce((x, y) => x.isAfter(y) ? x : y);
        return bDate.compareTo(aDate);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: albumIds.isEmpty
          ? const EmptyState(
              icon: Icons.download_rounded,
              title: 'No downloads yet',
              message: 'Tap the download icon on any album to keep it offline.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: albumIds.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _DownloadsSummary(
                    trackCount: downloads.tracks.length,
                    albumCount: albumIds.length,
                    totalSize: downloads.totalSizeBytes,
                    queueLength: downloads.queueLength,
                  );
                }
                if (i == 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
                    child: Text(
                      'READY OFFLINE',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  );
                }

                final albumId = albumIds[i - 2];
                final tracks = byAlbum[albumId]!;
                final first = tracks.first;
                return _DownloadedAlbumTile(
                  albumId: albumId,
                  trackCount: tracks.length,
                  totalSize: tracks.fold(0, (s, t) => s + t.fileSize),
                  totalDuration: tracks.fold(
                    Duration.zero,
                    (s, t) => s + t.duration,
                  ),
                  albumName: first.albumName ?? 'Unknown album',
                  artistName: first.artistName,
                  imageItemId: first.imageItemId,
                  imageTag: first.imageTag,
                );
              },
            ),
    );
  }
}

class _DownloadsSummary extends StatelessWidget {
  const _DownloadsSummary({
    required this.trackCount,
    required this.albumCount,
    required this.totalSize,
    required this.queueLength,
  });

  final int trackCount;
  final int albumCount;
  final int totalSize;
  final int queueLength;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.download_for_offline_rounded,
              color: AppColors.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$albumCount albums ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '$trackCount tracks · ${_formatBytes(totalSize)}'
                  '${queueLength > 0 ? ' · $queueLength queued' : ''}',
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
        ],
      ),
    );
  }
}

class _DownloadedAlbumTile extends ConsumerWidget {
  const _DownloadedAlbumTile({
    required this.albumId,
    required this.trackCount,
    required this.totalSize,
    required this.totalDuration,
    required this.albumName,
    required this.artistName,
    required this.imageItemId,
    required this.imageTag,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canOpen ? () => context.push('/album/$albumId') : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.album_rounded,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 6),
                      Text(
                        '$trackCount tracks · ${formatLongDuration(totalDuration)} · ${_formatBytes(totalSize)}',
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
                const SizedBox(width: 8),
                PopupMenuButton<_DownloadAction>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
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
                          Icons.delete_rounded,
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

enum _DownloadAction { remove }

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}
