import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/playlists/playlist_backup_repository.dart';
import '../auth/auth_controller.dart';
import '../playlist/playlist_providers.dart';

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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          _SettingsGroup(
            label: 'Safety',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.autorenew_rounded),
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
                leading: const Icon(Icons.backup_rounded),
                title: const Text('Back up now'),
                subtitle: const Text(
                  'Save every Jellyfin playlist and track order locally.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                enabled: !_busy,
                onTap: _createBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore_rounded),
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
          const SizedBox(height: 24),
          _SettingsGroup(
            label: 'Portability',
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
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
                leading: const Icon(Icons.file_open_rounded),
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
          const SizedBox(height: 24),
          _BackupList(
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BackupList extends StatelessWidget {
  const _BackupList({
    required this.backups,
    required this.busy,
    required this.onOpen,
    required this.onRestore,
    required this.onExport,
    required this.onCopyPath,
  });

  final AsyncValue<List<PlaylistBackupFile>> backups;
  final bool busy;
  final void Function(PlaylistBackupFile backup) onOpen;
  final Future<void> Function(File file) onRestore;
  final Future<void> Function(File file) onExport;
  final Future<void> Function(String path) onCopyPath;

  @override
  Widget build(BuildContext context) {
    return _SettingsGroup(
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
                  '${backup.playlistCount} playlists · ${backup.trackCount} songs · ${_formatBytes(backup.sizeBytes)}',
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

enum _BackupAction { restore, export, copyPath }

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
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not read backup: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (document) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            _BackupSummary(document: document, backup: backup),
            const SizedBox(height: 24),
            _SettingsGroup(
              label: 'Playlists',
              children: document.playlists.isEmpty
                  ? const [
                      ListTile(
                        leading: Icon(Icons.playlist_remove_rounded),
                        title: Text('No playlists in this backup'),
                      ),
                    ]
                  : [
                      for (final playlist in document.playlists)
                        _BackupPlaylistTile(playlist: playlist),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupSummary extends StatelessWidget {
  const _BackupSummary({required this.document, required this.backup});

  final PlaylistBackupDocument document;
  final PlaylistBackupFile backup;

  @override
  Widget build(BuildContext context) {
    final source = document.source;
    return _SettingsGroup(
      label: 'Snapshot',
      children: [
        ListTile(
          leading: const Icon(Icons.event_available_rounded),
          title: const Text('Created'),
          subtitle: Text(
            _formatDateTime(document.createdAt),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.library_music_rounded),
          title: const Text('Contents'),
          subtitle: Text(
            '${backup.playlistCount} playlists · ${backup.trackCount} songs · ${_formatBytes(backup.sizeBytes)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_rounded),
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
          leading: const Icon(Icons.folder_rounded),
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

class _BackupPlaylistTile extends StatelessWidget {
  const _BackupPlaylistTile({required this.playlist});

  final PlaylistBackupPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.queue_music_rounded),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${playlist.tracks.length} songs · ${_formatDuration(Duration(milliseconds: playlist.durationMs))}',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      children: [
        if (playlist.tracks.isEmpty)
          const ListTile(
            title: Text('No songs saved'),
            contentPadding: EdgeInsets.only(left: 72, right: 16),
          )
        else
          for (final track in playlist.tracks)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: Text(
                '${track.position}. ${track.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (track.artistText.isNotEmpty) track.artistText,
                  if (track.album != null && track.album!.isNotEmpty)
                    track.album!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: track.jellyfinTrackId == null
                  ? const Icon(
                      Icons.link_off_rounded,
                      color: AppColors.textTertiary,
                      size: 18,
                    )
                  : null,
            ),
      ],
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(const Divider(height: 1, indent: 56));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
