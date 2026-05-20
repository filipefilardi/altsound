import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

class TrackMoreMenuButton extends ConsumerWidget {
  const TrackMoreMenuButton({required this.track, super.key});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (anchorCtx) => IconButton(
        icon: const Icon(
          PiconsRegular.dotsThreeVertical,
          color: AppColors.textSecondary,
        ),
        onPressed: () => showGlassPopover<void>(
          context: anchorCtx,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassPopoverItem(
                icon: PiconsRegular.listPlus,
                label: 'Add to playlist',
                onTap: () =>
                    openAddTrackToPlaylistFlow(context, ref, trackId: track.id),
              ),
              GlassPopoverItem(
                icon: PiconsRegular.queue,
                label: 'Play next',
                onTap: () async {
                  await ref.read(playerControllerProvider).playNext(track);
                  if (context.mounted) {
                    showAppSnackBar(context, 'Playing next');
                  }
                },
              ),
              GlassPopoverItem(
                icon: PiconsRegular.sparkle,
                label: 'Instant Mix',
                onTap: () => openInstantMixPage(
                  context,
                  ref,
                  itemId: track.id,
                  kind: InstantMixSeedKind.track,
                  title: track.name,
                ),
              ),
              GlassPopoverItem(
                icon: PiconsRegular.listPlus,
                label: 'Add to queue',
                onTap: () async {
                  await ref.read(playerControllerProvider).addToQueue(track);
                  if (context.mounted) {
                    showAppSnackBar(context, 'Added to queue');
                  }
                },
              ),
              if (track.albumId != null && track.albumId!.isNotEmpty)
                GlassPopoverItem(
                  icon: PiconsRegular.disc,
                  label: 'Go to album',
                  onTap: () => context.push('/album/${track.albumId}'),
                ),
              if (track.artistId != null && track.artistId!.isNotEmpty)
                GlassPopoverItem(
                  icon: PiconsRegular.user,
                  label: 'Go to artist',
                  onTap: () => context.push('/artist/${track.artistId}'),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
