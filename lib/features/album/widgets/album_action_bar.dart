import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/album_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

enum _CollectionAction { addToPlaylist, addToQueue }

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

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          PlayPill(
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
            icon: isAlbumPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            tooltip: isAlbumPlaying ? 'Pause' : 'Play',
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            tooltip: 'Shuffle',
            icon: Icon(
              Icons.shuffle_rounded,
              color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
            ),
            onPressed: album.tracks.isEmpty
                ? null
                : () => ref.read(playerControllerProvider).toggleShuffle(),
          ),
          IconButton(
            tooltip: 'Instant Mix',
            icon: const Icon(Icons.auto_awesome_rounded),
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
          IconButton(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: album.tracks.isEmpty
                ? null
                : () => _showMoreActions(context, ref),
          ),
          const Spacer(),
          Text(
            formatLongDuration(album.totalDuration),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_CollectionAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add album to playlist'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CollectionAction.addToPlaylist),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_queue_rounded),
              title: const Text('Add to queue'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CollectionAction.addToQueue),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final controller = ref.read(playerControllerProvider);
    switch (action) {
      case _CollectionAction.addToPlaylist:
        await openAddTracksToPlaylistFlow(
          context,
          ref,
          trackIds: album.tracks.map((t) => t.id).toList(),
        );
      case _CollectionAction.addToQueue:
        final added = await controller.addTracksToQueue(album.tracks);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $added song${added == 1 ? '' : 's'} to queue',
            ),
          ),
        );
    }
  }
}

/// Sliver delegate for pinning [AlbumActionBar] at the top of the scroll.
class AlbumActionBarDelegate extends SliverPersistentHeaderDelegate {
  AlbumActionBarDelegate({required this.child});
  final Widget child;

  @override
  double get minExtent => 72;
  @override
  double get maxExtent => 72;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AppColors.background, child: child);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
