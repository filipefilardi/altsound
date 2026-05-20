import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/settings_group.dart';
import 'package:altsound/data/playlists/playlist_backup_repository.dart';

/// "Snapshot" details card shown on the backup detail screen — created date,
/// contents counts, originating server, and the underlying file path.
class BackupSummary extends StatelessWidget {
  const BackupSummary({
    required this.document,
    required this.backup,
    super.key,
  });

  final PlaylistBackupDocument document;
  final PlaylistBackupFile backup;

  @override
  Widget build(BuildContext context) {
    final source = document.source;
    return SettingsGroup(
      label: 'Snapshot',
      children: [
        ListTile(
          leading: const Icon(PiconsRegular.calendarCheck),
          title: const Text('Created'),
          subtitle: Text(
            _formatDateTime(document.createdAt),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.musicNotes),
          title: const Text('Contents'),
          subtitle: Text(
            '${backup.playlistCount} playlists · ${backup.trackCount} songs · ${formatBytes(backup.sizeBytes)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.hardDrives),
          title: const Text('Source'),
          subtitle: Text(
            [
                  if (source.username != null && source.username!.isNotEmpty)
                    source.username!,
                  if (source.serverUrl != null && source.serverUrl!.isNotEmpty)
                    source.serverUrl!,
                ].isEmpty
                ? source.app
                : [
                    if (source.username != null && source.username!.isNotEmpty)
                      source.username!,
                    if (source.serverUrl != null &&
                        source.serverUrl!.isNotEmpty)
                      source.serverUrl!,
                  ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.folder),
          title: const Text('File'),
          subtitle: Text(
            backup.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
