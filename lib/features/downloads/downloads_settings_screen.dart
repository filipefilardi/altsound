import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/downloads/download_preferences.dart';

class DownloadsSettingsScreen extends ConsumerWidget {
  const DownloadsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(downloadPreferencesProvider);
    final notifier = ref.read(downloadPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Download settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _SectionLabel('Behaviour'),
          SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
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
            secondary: const Icon(Icons.wifi_outlined),
            title: const Text('WiFi only'),
            subtitle: const Text(
              'Pause downloads when not connected to WiFi.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.wifiOnly,
            onChanged: notifier.setWifiOnly,
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
