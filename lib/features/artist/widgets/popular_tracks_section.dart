import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/artist/widgets/popular_track_tile.dart';

const _kDefaultTrackCount = 5;

/// "Popular" tracks sliver for the artist screen. Shows the top 5 tracks by
/// default and expands to the full list on tap of the footer toggle.
class PopularTracksSection extends StatefulWidget {
  const PopularTracksSection({required this.artist, super.key});

  final Artist artist;

  @override
  State<PopularTracksSection> createState() => _PopularTracksSectionState();
}

class _PopularTracksSectionState extends State<PopularTracksSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tracks = widget.artist.popularTracks;
    final shown = _expanded
        ? tracks
        : tracks.take(_kDefaultTrackCount).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              'Popular',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => PopularTrackTile(
              rank: i + 1,
              track: shown[i],
              allTracks: tracks,
              contextId: widget.artist.id,
            ),
            childCount: shown.length,
          ),
        ),
        if (tracks.length > _kDefaultTrackCount)
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _expanded
                          ? 'Show less'
                          : 'See all ${tracks.length} songs',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
