import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/media_item.dart';
import '../player_providers.dart';

class TrackMoreMenuButton extends ConsumerWidget {
  const TrackMoreMenuButton({
    required this.track,
    super.key,
  });

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onPressed: () async {
        final action = await _showActionsBottomSheet(context);
        if (action == null || !context.mounted) return;
        await _onAction(context, ref, action);
      },
    );
  }

  Future<_TrackAction?> _showActionsBottomSheet(BuildContext context) {
    return showModalBottomSheet<_TrackAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to playlist'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_TrackAction.addToPlaylist),
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to queue'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_TrackAction.addToQueue),
              ),
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Go to album'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_TrackAction.goToAlbum),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Go to artist'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_TrackAction.goToArtist),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _TrackAction action,
  ) async {
    switch (action) {
      case _TrackAction.addToQueue:
        await ref.read(playerControllerProvider).addTrackToQueue(track);
      case _TrackAction.goToAlbum:
        if (track.albumId != null && track.albumId!.isNotEmpty) {
          context.push('/album/${track.albumId}');
        }
      case _TrackAction.goToArtist:
        if (track.artistId != null && track.artistId!.isNotEmpty) {
          context.push('/artist/${track.artistId}');
        }
      case _TrackAction.addToPlaylist:
        await _showAddToPlaylistDialog(context, ref);
    }
  }

  Future<void> _showAddToPlaylistDialog(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final playlists = await repo.playlists();
    if (!context.mounted) return;
    if (playlists.isEmpty) {
      await _showCreatePlaylistDialog(context, ref, autoAddTrack: true);
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('Add to playlist'),
              ),
              ...playlists.map(
                (playlist) => ListTile(
                  title: Text(playlist.name),
                  onTap: () => Navigator.of(sheetContext).pop(playlist.id),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.playlist_add_circle_outlined),
                title: const Text('Create new playlist'),
                onTap: () => Navigator.of(sheetContext).pop('__create__'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (selectedId == null) return;
    if (selectedId == '__create__') {
      await _showCreatePlaylistDialog(context, ref, autoAddTrack: true);
      return;
    }
    final selected = playlists.firstWhere((playlist) => playlist.id == selectedId);
    await repo.addTrackToPlaylist(trackId: track.id, playlistId: selectedId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to ${selected.name}')),
    );
  }

  Future<void> _showCreatePlaylistDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool autoAddTrack,
  }) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final playlistName = name?.trim() ?? '';
    if (playlistName.isEmpty) return;

    final repo = ref.read(jellyfinRepositoryProvider);
    final created = await repo.createPlaylist(playlistName);
    if (autoAddTrack) {
      await repo.addTrackToPlaylist(trackId: track.id, playlistId: created.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playlist "${created.name}" created')),
    );
  }
}

enum _TrackAction {
  addToPlaylist,
  addToQueue,
  goToAlbum,
  goToArtist,
}
