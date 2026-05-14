import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/playlist_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

enum _PlaylistCollectionAction {
  edit,
  removeDuplicates,
  addToPlaylist,
  addToQueue,
  rename,
  delete,
}

/// Horizontal action row at the top of the playlist detail screen.
/// Owns playback controls (play/shuffle), Instant Mix, sort, download, and
/// the More menu (edit/dedupe/add to playlist/add to queue/rename/delete).
/// Wraps in [SingleChildScrollView] so the buttons can overflow horizontally.
class PlaylistActionRow extends ConsumerWidget {
  const PlaylistActionRow({
    required this.playlist,
    required this.visibleTracks,
    this.selectionActive = false,
    this.onSort,
    this.onEdit,
    this.duplicateCount = 0,
    this.onRemoveDuplicates,
    this.onRename,
    this.onDelete,
    super.key,
  });

  final PlaylistDetail playlist;
  final List<Track> visibleTracks;
  final bool selectionActive;
  final VoidCallback? onSort;
  final VoidCallback? onEdit;
  final int duplicateCount;
  final VoidCallback? onRemoveDuplicates;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isPlaylistPlaying = ref.watch(isContextPlayingProvider(playlist.id));
    final hasTracks = visibleTracks.isNotEmpty;
    final enabled = hasTracks && !selectionActive;
    final canOpenMore =
        !selectionActive &&
        (hasTracks || onEdit != null || onRename != null || onDelete != null);

    return Opacity(
      opacity: selectionActive ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: selectionActive,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayPill(
                onTap: enabled
                    ? () {
                        if (isPlaylistPlaying) {
                          controller.togglePlay();
                          return;
                        }
                        controller.playTracks(
                          visibleTracks,
                          contextId: playlist.id,
                        );
                      }
                    : null,
                icon: isPlaylistPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: isPlaylistPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: 'Shuffle',
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: shuffleEnabled
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
                onPressed: enabled ? () => controller.toggleShuffle() : null,
              ),
              IconButton(
                tooltip: 'Instant Mix',
                icon: const Icon(Icons.auto_awesome_rounded),
                onPressed: enabled
                    ? () => openInstantMixPage(
                        context,
                        ref,
                        itemId: playlist.id,
                        kind: InstantMixSeedKind.playlist,
                        title: playlist.name,
                      )
                    : null,
              ),
              IconButton(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_rounded),
                onPressed: enabled ? onSort : null,
              ),
              PlaylistDownloadButton(playlist: playlist),
              IconButton(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: canOpenMore
                    ? () => _showMoreActions(context, ref, controller)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreActions(
    BuildContext context,
    WidgetRef ref,
    PlayerController controller,
  ) async {
    final hasTracks = visibleTracks.isNotEmpty;
    final action = await showModalBottomSheet<_PlaylistCollectionAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasTracks) ...[
              if (onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Edit playlist'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_PlaylistCollectionAction.edit),
                ),
              if (duplicateCount > 0 && onRemoveDuplicates != null)
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: Text(
                    'Remove $duplicateCount duplicate${duplicateCount == 1 ? '' : 's'}',
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_PlaylistCollectionAction.removeDuplicates),
                ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_PlaylistCollectionAction.addToPlaylist),
              ),
              ListTile(
                leading: const Icon(Icons.add_to_queue_rounded),
                title: const Text('Add to queue'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_PlaylistCollectionAction.addToQueue),
              ),
            ],
            if (onRename != null || onDelete != null) ...[
              if (hasTracks) const Divider(height: 1),
            ],
            if (onRename != null)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Rename playlist'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_PlaylistCollectionAction.rename),
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: AppColors.error,
                ),
                title: const Text('Delete playlist'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_PlaylistCollectionAction.delete),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _PlaylistCollectionAction.addToPlaylist:
        await openAddTracksToPlaylistFlow(
          context,
          ref,
          trackIds: visibleTracks.map((t) => t.id).toList(),
        );
      case _PlaylistCollectionAction.addToQueue:
        final added = await controller.addTracksToQueue(visibleTracks);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $added song${added == 1 ? '' : 's'} to queue'),
          ),
        );
      case _PlaylistCollectionAction.delete:
        onDelete?.call();
      case _PlaylistCollectionAction.rename:
        onRename?.call();
      case _PlaylistCollectionAction.edit:
        onEdit?.call();
      case _PlaylistCollectionAction.removeDuplicates:
        onRemoveDuplicates?.call();
    }
  }
}
