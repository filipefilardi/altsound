import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../downloads/widgets/album_download_button.dart';
import '../player/player_providers.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/widgets/playing_track_leading.dart';
import '../player/widgets/track_more_menu_button.dart';
import 'album_controller.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumProvider(albumId));

    return Scaffold(
      bottomNavigationBar: const MiniPlayerSlot(withTopDivider: true),
      body: async.when(
        loading: () => const _AlbumLoading(),
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
                title: "Couldn't load this album",
                message: e.toString(),
                onRetry: () => ref.invalidate(albumProvider(albumId)),
              ),
            ],
          ),
        ),
        data: (album) => _AlbumView(album: album),
      ),
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
    final url = repo.imageUrl(widget.album.id,
        imageTag: widget.album.imageTag, size: 200);
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        size: const Size(200, 200),
        maximumColorCount: 8,
      );
      final c = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.darkVibrantColor?.color;
      if (c != null && mounted) {
        setState(() => _backdrop = Color.alphaBlend(
              c.withValues(alpha: 0.55),
              AppColors.background,
            ));
      }
    } catch (_) {
      // ignore palette failures
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final repo = ref.read(jellyfinRepositoryProvider);
    final imageUrl =
        repo.imageUrl(album.id, imageTag: album.imageTag, size: 600);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 380,
          pinned: true,
          stretch: true,
          backgroundColor: _backdrop,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
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
                            onTap: album.artistId == null || album.artistId!.isEmpty
                                ? null
                                : () => context.push('/artist/${album.artistId}'),
                            child: Text(
                              album.artistName,
                              style:
                                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: album.artistId == null ||
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
          delegate: _ActionBarDelegate(
            child: _ActionBar(album: album),
          ),
        ),
        SliverList.builder(
          itemCount: album.tracks.length,
          itemBuilder: (_, i) {
            final track = album.tracks[i];
            return _TrackTile(
              track: track,
              index: i,
              onTap: () => ref
                  .read(playerControllerProvider)
                  .playTracks(album.tracks, startIndex: i),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: child,
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _PlayPill(
            onTap: album.tracks.isEmpty
                ? null
                : () => ref
                    .read(playerControllerProvider)
                    .playTracks(album.tracks),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Shuffle',
            icon: const Icon(Icons.shuffle, color: AppColors.textPrimary),
            onPressed: album.tracks.isEmpty
                ? null
                : () async {
                    await ref
                        .read(playerControllerProvider)
                        .toggleShuffle();
                    if (!context.mounted) return;
                    await ref
                        .read(playerControllerProvider)
                        .playTracks(album.tracks);
                  },
          ),
          AlbumDownloadButton(album: album),
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

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: -3,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.play_arrow,
                  color: Color(0xFF1A0F05), size: 30),
            ),
          ),
        ),
      ),
    );
  }
}

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

    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: PlayingTrackLeading(
        jellyfinTrackId: track.id,
        indexLabel: '${track.trackNumber ?? index + 1}',
        trackDuration: track.duration,
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
      child: const Icon(Icons.album, size: 64, color: AppColors.textTertiary),
    );
  }
}
