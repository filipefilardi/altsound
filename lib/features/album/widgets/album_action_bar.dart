import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
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
                ? PhosphorIconsRegular.pause
                : PhosphorIconsRegular.play,
            tooltip: isAlbumPlaying ? 'Pause' : 'Play',
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            tooltip: 'Shuffle',
            icon: Icon(
              PhosphorIconsRegular.shuffle,
              color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
            ),
            onPressed: album.tracks.isEmpty
                ? null
                : () => ref.read(playerControllerProvider).toggleShuffle(),
          ),
          IconButton(
            tooltip: 'Instant Mix',
            icon: const Icon(PhosphorIconsRegular.sparkle),
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
              icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
              onPressed: album.tracks.isEmpty
                  ? null
                  : () => _showMoreActions(anchorCtx, context, ref),
            ),
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
            icon: PhosphorIconsRegular.listPlus,
            label: 'Add album to playlist',
            onTap: () => openAddTracksToPlaylistFlow(
              context,
              ref,
              trackIds: album.tracks.map((t) => t.id).toList(),
            ),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.listPlus,
            label: 'Add to queue',
            onTap: () async {
              final added = await ref
                  .read(playerControllerProvider)
                  .addTracksToQueue(album.tracks);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Added $added song${added == 1 ? '' : 's'} to queue',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
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
