import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/features/home/recommendations_provider.dart';
import 'package:altsound/features/player/instant_mix.dart';

/// Personalized "for you" recommendations on Home: a "Because you played"
/// anchor (the user's #1 song from the last 7 days) plus 4 "Inspired by"
/// artist mixes (drawn daily from the user's top 8 of the same window), plus
/// one day-rotating discovery seed from your top tracks. Hides itself entirely
/// when there's no data — i.e. when the Playback Reporting plugin isn't
/// installed and there's no cached snapshot from a previous online session.
class ForYouSection extends ConsumerWidget {
  const ForYouSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(homeRecommendationsProvider).value;
    if (recs == null) return const SizedBox.shrink();

    final repo = ref.read(jellyfinRepositoryProvider);
    final tiles = <Widget>[];

    final topSong = recs.topSong;
    if (topSong != null) {
      tiles.add(
        _ForYouCard(
          eyebrow: 'BECAUSE YOU PLAYED',
          title: topSong.name,
          subtitle: topSong.artistName,
          imageUrl: topSong.imageTag == null
              ? null
              : repo.imageUrl(topSong.imageItemId, imageTag: topSong.imageTag),
          fallbackIcon: PhosphorIconsRegular.musicNote,
          onTap: () => openInstantMixPage(
            context,
            ref,
            itemId: topSong.id,
            kind: InstantMixSeedKind.track,
            title: topSong.name,
          ),
        ),
      );
    }

    final discovery = recs.discoveryTrack;
    if (discovery != null) {
      tiles.add(
        _ForYouCard(
          eyebrow: 'DISCOVER WITH',
          title: discovery.name,
          subtitle: discovery.artistName,
          imageUrl: discovery.imageTag == null
              ? null
              : repo.imageUrl(
                  discovery.imageItemId,
                  imageTag: discovery.imageTag,
                ),
          fallbackIcon: PhosphorIconsRegular.compass,
          onTap: () => openInstantMixPage(
            context,
            ref,
            itemId: discovery.id,
            kind: InstantMixSeedKind.track,
            title: discovery.name,
          ),
        ),
      );
    }

    for (final artist in recs.topArtists) {
      tiles.add(
        _ForYouCard(
          eyebrow: 'INSPIRED BY',
          title: artist.name,
          subtitle: 'Mix from artist',
          imageUrl: artist.imageTag == null
              ? null
              : repo.imageUrl(artist.id, imageTag: artist.imageTag),
          fallbackIcon: PhosphorIconsRegular.user,
          onTap: () => openInstantMixPage(
            context,
            ref,
            itemId: artist.id,
            kind: InstantMixSeedKind.artist,
            title: artist.name,
          ),
        ),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Text(
            'For you',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
      ],
    );
  }
}

class _ForYouCard extends StatelessWidget {
  const _ForYouCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.onTap,
  });

  static const double width = 168;

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = ArtworkPlaceholder(
      icon: fallbackIcon,
      iconSize: 48,
      iconColor: AppColors.primary,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      splashColor: AppColors.primary.withValues(alpha: 0.06),
      highlightColor: AppColors.primary.withValues(alpha: 0.03),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: imageUrl == null
                        ? fallback
                        : LocalOrNetworkImage(
                            source: imageUrl,
                            placeholderBuilder: (_) => fallback,
                            errorBuilder: (_) => fallback,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
