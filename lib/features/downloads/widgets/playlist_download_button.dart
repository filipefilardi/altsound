import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/download_preferences.dart';
import '../../../data/jellyfin/models/media_item.dart';

class PlaylistDownloadButton extends ConsumerWidget {
  const PlaylistDownloadButton({required this.playlist, super.key});
  final PlaylistDetail playlist;

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, DownloadManager manager) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove downloads'),
        content: Text('Remove all downloaded songs from "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      manager.deleteTracks(playlist.tracks.map((t) => t.id).toList());
      ref
          .read(downloadPreferencesProvider.notifier)
          .unsubscribePlaylist(playlist.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) return const SizedBox.shrink();
    if (playlist.tracks.isEmpty) return const SizedBox.shrink();

    final downloadedCount =
        playlist.tracks.where((t) => downloads.isDownloaded(t.id)).length;
    final inProgress =
        playlist.tracks.any((t) => downloads.progressFor(t.id) != null);
    final allDone = downloadedCount == playlist.tracks.length;

    if (allDone) {
      return IconButton(
        tooltip: 'Remove downloads',
        icon: const Icon(Icons.download_for_offline, color: AppColors.primary),
        onPressed: () => _confirmDelete(context, ref, manager),
      );
    }

    if (inProgress) {
      final activeProgresses = playlist.tracks
          .map((t) => downloads.progressFor(t.id))
          .whereType<double>()
          .toList();
      final overall = (downloadedCount +
              (activeProgresses.isEmpty
                  ? 0
                  : activeProgresses.reduce((a, b) => a + b))) /
          playlist.tracks.length;
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
            const Icon(Icons.downloading, size: 18, color: AppColors.textPrimary),
          ],
        ),
      );
    }

    return IconButton(
      tooltip: 'Download playlist',
      icon: const Icon(Icons.download_outlined, color: AppColors.textPrimary),
      onPressed: () {
        manager.enqueuePlaylist(playlist);
        ref
            .read(downloadPreferencesProvider.notifier)
            .subscribePlaylist(playlist.id);
      },
    );
  }
}
