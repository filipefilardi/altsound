import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/artist/widgets/about_section.dart';
import 'package:altsound/features/artist/widgets/album_carousel_tile.dart';
import 'package:altsound/features/artist/widgets/artist_action_row.dart';
import 'package:altsound/features/artist/widgets/artist_loading.dart';
import 'package:altsound/features/artist/widgets/popular_tracks_section.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';

final artistProvider = FutureProvider.autoDispose.family<Artist, String>((
  ref,
  artistId,
) {
  return ref.read(jellyfinRepositoryProvider).artist(artistId);
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistProvider(artistId));
    return Scaffold(
      bottomNavigationBar: const MiniPlayerSlot(
        withTopDivider: true,
        reserveSpaceWhenEmpty: true,
      ),
      body: async.when(
        loading: () => const ArtistLoading(),
        error: (e, _) => SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: BackButton(onPressed: () => context.pop()),
              ),
              ErrorStateView(
                title: "Couldn't load this artist",
                message: e.toString(),
                onRetry: () => ref.invalidate(artistProvider(artistId)),
              ),
            ],
          ),
        ),
        data: (artist) => _ArtistView(artist: artist),
      ),
    );
  }
}

class _ArtistView extends ConsumerWidget {
  const _ArtistView({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(jellyfinRepositoryProvider);
    final imageUrl = repo.imageUrl(
      artist.id,
      imageTag: artist.imageTag,
      size: 600,
    );

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(artistProvider(artist.id).future),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            leading: BackButton(onPressed: () => context.pop()),
            title: Text(artist.name),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const ColoredBox(color: AppColors.surfaceElevated),
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: AppColors.surfaceElevated),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          AppColors.background.withValues(alpha: 0.6),
                          AppColors.background,
                        ],
                        stops: const [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          style: Theme.of(context).textTheme.headlineLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${artist.albums.length} albums',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: ArtistActionRow(artist: artist),
            ),
          ),
          if (artist.popularTracks.isNotEmpty)
            PopularTracksSection(artist: artist),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Discography',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: artist.albums.isEmpty
                        ? null
                        : () =>
                              context.push('/artist/${artist.id}/discography'),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
          ),
          if (artist.albums.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                child: Text(
                  'No albums found in your Jellyfin library.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: artist.albums.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) =>
                      AlbumCarouselTile(album: artist.albums[i]),
                ),
              ),
            ),
          AboutSection(artistName: artist.name),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }
}










