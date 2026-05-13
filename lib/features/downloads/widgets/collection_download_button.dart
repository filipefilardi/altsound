import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/wifi_required_dialog.dart';

/// Shared download-button shell for "a fixed list of tracks" — albums and
/// playlists. Surfaces four states (downloaded, in-progress, blocked-on-wifi,
/// default) computed from the supplied [tracks].
///
/// Variants only differ in copy and the side-effect callbacks ([onEnqueue],
/// [onDelete]), so each caller passes those in.
class CollectionDownloadButton extends ConsumerWidget {
  const CollectionDownloadButton({
    required this.tracks,
    required this.confirmDialogTitle,
    required this.confirmDialogContent,
    required this.downloadTooltip,
    required this.onEnqueue,
    required this.onDelete,
    super.key,
  });

  final List<Track> tracks;

  /// Title shown in the "Remove download(s)?" confirmation dialog.
  final String confirmDialogTitle;

  /// Content shown in the "Remove download(s)?" confirmation dialog.
  final String confirmDialogContent;

  /// Tooltip on the default download icon, e.g. "Download album".
  final String downloadTooltip;

  /// Called after the WiFi-only gate passes. Should enqueue the tracks AND
  /// subscribe the collection in [downloadPreferencesProvider].
  final VoidCallback onEnqueue;

  /// Called after the user confirms the remove dialog. Should delete the
  /// downloaded tracks AND unsubscribe.
  final VoidCallback onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmDialogTitle),
        content: Text(confirmDialogContent),
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
    if (confirmed == true) onDelete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);

    if (!manager.supported) return const SizedBox.shrink();
    if (tracks.isEmpty) return const SizedBox.shrink();

    final downloadedCount = tracks
        .where((t) => downloads.isDownloaded(t.id))
        .length;
    final inProgress = tracks.any((t) => downloads.progressFor(t.id) != null);
    final allDone = downloadedCount == tracks.length;
    final isQueuedButBlocked =
        !allDone &&
        !inProgress &&
        downloads.isBlockedByWifiOnly &&
        tracks.any((t) => downloads.isQueued(t.id));

    if (allDone) {
      return IconButton(
        tooltip: 'Remove downloads',
        icon: const Icon(
          Icons.download_for_offline_rounded,
          color: AppColors.primary,
        ),
        onPressed: () => _confirmDelete(context),
      );
    }

    if (inProgress) {
      final activeProgresses = tracks
          .map((t) => downloads.progressFor(t.id))
          .whereType<double>()
          .toList();
      final overall =
          (downloadedCount +
              (activeProgresses.isEmpty
                  ? 0
                  : activeProgresses.reduce((a, b) => a + b))) /
          tracks.length;
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
            const Icon(
              Icons.downloading_rounded,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      );
    }

    if (isQueuedButBlocked) {
      return IconButton(
        tooltip: 'Waiting for WiFi — tap to change settings',
        icon: const Icon(
          Icons.wifi_off_rounded,
          color: AppColors.textSecondary,
        ),
        onPressed: () => showWifiRequiredDialog(context),
      );
    }

    return IconButton(
      tooltip: downloadTooltip,
      icon: const Icon(Icons.download_rounded, color: AppColors.textPrimary),
      onPressed: () async {
        final canDownload = await ref
            .read(downloadPreferencesProvider.notifier)
            .canDownloadNow();
        if (!context.mounted) return;
        if (!canDownload) {
          showWifiRequiredDialog(context);
          return;
        }
        onEnqueue();
      },
    );
  }
}
