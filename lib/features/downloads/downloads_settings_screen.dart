import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/download_preferences.dart';

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
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _SectionLabel('Behaviour'),
          SwitchListTile(
            secondary: const Icon(Icons.sync_rounded),
            title: const Text('Auto-download new songs'),
            subtitle: const Text(
              'When you open a downloaded album or playlist, any new tracks are queued automatically.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.autoDownload,
            onChanged: notifier.setAutoDownload,
          ),
          const _SectionLabel('Network'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_rounded),
            title: const Text('WiFi only'),
            subtitle: const Text(
              'Pause downloads when not connected to WiFi.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.wifiOnly,
            onChanged: notifier.setWifiOnly,
          ),
          const _SectionLabel('Storage'),
          ListTile(
            leading: const Icon(Icons.bar_chart_rounded),
            title: const Text('Downloaded tracks'),
            subtitle: Text(
              '${downloads.tracks.length} tracks across $albumCount albums',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: Text(
              _formatBytes(downloads.totalSizeBytes),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Saved playlists'),
            subtitle: Text(
              '${downloads.playlists.length} playlists',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (downloads.queueLength > 0)
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Queued downloads'),
              subtitle: Text(
                '${downloads.queueLength} tracks waiting',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ListTile(
            leading: const Icon(
              Icons.delete_forever_rounded,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All downloads removed')));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
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
