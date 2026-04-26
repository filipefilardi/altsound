import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/player_providers.dart';
import '../player/widgets/playing_track_leading.dart';
import '../player/widgets/track_more_menu_button.dart';

final artistProvider = FutureProvider.family<Artist, String>((ref, artistId) {
  return ref.read(jellyfinRepositoryProvider).artist(artistId);
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistProvider(artistId));
    return Scaffold(
      bottomNavigationBar: const MiniPlayerSlot(withTopDivider: true),
      body: async.when(
        loading: () => const _ArtistLoading(),
        error: (e, _) => SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
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
    final imageUrl = repo.imageUrl(artist.id, imageTag: artist.imageTag, size: 600);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          stretch: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
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
                      const SizedBox(height: 4),
                      Text(
                        '${artist.albums.length} albums',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (artist.popularTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Popular',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _PopularTrackTile(
                index: i + 1,
                track: artist.popularTracks[i],
              ),
              childCount: artist.popularTracks.length,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 4, 8),
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
                      : () => context.push('/artist/${artist.id}/discography'),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
        ),
        if (artist.albums.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: artist.albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _AlbumCarouselTile(album: artist.albums[i]),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _AlbumCarouselTile extends ConsumerWidget {
  const _AlbumCarouselTile({required this.album});

  final BrowseItem album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = (album.imageTag == null || album.imageTag!.isEmpty)
        ? null
        : repo.imageUrl(album.id, imageTag: album.imageTag, size: 400);
    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/album/${album.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl == null
                    ? Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(
                          Icons.album,
                          color: AppColors.textTertiary,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.surfaceElevated),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(
                            Icons.album,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.subtitle ?? 'Album',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularTrackTile extends ConsumerWidget {
  const _PopularTrackTile({required this.index, required this.track});

  final int index;
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack =
        current != null && current.extras?['jellyfinId'] == track.id;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl =
        repo.imageUrl(track.imageItemId, imageTag: track.imageTag, size: 200);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SearchTrackArtwork(
        imageUrl: imageUrl,
        jellyfinTrackId: track.id,
        isArtistShape: false,
      ),
      title: Text(
        '$index. ${track.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrentTrack ? AppColors.primary : null,
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        track.albumName ?? 'Single',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
      onTap: () => ref.read(playerControllerProvider).playTracks([track]),
    );
  }
}

class _ArtistLoading extends StatelessWidget {
  const _ArtistLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: Skeleton.box(
                width: double.infinity,
                height: double.infinity,
                radius: 0,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Skeleton.line(width: 120, height: 16),
                const SizedBox(height: 12),
                for (int i = 0; i < 5; i++) ...[
                  Skeleton.line(height: 14),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
