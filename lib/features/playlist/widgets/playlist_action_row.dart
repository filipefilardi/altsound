import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/media_action_row.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/playlist_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

/// Horizontal action row at the top of the playlist detail screen.
/// Owns playback controls (play/shuffle/download), plus a More menu with
/// lower-frequency actions like sort and instant mix.
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
  final ValueChanged<BuildContext>? onSort;
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
        child: MediaActionRow(
          actions: [
            IconButton(
              tooltip: 'Shuffle',
              icon: Icon(
                PiconsRegular.shuffle,
                color: shuffleEnabled
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              onPressed: enabled ? () => controller.toggleShuffle() : null,
            ),
            PlaylistDownloadButton(playlist: playlist),
            Builder(
              builder: (anchorCtx) => IconButton(
                tooltip: 'More actions',
                icon: const Icon(PiconsRegular.dotsThree),
                onPressed: canOpenMore
                    ? () =>
                          _showMoreActions(anchorCtx, context, ref, controller)
                    : null,
              ),
            ),
          ],
          playControl: PlayPill(
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
            icon: isPlaylistPlaying ? PiconsFill.pause : PiconsFill.play,
            tooltip: isPlaylistPlaying ? 'Pause' : 'Play',
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Future<void> _showMoreActions(
    BuildContext anchorCtx,
    BuildContext context,
    WidgetRef ref,
    PlayerController controller,
  ) {
    final hasTracks = visibleTracks.isNotEmpty;
    final showDivider = hasTracks && (onRename != null || onDelete != null);
    return showGlassPopover<void>(
      context: anchorCtx,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTracks) ...[
            if (onSort != null)
              GlassPopoverItem(
                icon: PiconsRegular.sortAscending,
                label: 'Sort',
                onTap: () => onSort!.call(anchorCtx),
              ),
            GlassPopoverItem(
              icon: PiconsRegular.sparkle,
              label: 'Instant Mix',
              onTap: () => openInstantMixPage(
                context,
                ref,
                itemId: playlist.id,
                kind: InstantMixSeedKind.playlist,
                title: playlist.name,
              ),
            ),
            if (onEdit != null)
              GlassPopoverItem(
                icon: PiconsRegular.notePencil,
                label: 'Edit playlist',
                onTap: () => onEdit!.call(),
              ),
            if (duplicateCount > 0 && onRemoveDuplicates != null)
              GlassPopoverItem(
                icon: PiconsRegular.copy,
                label:
                    'Remove $duplicateCount duplicate${duplicateCount == 1 ? '' : 's'}',
                onTap: () => onRemoveDuplicates!.call(),
              ),
            GlassPopoverItem(
              icon: PiconsRegular.listPlus,
              label: 'Add to playlist',
              onTap: () => openAddTracksToPlaylistFlow(
                context,
                ref,
                trackIds: visibleTracks.map((t) => t.id).toList(),
              ),
            ),
            GlassPopoverItem(
              icon: PiconsRegular.listPlus,
              label: 'Add to queue',
              onTap: () async {
                final added = await controller.addTracksToQueue(visibleTracks);
                if (!context.mounted) return;
                showAppSnackBar(
                  context,
                  'Added $added song${added == 1 ? '' : 's'} to queue',
                );
              },
            ),
          ],
          if (showDivider) const Divider(height: 1, color: Color(0x33FFFFFF)),
          if (onRename != null)
            GlassPopoverItem(
              icon: PiconsRegular.pencilSimple,
              label: 'Rename playlist',
              onTap: () => onRename!.call(),
            ),
          if (onDelete != null)
            GlassPopoverItem(
              icon: PiconsRegular.trash,
              label: 'Delete playlist',
              destructive: true,
              onTap: () => onDelete!.call(),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
