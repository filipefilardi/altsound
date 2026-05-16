import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/features/downloads/widgets/section_label.dart';

class DownloadsSettingsScreen extends ConsumerWidget {
  const DownloadsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(downloadPreferencesProvider);
    final notifier = ref.read(downloadPreferencesProvider.notifier);
    final downloads = ref.watch(downloadManagerProvider);
    final manager = ref.read(downloadManagerProvider.notifier);
    final albumCount = downloads.tracks.values
        .map((t) => t.albumId)
        .whereType<String>()
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Download settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.miniPlayerInset),
        children: [
          const SectionLabel('Behaviour'),
          SwitchListTile(
            secondary: const Icon(PhosphorIconsRegular.arrowsClockwise),
            title: const Text('Auto-download new songs'),
            subtitle: const Text(
              'When you open a downloaded album or playlist, any new tracks are queued automatically.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.autoDownload,
            onChanged: notifier.setAutoDownload,
          ),
          const SectionLabel('Network'),
          SwitchListTile(
            secondary: const Icon(PhosphorIconsRegular.wifiHigh),
            title: const Text('WiFi only'),
            subtitle: const Text(
              'Pause downloads when not connected to WiFi.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.wifiOnly,
            onChanged: notifier.setWifiOnly,
          ),
          const SectionLabel('Storage'),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.chartBar),
            title: const Text('Downloaded tracks'),
            subtitle: Text(
              '${downloads.tracks.length} tracks across $albumCount albums',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: Text(
              formatBytes(downloads.totalSizeBytes),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.playlist),
            title: const Text('Saved playlists'),
            subtitle: Text(
              '${downloads.playlists.length} playlists',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (downloads.queueLength > 0)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.clock),
              title: const Text('Queued downloads'),
              subtitle: Text(
                '${downloads.queueLength} tracks waiting',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ListTile(
            leading: const Icon(
              PhosphorIconsRegular.trash,
              color: AppColors.error,
            ),
            title: const Text(
              'Remove all downloads',
              style: TextStyle(color: AppColors.error),
            ),
            subtitle: const Text(
              'Delete all downloaded tracks and offline playlists from this device.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            enabled:
                downloads.tracks.isNotEmpty || downloads.playlists.isNotEmpty,
            onTap: () => _confirmRemoveAll(context, manager),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmRemoveAll(
  BuildContext context,
  DownloadManager manager,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove all downloads?'),
      content: const Text(
        'This will delete all downloaded songs and playlists from this device. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(
            'Remove all',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await manager.clearAllDownloads();
    if (context.mounted) {
      showAppSnackBar(context, 'All downloads removed');
    }
  }
}
