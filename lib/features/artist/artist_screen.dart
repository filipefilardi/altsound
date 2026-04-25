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
      appBar: AppBar(title: const Text('Artist')),
      bottomNavigationBar: const MiniPlayerSlot(withTopDivider: true),
      body: async.when(
        loading: () => const _ArtistLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load this artist",
          message: e.toString(),
          onRetry: () => ref.invalidate(artistProvider(artistId)),
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
    final imageUrl = repo.imageUrl(artist.id, imageTag: artist.imageTag, size: 320);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: SizedBox(
                width: 80,
                height: 80,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.person, color: AppColors.textTertiary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    style: Theme.of(context).textTheme.headlineSmall,
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
        const SizedBox(height: 18),
        if (artist.popularTracks.isNotEmpty) ...[
          Text('Popular', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...artist.popularTracks.asMap().entries.map(
            (entry) => _PopularTrackTile(
              index: entry.key + 1,
              track: entry.value,
            ),
          ),
          const SizedBox(height: 18),
        ],
        Row(
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
        const SizedBox(height: 8),
        if (artist.albums.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No albums found in your Jellyfin library.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artist.albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _AlbumCarouselTile(
                album: artist.albums[i],
              ),
            ),
          ),
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
    final imageUrl = repo.imageUrl(album.id, imageTag: album.imageTag, size: 400);
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
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.album, color: AppColors.textTertiary),
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
  const _PopularTrackTile({
    required this.index,
    required this.track,
  });

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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Row(
            children: [
              Skeleton.box(width: 80, height: 80, radius: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180, height: 20),
                    SizedBox(height: 8),
                    Skeleton.line(width: 90, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Skeleton.line(width: 120, height: 16),
          const SizedBox(height: 12),
          for (int i = 0; i < 8; i++) ...[
            Skeleton.line(height: 14),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
