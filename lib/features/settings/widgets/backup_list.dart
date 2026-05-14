import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/settings_group.dart';
import 'package:altsound/data/playlists/playlist_backup_repository.dart';

enum _BackupAction { restore, export, copyPath }

/// "Saved backups" group on the backup index screen. Renders each backup as
/// a tile that opens the detail view on tap, with a popup menu offering
/// Restore / Export / Copy path.
class BackupList extends StatelessWidget {
  const BackupList({
    required this.backups,
    required this.busy,
    required this.onOpen,
    required this.onRestore,
    required this.onExport,
    required this.onCopyPath,
    super.key,
  });

  final AsyncValue<List<PlaylistBackupFile>> backups;
  final bool busy;
  final void Function(PlaylistBackupFile backup) onOpen;
  final Future<void> Function(File file) onRestore;
  final Future<void> Function(File file) onExport;
  final Future<void> Function(String path) onCopyPath;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      label: 'Saved backups',
      children: backups.when(
        loading: () => const [
          ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Loading backups'),
          ),
        ],
        error: (e, _) => [
          ListTile(
            leading: const Icon(Icons.error_rounded, color: AppColors.error),
            title: const Text('Could not load backups'),
            subtitle: Text(
              e.toString(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
        data: (items) {
          if (items.isEmpty) {
            return const [
              ListTile(
                leading: Icon(Icons.inventory_2_rounded),
                title: Text('No backups yet'),
                subtitle: Text(
                  'Use Back up now, or keep automatic backups enabled.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ];
          }
          return [
            for (final backup in items)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(_formatDateTime(backup.createdAt)),
                subtitle: Text(
                  '${backup.playlistCount} playlists · ${backup.trackCount} songs · ${formatBytes(backup.sizeBytes)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                onTap: () => onOpen(backup),
                trailing: PopupMenuButton<_BackupAction>(
                  enabled: !busy,
                  onSelected: (action) {
                    switch (action) {
                      case _BackupAction.restore:
                        onRestore(backup.file);
                      case _BackupAction.export:
                        onExport(backup.file);
                      case _BackupAction.copyPath:
                        onCopyPath(backup.path);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _BackupAction.restore,
                      child: Text('Restore'),
                    ),
                    PopupMenuItem(
                      value: _BackupAction.export,
                      child: Text('Export bundle'),
                    ),
                    PopupMenuItem(
                      value: _BackupAction.copyPath,
                      child: Text('Copy path'),
                    ),
                  ],
                ),
              ),
          ];
        },
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
