import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/settings_group.dart';
import 'package:altsound/data/playlists/playlist_backup_repository.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';
import 'package:altsound/features/settings/widgets/backup_list.dart';
import 'package:altsound/features/settings/widgets/backup_playlist_tile.dart';
import 'package:altsound/features/settings/widgets/backup_summary.dart';

class PlaylistBackupScreen extends ConsumerStatefulWidget {
  const PlaylistBackupScreen({super.key});

  @override
  ConsumerState<PlaylistBackupScreen> createState() =>
      _PlaylistBackupScreenState();
}

class _PlaylistBackupScreenState extends ConsumerState<PlaylistBackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(playlistBackupPreferencesProvider);
    final backups = ref.watch(playlistBackupFilesProvider);
    final latest = backups.maybeWhen(
      data: (items) => items.firstOrNull,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Playlist backups')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.miniPlayerInset,
        ),
        children: [
          SettingsGroup(
            label: 'Safety',
            children: [
              SwitchListTile(
                secondary: const Icon(PhosphorIconsRegular.arrowsClockwise),
                title: const Text('Automatic backups'),
                subtitle: Text(
                  prefs.lastAutoBackupAt == null
                      ? 'Runs daily after you open the app'
                      : 'Last automatic backup ${_formatDateTime(prefs.lastAutoBackupAt!)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                value: prefs.autoBackupEnabled,
                onChanged: _busy
                    ? null
                    : (value) => ref
                          .read(playlistBackupPreferencesProvider.notifier)
                          .setAutoBackupEnabled(value),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.cloudArrowUp),
                title: const Text('Back up now'),
                subtitle: const Text(
                  'Save every Jellyfin playlist and track order locally.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                enabled: !_busy,
                onTap: _createBackup,
              ),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.arrowsCounterClockwise,
                ),
                title: const Text('Restore latest backup'),
                subtitle: Text(
                  latest == null
                      ? 'No backup saved yet'
                      : '${latest.playlistCount} playlists · ${latest.trackCount} songs',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                enabled: !_busy && latest != null,
                onTap: latest == null
                    ? null
                    : () => _restoreBackup(latest.file),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsGroup(
            label: 'Portability',
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsRegular.shareNetwork),
                title: const Text('Export migration bundle'),
                subtitle: Text(
                  latest == null
                      ? 'Create a backup first'
                      : 'Creates JSON, CSV, and M3U8 files',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                enabled: !_busy && latest != null,
                onTap: latest == null ? null : () => _exportBackup(latest.file),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsRegular.fileText),
                title: const Text('Import backup from path'),
                subtitle: const Text(
                  'Import an AltSound playlist JSON backup.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                enabled: !_busy,
                onTap: _importBackup,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          BackupList(
            backups: backups,
            busy: _busy,
            onOpen: _openBackup,
            onRestore: _restoreBackup,
            onExport: _exportBackup,
            onCopyPath: _copyPath,
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    await _run(() async {
      final auth = ref.read(authControllerProvider);
      final session = auth is AuthAuthenticated ? auth.session : null;
      final backup = await ref
          .read(playlistBackupRepositoryProvider)
          .createBackup(session: session);
      ref.invalidate(playlistBackupFilesProvider);
      if (!mounted) return;
      _showMessage(
        'Backed up ${backup.playlistCount} playlists and ${backup.trackCount} songs',
      );
    });
  }

  Future<void> _restoreBackup(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore playlists?'),
        content: const Text(
          'AltSound will create missing playlists and add missing songs by Jellyfin track ID. Existing songs will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final result = await ref
          .read(playlistBackupRepositoryProvider)
          .restoreBackup(file);
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      _showMessage(
        'Restored ${result.tracksAdded} songs'
        '${result.tracksMatchedByMetadata > 0 ? ' · ${result.tracksMatchedByMetadata} matched by metadata' : ''}'
        ' · ${result.playlistsCreated} playlists created',
      );
    });
  }

  Future<void> _exportBackup(File file) async {
    await _run(() async {
      final repo = ref.read(playlistBackupRepositoryProvider);
      final bundle = await repo.exportBackupBundle(file);
      await repo.copyPathToClipboard(bundle.directory.path);
      if (!mounted) return;
      _showMessage('Exported bundle. Folder path copied.');
    });
  }

  Future<void> _importBackup() async {
    final path = await _showPathDialog(context);
    if (path == null || path.trim().isEmpty) return;
    await _run(() async {
      final imported = await ref
          .read(playlistBackupRepositoryProvider)
          .importBackupFromPath(path);
      ref.invalidate(playlistBackupFilesProvider);
      if (!mounted) return;
      _showMessage('Imported ${imported.playlistCount} playlists from backup');
    });
  }

  Future<void> _copyPath(String path) async {
    await ref.read(playlistBackupRepositoryProvider).copyPathToClipboard(path);
    if (!mounted) return;
    _showMessage('Path copied');
  }

  void _openBackup(PlaylistBackupFile backup) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistBackupDetailScreen(backup: backup),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }
}

class PlaylistBackupDetailScreen extends ConsumerWidget {
  const PlaylistBackupDetailScreen({required this.backup, super.key});

  final PlaylistBackupFile backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistBackupDocumentProvider(backup.path));
    return Scaffold(
      appBar: AppBar(title: const Text('Backup contents')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Could not read backup: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (document) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.miniPlayerInset,
          ),
          children: [
            BackupSummary(document: document, backup: backup),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              label: 'Playlists',
              children: document.playlists.isEmpty
                  ? const [
                      ListTile(
                        leading: Icon(PhosphorIconsRegular.playlist),
                        title: Text('No playlists in this backup'),
                      ),
                    ]
                  : [
                      for (final playlist in document.playlists)
                        BackupPlaylistTile(playlist: playlist),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showPathDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import backup'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: '/path/to/backup.json'),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
          child: const Text('Import'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
