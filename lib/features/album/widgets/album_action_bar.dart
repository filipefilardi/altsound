import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/media_action_row.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/album_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

/// Pinned action bar at the top of the album scroll view: play/shuffle,
/// Instant Mix, download, More menu, and the total duration.
class AlbumActionBar extends ConsumerWidget {
  const AlbumActionBar({required this.album, super.key});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isAlbumPlaying = ref.watch(isContextPlayingProvider(album.id));

    return MediaActionRow(
      actions: [
        IconButton(
          tooltip: 'Shuffle',
          icon: Icon(
            PiconsRegular.shuffle,
            color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
          ),
          onPressed: album.tracks.isEmpty
              ? null
              : () => ref.read(playerControllerProvider).toggleShuffle(),
        ),
        IconButton(
          tooltip: 'Instant Mix',
          icon: const Icon(PiconsRegular.sparkle),
          onPressed: album.tracks.isEmpty
              ? null
              : () => openInstantMixPage(
                  context,
                  ref,
                  itemId: album.id,
                  kind: InstantMixSeedKind.album,
                  title: album.name,
                ),
        ),
        AlbumDownloadButton(album: album),
        Builder(
          builder: (anchorCtx) => IconButton(
            tooltip: 'More actions',
            icon: const Icon(PiconsRegular.dotsThree),
            onPressed: album.tracks.isEmpty
                ? null
                : () => _showMoreActions(anchorCtx, context, ref),
          ),
        ),
      ],
      playControl: PlayPill(
        onTap: album.tracks.isEmpty
            ? null
            : () {
                final controller = ref.read(playerControllerProvider);
                if (isAlbumPlaying) {
                  controller.togglePlay();
                  return;
                }
                controller.playTracks(album.tracks, contextId: album.id);
              },
        icon: isAlbumPlaying ? PiconsFill.pause : PiconsFill.play,
        tooltip: isAlbumPlaying ? 'Pause' : 'Play',
      ),
      padding: EdgeInsets.zero,
    );
  }

  Future<void> _showMoreActions(
    BuildContext anchorCtx,
    BuildContext context,
    WidgetRef ref,
  ) {
    return showGlassPopover<void>(
      context: anchorCtx,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPopoverItem(
            icon: PiconsRegular.listPlus,
            label: 'Add album to playlist',
            onTap: () => openAddTracksToPlaylistFlow(
              context,
              ref,
              trackIds: album.tracks.map((t) => t.id).toList(),
            ),
          ),
          GlassPopoverItem(
            icon: PiconsRegular.listPlus,
            label: 'Add to queue',
            onTap: () async {
              final added = await ref
                  .read(playerControllerProvider)
                  .addTracksToQueue(album.tracks);
              if (!context.mounted) return;
              showAppSnackBar(
                context,
                'Added $added song${added == 1 ? '' : 's'} to queue',
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
