import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/settings_group.dart';
import 'package:altsound/data/downloads/download_manager.dart';

class LibraryGroup extends ConsumerWidget {
  const LibraryGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);

    return SettingsGroup(
      label: 'Library',
      children: [
        ListTile(
          leading: const Icon(PiconsRegular.downloadSimple),
          title: const Text('Downloads'),
          subtitle: Text(
            '${downloads.tracks.length} tracks · ${formatBytes(downloads.totalSizeBytes)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => context.push('/downloads'),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.slidersHorizontal),
          title: const Text('Download settings'),
          subtitle: const Text(
            'Auto-download, WiFi only',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => context.push('/settings/downloads'),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.cloudArrowUp),
          title: const Text('Playlist backups'),
          subtitle: const Text(
            'Automatic restore points and migration exports',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => context.push('/settings/playlist-backups'),
        ),
      ],
    );
  }
}
