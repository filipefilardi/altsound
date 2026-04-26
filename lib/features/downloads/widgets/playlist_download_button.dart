import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      manager.deletePlaylist(playlist.id);
      ref
          .read(downloadPreferencesProvider.notifier)
          .unsubscribePlaylist(playlist.id);
    }
  }

  void _showWifiOnlyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WiFi required'),
        content: const Text(
          'WiFi-only downloads is enabled and you\'re not on WiFi. '
          'Connect to WiFi or turn off this setting to download.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/settings/downloads');
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
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
    final isQueuedButBlocked = !allDone &&
        !inProgress &&
        downloads.isBlockedByWifiOnly &&
        playlist.tracks.any((t) => downloads.isQueued(t.id));

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

    if (isQueuedButBlocked) {
      return IconButton(
        tooltip: 'Waiting for WiFi — tap to change settings',
        icon: const Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary),
        onPressed: () => _showWifiOnlyDialog(context),
      );
    }

    return IconButton(
      tooltip: 'Download playlist',
      icon: const Icon(Icons.download_outlined, color: AppColors.textPrimary),
      onPressed: () async {
        final canDownload = await ref
            .read(downloadPreferencesProvider.notifier)
            .canDownloadNow();
        if (!context.mounted) return;
        if (!canDownload) {
          _showWifiOnlyDialog(context);
          return;
        }
        manager.enqueuePlaylist(playlist);
        ref
            .read(downloadPreferencesProvider.notifier)
            .subscribePlaylist(playlist.id);
      },
    );
  }
}
