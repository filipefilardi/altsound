import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/lidarr/lidarr_config.dart';
import '../auth/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final lidarr = ref.watch(lidarrConfigProvider);

    final session = auth is AuthAuthenticated ? auth.session : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (session != null) ...[
            const _SectionLabel('Jellyfin server'),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(session.username),
              subtitle: Text(
                session.serverUrl,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
          const _SectionLabel('Lidarr'),
          ListTile(
            leading: const Icon(Icons.travel_explore_outlined),
            title: const Text('Lidarr connection'),
            subtitle: Text(
              lidarr == null ? 'Not connected' : lidarr.url,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => context.push('/settings/lidarr'),
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: const Text('Lidarr requests'),
            subtitle: const Text(
              'Discover and request music via Lidarr',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => context.push('/discover'),
          ),
          const _SectionLabel('Storage'),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Downloads'),
            subtitle: Text(
              '${downloads.tracks.length} tracks · ${_formatBytes(downloads.totalSizeBytes)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => context.push('/downloads'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Download settings'),
            subtitle: const Text(
              'Auto-download, WiFi only',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => context.push('/settings/downloads'),
          ),
          const _SectionLabel('Account'),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Sign out',
                style: TextStyle(color: AppColors.error)),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.pop();
            },
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'AltSound 0.1.0',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
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
