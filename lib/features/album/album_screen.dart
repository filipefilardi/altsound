import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/album_download_button.dart';
import 'package:altsound/features/home/widgets/media_card.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';
import 'package:altsound/features/player/widgets/track_more_menu_button.dart';
import 'package:altsound/features/album/album_controller.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumProvider(albumId));
    final downloads = ref.watch(downloadManagerProvider);

    ref.listen(albumProvider(albumId), (prev, next) {
      if (prev?.value == null && next.value != null) {
        final prefs = ref.read(downloadPreferencesProvider);
        if (prefs.autoDownload && prefs.isAlbumSubscribed(next.value!.id)) {
          ref.read(downloadManagerProvider.notifier).enqueueAlbum(next.value!);
        }
      }
    });

    return Scaffold(
      bottomNavigationBar: const MiniPlayerSlot(
        withTopDivider: true,
        reserveSpaceWhenEmpty: true,
      ),
      body: async.when(
        loading: () {
          // If we have local tracks, skip the spinner while remote metadata loads.
          final offlineAlbum = _buildOfflineAlbum(albumId, downloads);
          if (offlineAlbum != null) {
            return _AlbumView(album: offlineAlbum);
          }
          return const _AlbumLoading();
        },
        error: (e, _) {
          final offlineAlbum = _buildOfflineAlbum(albumId, downloads);
          if (offlineAlbum != null) return _AlbumView(album: offlineAlbum);
          return SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  child: BackButton(onPressed: () => context.pop()),
                ),
                ErrorStateView(
                  title: "Couldn't load this album",
                  message: e.toString(),
                  onRetry: () => ref.invalidate(albumProvider(albumId)),
                ),
              ],
            ),
          );
        },
        data: (album) => _AlbumView(album: album),
      ),
    );
  }

  static Album? _buildOfflineAlbum(String albumId, DownloadsState downloads) {
    final tracks = downloads.tracks.values
        .where((t) => t.albumId == albumId)
        .toList();
    if (tracks.isEmpty) return null;
    tracks.sort((a, b) {
      final disc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
      if (disc != 0) return disc;
      return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
    });
    final first = tracks.first;
    return Album(
      id: albumId,
      name: first.albumName ?? 'Unknown Album',
      artistName: first.artistName,
      artistId: null,
      year: null,
      imageTag: first.imageTag,
      tracks: tracks.map((t) => t.toTrack()).toList(),
    );
  }
}

class _AlbumLoading extends StatelessWidget {
  const _AlbumLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Skeleton.group(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.box(width: 220, height: 220),
                const SizedBox(height: 16),
                Skeleton.line(width: 220, height: 18),
                const SizedBox(height: 8),
                Skeleton.line(width: 140, height: 12),
                const SizedBox(height: 28),
                for (int i = 0; i < 8; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Skeleton.box(width: 28, height: 28, radius: 6),
                        const SizedBox(width: 14),
                        Expanded(child: Skeleton.line(height: 14)),
                        const SizedBox(width: 14),
                        Skeleton.line(width: 36, height: 12),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumView extends ConsumerStatefulWidget {
  const _AlbumView({required this.album});
  final Album album;

  @override
  ConsumerState<_AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends ConsumerState<_AlbumView> {
  Color _backdrop = AppColors.surfaceElevated;

  @override
  void initState() {
    super.initState();
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final url = repo.imageUrl(
      widget.album.id,
      imageTag: widget.album.imageTag,
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
    final album = widget.album;
    final repo = ref.read(jellyfinRepositoryProvider);
    final imageUrl = repo.imageUrl(
      album.id,
      imageTag: album.imageTag,
      size: 600,
    );

    return RefreshIndicator(
      onRefresh: () async {
        final artistId = album.artistId;
        ref.invalidate(
          similarAlbumsProvider((
            albumId: album.id,
            artistName: album.artistName,
          )),
        );
        if (artistId != null && artistId.isNotEmpty) {
          ref.invalidate(
            moreAlbumsByArtistProvider((
              artistId: artistId,
              excludeAlbumId: album.id,
            )),
          );
        }
        final refreshedAlbum = await ref.refresh(
          albumProvider(album.id).future,
        );
        if (!mounted || refreshedAlbum.id != album.id) return;
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            stretch: true,
            backgroundColor: _backdrop,
            leading: BackButton(onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
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
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                                spreadRadius: -6,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 220,
                              height: 220,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  const _ArtFallback(size: 220),
                              errorWidget: (_, __, ___) =>
                                  const _ArtFallback(size: 220),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          album.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            InkWell(
                              onTap:
                                  album.artistId == null ||
                                      album.artistId!.isEmpty
                                  ? null
                                  : () => context.push(
                                      '/artist/${album.artistId}',
                                    ),
                              child: Text(
                                album.artistName,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color:
                                          album.artistId == null ||
                                              album.artistId!.isEmpty
                                          ? AppColors.textSecondary
                                          : AppColors.primary,
                                    ),
                              ),
                            ),
                            if (album.year != null)
                              Text(
                                '• ${album.year}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            if (album.tracks.isNotEmpty)
                              Text(
                                '• ${album.tracks.length} tracks',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
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
            delegate: _ActionBarDelegate(child: _ActionBar(album: album)),
          ),
          SliverList.builder(
            itemCount: album.tracks.length,
            itemBuilder: (_, i) {
              final track = album.tracks[i];
              return _TrackTile(
                track: track,
                index: i,
                onTap: () {
                  final current = ref.read(currentMediaItemProvider).value;
                  final isCurrentInContext =
                      current != null &&
                      current.extras?['jellyfinId'] == track.id &&
                      current.extras?['contextId'] == album.id;
                  if (isCurrentInContext) {
                    context.pushNowPlayingIfNeeded();
                    return;
                  }
                  ref
                      .read(playerControllerProvider)
                      .playTracks(
                        album.tracks,
                        startIndex: i,
                        contextId: album.id,
                        selectedTrack: true,
                      );
                },
              );
            },
          ),
          SliverToBoxAdapter(child: _AlbumRecommendations(album: album)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _AlbumRecommendations extends ConsumerWidget {
  const _AlbumRecommendations({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistId = album.artistId;
    final moreFromArtist = artistId == null || artistId.isEmpty
        ? const AsyncValue<List<BrowseItem>>.data([])
        : ref.watch(
            moreAlbumsByArtistProvider((
              artistId: artistId,
              excludeAlbumId: album.id,
            )),
          );
    final similarAlbums = ref.watch(
      similarAlbumsProvider((albumId: album.id, artistName: album.artistName)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (artistId != null && artistId.isNotEmpty)
          _RecommendationShelf(
            title: 'More from ${album.artistName}',
            items: moreFromArtist,
          ),
        _RecommendationShelf(title: 'More Like This', items: similarAlbums),
      ],
    );
  }
}

class _RecommendationShelf extends StatelessWidget {
  const _RecommendationShelf({required this.title, required this.items});

  final String title;
  final AsyncValue<List<BrowseItem>> items;

  @override
  Widget build(BuildContext context) {
    return items.when(
      loading: () => _RecommendationShelfFrame(
        title: title,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Skeleton.group(
            child: Row(
              children: const [
                _RecommendationSkeleton(),
                SizedBox(width: 6),
                _RecommendationSkeleton(),
                SizedBox(width: 6),
                _RecommendationSkeleton(),
              ],
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _RecommendationShelfFrame(
          title: title,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => MediaCard(item: items[i]),
          ),
        );
      },
    );
  }
}

class _RecommendationShelfFrame extends StatelessWidget {
  const _RecommendationShelfFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SizedBox(height: 220, child: child),
        ],
      ),
    );
  }
}

class _RecommendationSkeleton extends StatelessWidget {
  const _RecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton.box(width: 156, height: 156, radius: 10),
          const SizedBox(height: 10),
          Skeleton.line(width: 120),
          const SizedBox(height: 6),
          Skeleton.line(width: 80, height: 10),
        ],
      ),
    );
  }
}

class _ActionBarDelegate extends SliverPersistentHeaderDelegate {
  _ActionBarDelegate({required this.child});
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

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackStateProvider).value;
    final currentMediaItem = ref.watch(currentMediaItemProvider).value;
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isAlbumPlaying =
        playbackState?.playing == true &&
        (currentMediaItem?.extras?['contextId'] as String?) == album.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          const SizedBox(width: 12),
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
                : () async {
                    final action =
                        await showModalBottomSheet<_CollectionAction>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheetContext) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.playlist_add_rounded,
                                  ),
                                  title: const Text('Add album to playlist'),
                                  onTap: () => Navigator.of(
                                    sheetContext,
                                  ).pop(_CollectionAction.addToPlaylist),
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.add_to_queue_rounded,
                                  ),
                                  title: const Text('Add to queue'),
                                  onTap: () => Navigator.of(
                                    sheetContext,
                                  ).pop(_CollectionAction.addToQueue),
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
                        final added = await controller.addTracksToQueue(
                          album.tracks,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $added song${added == 1 ? '' : 's'} to queue',
                            ),
                          ),
                        );
                    }
                  },
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
}

enum _CollectionAction { addToPlaylist, addToQueue }

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.onTap,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);

    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: PlayingTrackLeading(
        jellyfinTrackId: track.id,
        indexLabel: '${track.trackNumber ?? index + 1}',
      ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? AppColors.primary : AppColors.textPrimary,
          fontSize: 14,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        track.artistName,
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
              child: Icon(
                Icons.download_for_offline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceElevated,
      child: const Icon(
        Icons.album_rounded,
        size: 64,
        color: AppColors.textTertiary,
      ),
    );
  }
}
