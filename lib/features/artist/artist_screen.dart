import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/core/widgets/pinned_action_bar_delegate.dart';
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
      bottomNavigationBar: const MiniPlayerSlot(),
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

class _ArtistView extends ConsumerStatefulWidget {
  const _ArtistView({required this.artist});

  final Artist artist;

  @override
  ConsumerState<_ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends ConsumerState<_ArtistView> {
  Color _backdrop = AppColors.surfaceElevated;

  @override
  void initState() {
    super.initState();
    _extractPalette();
  }

  @override
  void didUpdateWidget(covariant _ArtistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.id != widget.artist.id ||
        oldWidget.artist.imageTag != widget.artist.imageTag) {
      _extractPalette();
    }
  }

  Future<void> _extractPalette() async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final url = repo.imageUrl(
      widget.artist.id,
      imageTag: widget.artist.imageTag,
      size: 200,
    );
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        size: const Size(200, 200),
        maximumColorCount: 8,
      );
      final c =
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.darkVibrantColor?.color;
      if (c != null && mounted) {
        setState(
          () => _backdrop = Color.alphaBlend(
            c.withValues(alpha: 0.55),
            AppColors.background,
          ),
        );
      }
    } catch (_) {
      // ignore palette failures
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
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
            expandedHeight: 380,
            pinned: true,
            stretch: true,
            leading: BackButton(onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _backdrop,
                      Color.alphaBlend(
                        _backdrop.withValues(alpha: 0.5),
                        AppColors.background,
                      ),
                      AppColors.background,
                    ],
                    stops: [0.0, 0.62, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                                spreadRadius: -6,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 220,
                              height: 220,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const SizedBox(
                                width: 220,
                                height: 220,
                                child: ArtworkPlaceholder(iconSize: 64),
                              ),
                              errorWidget: (_, _, _) => const SizedBox(
                                width: 220,
                                height: 220,
                                child: ArtworkPlaceholder(iconSize: 64),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          artist.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${artist.popularTracks.length} songs • ${artist.albums.length} albums',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: PinnedActionBarDelegate(
              child: ArtistActionRow(artist: artist),
            ),
          ),
          if (artist.popularTracks.isNotEmpty)
            PopularTracksSection(artist: artist),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
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
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: Text(
                  'No albums found in your Jellyfin library.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  itemCount: artist.albums.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
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
