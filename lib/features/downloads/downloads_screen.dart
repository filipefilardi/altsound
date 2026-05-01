import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/downloaded_track.dart';
import '../../data/jellyfin/jellyfin_repository.dart';

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
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '${downloads.tracks.length} tracks · ${_formatBytes(downloads.totalSizeBytes)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (downloads.queueLength > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${downloads.queueLength} queued',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: albumIds.isEmpty
          ? const EmptyState(
              icon: Icons.download_rounded,
              title: 'No downloads yet',
              message: 'Tap the download icon on any album to keep it offline.',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: albumIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
              itemBuilder: (_, i) {
                final albumId = albumIds[i];
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

    return ListTile(
      onTap: albumId == 'unknown'
          ? null
          : () => context.push('/album/$albumId'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: CachedNetworkImage(
            imageUrl: repo.imageUrl(imageItemId, imageTag: imageTag, size: 200),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.album_rounded, color: AppColors.textTertiary),
          ),
        ),
      ),
      title: Text(albumName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$artistName · $trackCount tracks · ${_formatBytes(totalSize)} · ${formatLongDuration(totalDuration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_rounded, color: AppColors.textSecondary),
        onPressed: () => _confirmDelete(context, manager),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}
