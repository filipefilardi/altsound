import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/artist_download_button.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';

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
    final totalDuration = artist.popularTracks.fold(
      Duration.zero,
      (sum, track) => sum + track.duration,
    );
    final meta = hasTracks
        ? '${artist.popularTracks.length} songs'
        : '${artist.albums.length} albums';

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMeta = constraints.maxWidth >= 430;
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
                  ? PhosphorIconsFill.pause
                  : PhosphorIconsFill.play,
              tooltip: isArtistPlaying ? 'Pause' : 'Play',
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton(
              tooltip: 'Shuffle',
              icon: Icon(
                PhosphorIconsRegular.shuffle,
                color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
              ),
              onPressed: hasTracks
                  ? () => ref.read(playerControllerProvider).toggleShuffle()
                  : null,
            ),
            IconButton(
              tooltip: 'Instant Mix',
              icon: const Icon(PhosphorIconsRegular.sparkle),
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
            Builder(
              builder: (anchorCtx) => IconButton(
                tooltip: 'More actions',
                icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
                onPressed: hasTracks
                    ? () => _showMoreActions(anchorCtx, context, ref)
                    : null,
              ),
            ),
            if (showMeta) ...[
              const Spacer(),
              Flexible(
                child: Text(
                  '$meta • ${formatLongDuration(totalDuration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
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
            label: 'Add top songs to playlist',
            onTap: () => openAddTracksToPlaylistFlow(
              context,
              ref,
              trackIds: artist.popularTracks.map((t) => t.id).toList(),
            ),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.listPlus,
            label: 'Add to queue',
            onTap: () async {
              final added = await ref
                  .read(playerControllerProvider)
                  .addTracksToQueue(artist.popularTracks);
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

class ArtistActionBarDelegate extends SliverPersistentHeaderDelegate {
  ArtistActionBarDelegate({required this.child});

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
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
