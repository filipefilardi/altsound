import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/artist_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

enum _ArtistCollectionAction { addToPlaylist, addToQueue }

/// Action row for the artist detail screen: Play/Pause + Shuffle + Instant
/// Mix + Download + More (add to playlist / add to queue).
class ArtistActionRow extends ConsumerWidget {
  const ArtistActionRow({required this.artist, super.key});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isArtistPlaying = ref.watch(isContextPlayingProvider(artist.id));
    final hasTracks = artist.popularTracks.isNotEmpty;

    return Row(
      children: [
        PlayPill(
          onTap: hasTracks
              ? () {
                  final controller = ref.read(playerControllerProvider);
                  if (isArtistPlaying) {
                    controller.togglePlay();
                    return;
                  }
                  controller.playTracks(
                    artist.popularTracks,
                    contextId: artist.id,
                  );
                }
              : null,
          icon: isArtistPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          tooltip: isArtistPlaying ? 'Pause' : 'Play',
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton(
          tooltip: 'Shuffle',
          icon: Icon(
            Icons.shuffle_rounded,
            color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
          ),
          onPressed: hasTracks
              ? () => ref.read(playerControllerProvider).toggleShuffle()
              : null,
        ),
        IconButton(
          tooltip: 'Instant Mix',
          icon: const Icon(Icons.auto_awesome_rounded),
          onPressed: hasTracks
              ? () => openInstantMixPage(
                  context,
                  ref,
                  itemId: artist.id,
                  kind: InstantMixSeedKind.artist,
                  title: artist.name,
                )
              : null,
        ),
        ArtistDownloadButton(artist: artist),
        IconButton(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: hasTracks ? () => _showMoreActions(context, ref) : null,
        ),
      ],
    );
  }

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_ArtistCollectionAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add top songs to playlist'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ArtistCollectionAction.addToPlaylist),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_queue_rounded),
              title: const Text('Add to queue'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ArtistCollectionAction.addToQueue),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final controller = ref.read(playerControllerProvider);
    switch (action) {
      case _ArtistCollectionAction.addToPlaylist:
        await openAddTracksToPlaylistFlow(
          context,
          ref,
          trackIds: artist.popularTracks.map((t) => t.id).toList(),
        );
      case _ArtistCollectionAction.addToQueue:
        final added = await controller.addTracksToQueue(artist.popularTracks);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $added song${added == 1 ? '' : 's'} to queue'),
          ),
        );
    }
  }
}
