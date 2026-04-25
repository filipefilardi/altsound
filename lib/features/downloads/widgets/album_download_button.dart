import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/jellyfin/models/media_item.dart';

class AlbumDownloadButton extends ConsumerWidget {
  const AlbumDownloadButton({required this.album, super.key});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) return const SizedBox.shrink();
    if (album.tracks.isEmpty) return const SizedBox.shrink();

    final downloadedCount = album.tracks
        .where((t) => downloads.isDownloaded(t.id))
        .length;
    final inProgress = album.tracks
        .any((t) => downloads.progressFor(t.id) != null);
    final allDone = downloadedCount == album.tracks.length;

    if (allDone) {
      return IconButton(
        tooltip: 'Remove downloads',
        icon: const Icon(Icons.download_done, color: AppColors.primary),
        onPressed: () => manager.deleteAlbum(album.id),
      );
    }

    if (inProgress) {
      final activeProgresses = album.tracks
          .map((t) => downloads.progressFor(t.id))
          .whereType<double>()
          .toList();
      final overall = (downloadedCount +
              (activeProgresses.isEmpty
                  ? 0
                  : activeProgresses.reduce((a, b) => a + b))) /
          album.tracks.length;
      return SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: overall.clamp(0.0, 1.0),
              strokeWidth: 2.5,
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
            ),
            const Icon(Icons.downloading,
                size: 18, color: AppColors.textPrimary),
          ],
        ),
      );
    }

    return IconButton(
      tooltip: 'Download album',
      icon: const Icon(Icons.download_outlined,
          color: AppColors.textPrimary),
      onPressed: () => manager.enqueueAlbum(album),
    );
  }
}
