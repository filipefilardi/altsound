import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/play_pill.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../../data/musicbrainz/wikipedia_repository.dart';
import '../downloads/widgets/artist_download_button.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/player_providers.dart';
import '../player/widgets/add_track_to_playlist_sheet.dart';
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ArtistActionRow(artist: artist),
          ),
        ),
        if (artist.popularTracks.isNotEmpty)
          _PopularTracksSection(artist: artist),
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
        _AboutSection(artistName: artist.name),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

const _kDefaultTrackCount = 5;

class _PopularTracksSection extends StatefulWidget {
  const _PopularTracksSection({required this.artist});

  final Artist artist;

  @override
  State<_PopularTracksSection> createState() => _PopularTracksSectionState();
}

class _PopularTracksSectionState extends State<_PopularTracksSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tracks = widget.artist.popularTracks;
    final shown = _expanded ? tracks : tracks.take(_kDefaultTrackCount).toList();

    return SliverMainAxisGroup(
      slivers: [
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
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

class _AboutSection extends ConsumerWidget {
  const _AboutSection({required this.artistName});
  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bio = ref.watch(artistBioProvider(artistName)).value;
    if (bio == null || bio.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ExpandableBio(bio: bio),
          ],
        ),
      ),
    );
  }
}

class _ExpandableBio extends StatefulWidget {
  const _ExpandableBio({required this.bio});
  final String bio;

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.bio,
        maxLines: _expanded ? null : 3,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

class _ArtistActionRow extends ConsumerWidget {
  const _ArtistActionRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackStateProvider).value;
    final currentMediaItem = ref.watch(currentMediaItemProvider).value;
    final shuffleEnabled = ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isArtistPlaying = playbackState?.playing == true &&
        (currentMediaItem?.extras?['contextId'] as String?) == artist.id;
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
          icon: isArtistPlaying ? Icons.pause : Icons.play_arrow,
          tooltip: isArtistPlaying ? 'Pause' : 'Play',
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Shuffle',
          icon: Icon(
            Icons.shuffle,
            color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
          ),
          onPressed: hasTracks
              ? () => ref.read(playerControllerProvider).toggleShuffle()
              : null,
        ),
        ArtistDownloadButton(artist: artist),
        IconButton(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert),
          onPressed: hasTracks
              ? () async {
                  final action = await showModalBottomSheet<_ArtistCollectionAction>(
                    context: context,
                    showDragHandle: true,
                    builder: (sheetContext) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.playlist_add),
                            title: const Text('Add to playlist'),
                            onTap: () => Navigator.of(sheetContext)
                                .pop(_ArtistCollectionAction.addToPlaylist),
                          ),
                          ListTile(
                            leading: const Icon(Icons.add_to_queue),
                            title: const Text('Add to queue'),
                            onTap: () => Navigator.of(sheetContext)
                                .pop(_ArtistCollectionAction.addToQueue),
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
                      final added =
                          await controller.addTracksToQueue(artist.popularTracks);
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
              : null,
        ),
      ],
    );
  }
}

enum _ArtistCollectionAction { addToPlaylist, addToQueue }

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
  const _PopularTrackTile({
    required this.index,
    required this.track,
    required this.allTracks,
    required this.contextId,
  });

  final int index;
  final Track track;
  final List<Track> allTracks;
  final String contextId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack =
        current != null && current.extras?['jellyfinId'] == track.id;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl =
        repo.imageUrl(track.imageItemId, imageTag: track.imageTag, size: 200);
    final isDownloaded =
        ref.watch(downloadManagerProvider).isDownloaded(track.id);

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
          if (isDownloaded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.download_for_offline,
                  size: 14, color: AppColors.primary),
            ),
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
      onTap: () => ref
          .read(playerControllerProvider)
          .playTracks(
            allTracks,
            startIndex: index - 1,
            contextId: contextId,
            selectedTrack: true,
          ),
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
