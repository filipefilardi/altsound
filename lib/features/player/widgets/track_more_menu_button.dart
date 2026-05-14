import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
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
          Icons.more_vert_rounded,
          color: AppColors.textSecondary,
        ),
        onPressed: () => showGlassPopover<void>(
          context: anchorCtx,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassPopoverItem(
                icon: Icons.playlist_add_rounded,
                label: 'Add to playlist',
                onTap: () =>
                    openAddTrackToPlaylistFlow(context, ref, trackId: track.id),
              ),
              GlassPopoverItem(
                icon: Icons.queue_music_rounded,
                label: 'Play next',
                onTap: () async {
                  await ref.read(playerControllerProvider).playNext(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playing next')),
                    );
                  }
                },
              ),
              GlassPopoverItem(
                icon: Icons.auto_awesome_rounded,
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
                icon: Icons.add_to_queue_rounded,
                label: 'Add to queue',
                onTap: () async {
                  await ref.read(playerControllerProvider).addToQueue(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to queue')),
                    );
                  }
                },
              ),
              if (track.albumId != null && track.albumId!.isNotEmpty)
                GlassPopoverItem(
                  icon: Icons.album_rounded,
                  label: 'Go to album',
                  onTap: () => context.push('/album/${track.albumId}'),
                ),
              if (track.artistId != null && track.artistId!.isNotEmpty)
                GlassPopoverItem(
                  icon: Icons.person_rounded,
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
