import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/jellyfin/models/media_item.dart';
import '../player_providers.dart';
import 'add_track_to_playlist_sheet.dart';

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
                title: const Text('Play next'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_TrackAction.playNext),
              ),
              ListTile(
                leading: const Icon(Icons.add_to_queue),
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
      case _TrackAction.playNext:
        await ref.read(playerControllerProvider).playNext(track);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playing next')),
          );
        }
      case _TrackAction.addToQueue:
        final added =
            await ref.read(playerControllerProvider).addToQueue(track);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(added ? 'Added to queue' : 'Already in queue'),
            ),
          );
        }
      case _TrackAction.goToAlbum:
        if (track.albumId != null && track.albumId!.isNotEmpty) {
          context.push('/album/${track.albumId}');
        }
      case _TrackAction.goToArtist:
        if (track.artistId != null && track.artistId!.isNotEmpty) {
          context.push('/artist/${track.artistId}');
        }
      case _TrackAction.addToPlaylist:
        await openAddTrackToPlaylistFlow(context, ref, trackId: track.id);
    }
  }
}

enum _TrackAction {
  addToPlaylist,
  playNext,
  addToQueue,
  goToAlbum,
  goToArtist,
}
