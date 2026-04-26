import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/musicbrainz/listenbrainz_repository.dart';
import '../../data/musicbrainz/musicbrainz_repository.dart';
import '../../data/musicbrainz/wikipedia_repository.dart';

// Search result providers — autoDispose so stale queries are released.
final _mbArtistSearchProvider =
    FutureProvider.autoDispose.family<List<MusicBrainzArtist>, String>((ref, term) {
  if (term.length < 2) return Future.value(const []);
  return ref.read(musicBrainzRepositoryProvider).searchArtists(term);
});

final _mbReleaseSearchProvider =
    FutureProvider.autoDispose.family<List<MusicBrainzReleaseGroup>, String>((ref, term) {
  if (term.length < 2) return Future.value(const []);
  return ref.read(musicBrainzRepositoryProvider).searchReleaseGroups(term);
});

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _searchActive = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _activateSearch() => setState(() => _searchActive = true);

  void _clearSearch() {
    _ctrl.clear();
    _focusNode.unfocus();
    setState(() {
      _query = '';
      _searchActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Discover'),
            floating: true,
            snap: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  onChanged: _onChanged,
                  onTap: _activateSearch,
                  decoration: InputDecoration(
                    hintText: 'Artists, albums, songs…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchActive
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _clearSearch,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          if (_searchActive && _query.isNotEmpty) ...[
            _sectionHeader(context, 'ARTISTS'),
            _ArtistResults(query: _query),
            _sectionHeader(context, 'ALBUMS'),
            _ReleaseResults(query: _query),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ] else ...[
            _sectionHeader(context, 'TRENDING ARTISTS'),
            const _TrendingArtists(),
            _sectionHeader(context, 'POPULAR ALBUMS'),
            const _TrendingReleases(),
            _sectionHeader(context, 'TRENDING SONGS'),
            const _TrendingSongs(),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}

// ── Trending artists horizontal scroll ─────────────────────────────────────

class _TrendingArtists extends ConsumerWidget {
  const _TrendingArtists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendingArtistsProvider);
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 116,
        child: async.when(
          loading: _buildSkeleton,
          error: (_, __) => const SizedBox.shrink(),
          data: (artists) {
            if (artists.isEmpty) return const SizedBox.shrink();
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _ArtistChip(artist: artists[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Skeleton.group(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => SizedBox(
          width: 76,
          child: Column(
            children: [
              Skeleton.circle(size: 68),
              const SizedBox(height: 6),
              Skeleton.line(width: 56, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistChip extends ConsumerWidget {
  const _ArtistChip({required this.artist});
  final LbArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(artistImageProvider(artist.artistName)).value;
    final hasMbid = artist.artistMbid != null;

    return GestureDetector(
      onTap: hasMbid
          ? () => context.push(
                '/discover/mb-artist',
                extra: MusicBrainzArtist(
                  id: artist.artistMbid!,
                  name: artist.artistName,
                ),
              )
          : null,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 68,
                height: 68,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.surfaceElevated),
                        errorWidget: (_, __, ___) => _ArtistInitial(artist.artistName),
                      )
                    : _ArtistInitial(artist.artistName),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              artist.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistInitial extends StatelessWidget {
  const _ArtistInitial(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

// ── Trending release groups list ────────────────────────────────────────────

class _TrendingReleases extends ConsumerStatefulWidget {
  const _TrendingReleases();

  @override
  ConsumerState<_TrendingReleases> createState() => _TrendingReleasesState();
}

class _TrendingReleasesState extends ConsumerState<_TrendingReleases> {
  bool _expanded = false;

  static const _kPreview = 5;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendingReleaseGroupsProvider);
    return async.when(
      loading: () => SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => Skeleton.group(
            child: ListTile(
              leading: Skeleton.box(width: 52, height: 52),
              title: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Skeleton.line(height: 13),
              ),
              subtitle: Skeleton.line(width: 100, height: 11),
            ),
          ),
          childCount: _kPreview,
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (groups) {
        if (groups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
        final visible = _expanded ? groups : groups.take(_kPreview).toList();
        final hasMore = groups.length > _kPreview;
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              if (hasMore && i == visible.length) {
                return _SeeMoreButton(
                  expanded: _expanded,
                  total: groups.length,
                  onTap: () => setState(() => _expanded = !_expanded),
                );
              }
              final g = visible[i];
              return _ReleaseTile(
                title: g.title,
                artist: g.artistName,
                coverArtUrl: g.coverArtUrl,
                onTap: g.artistMbid == null
                    ? null
                    : () => context.push(
                          '/discover/mb-artist',
                          extra: MusicBrainzArtist(
                            id: g.artistMbid!,
                            name: g.artistName,
                          ),
                        ),
              );
            },
            childCount: visible.length + (hasMore ? 1 : 0),
          ),
        );
      },
    );
  }
}

// ── Trending songs list ─────────────────────────────────────────────────────

class _TrendingSongs extends ConsumerStatefulWidget {
  const _TrendingSongs();

  @override
  ConsumerState<_TrendingSongs> createState() => _TrendingSongsState();
}

class _TrendingSongsState extends ConsumerState<_TrendingSongs> {
  bool _expanded = false;

  static const _kPreview = 5;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendingRecordingsProvider);
    return async.when(
      loading: () => SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => Skeleton.group(
            child: ListTile(
              leading: Skeleton.box(width: 40, height: 40),
              title: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Skeleton.line(height: 13),
              ),
              subtitle: Skeleton.line(width: 100, height: 11),
            ),
          ),
          childCount: _kPreview,
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (recordings) {
        if (recordings.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
        final visible = _expanded ? recordings : recordings.take(_kPreview).toList();
        final hasMore = recordings.length > _kPreview;
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              if (hasMore && i == visible.length) {
                return _SeeMoreButton(
                  expanded: _expanded,
                  total: recordings.length,
                  onTap: () => setState(() => _expanded = !_expanded),
                );
              }
              final rec = visible[i];
              return _SongTile(
                trackName: rec.trackName,
                artistName: rec.artistName,
                artistMbid: rec.artistMbid,
              );
            },
            childCount: visible.length + (hasMore ? 1 : 0),
          ),
        );
      },
    );
  }
}

// ── Search results ──────────────────────────────────────────────────────────

class _ArtistResults extends ConsumerWidget {
  const _ArtistResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_mbArtistSearchProvider(query));
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      data: (artists) {
        if (artists.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('No artists found',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _MbArtistTile(artist: artists[i]),
            childCount: artists.length,
          ),
        );
      },
    );
  }
}

class _ReleaseResults extends ConsumerWidget {
  const _ReleaseResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_mbReleaseSearchProvider(query));
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      data: (releases) {
        if (releases.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('No albums found',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final r = releases[i];
              return _ReleaseTile(
                title: r.title,
                artist: r.artistName ?? '',
                coverArtUrl: r.coverArtUrl,
                onTap: r.artistId == null
                    ? null
                    : () => context.push(
                          '/discover/mb-artist',
                          extra: MusicBrainzArtist(
                            id: r.artistId!,
                            name: r.artistName ?? '',
                          ),
                        ),
              );
            },
            childCount: releases.length,
          ),
        );
      },
    );
  }
}

// ── Shared tile widgets ─────────────────────────────────────────────────────

class _MbArtistTile extends ConsumerWidget {
  const _MbArtistTile({required this.artist});
  final MusicBrainzArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitoredIds = ref.watch(lidarrMonitoredArtistIdsProvider).when(
          data: (ids) => ids,
          error: (_, __) => const <String>{},
          loading: () => const <String>{},
        );
    final isMonitored = monitoredIds.contains(artist.id);

    final subtitle = [
      if (artist.type != null) artist.type!,
      if (artist.country != null) artist.country!,
      if (artist.disambiguation != null) artist.disambiguation!,
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => context.push('/discover/mb-artist', extra: artist),
      leading: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceElevated,
        ),
        child: Center(
          child: Text(
            artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: isMonitored
          ? _InLidarrBadge()
          : const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.title,
    required this.artist,
    required this.coverArtUrl,
    this.onTap,
  });

  final String title;
  final String artist;
  final String? coverArtUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 52,
          height: 52,
          child: coverArtUrl == null
              ? Container(
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.album, color: AppColors.textTertiary),
                )
              : CachedNetworkImage(
                  imageUrl: coverArtUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child:
                        const Icon(Icons.album, color: AppColors.textTertiary, size: 20),
                  ),
                ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
          : null,
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.trackName,
    required this.artistName,
    this.artistMbid,
  });

  final String trackName;
  final String artistName;
  final String? artistMbid;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: artistMbid == null
          ? null
          : () => context.push(
                '/discover/mb-artist',
                extra: MusicBrainzArtist(id: artistMbid!, name: artistName),
              ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.music_note, color: AppColors.textTertiary, size: 18),
      ),
      title: Text(trackName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: artistMbid != null
          ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
          : null,
    );
  }
}

class _SeeMoreButton extends StatelessWidget {
  const _SeeMoreButton({
    required this.expanded,
    required this.total,
    required this.onTap,
  });

  final bool expanded;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          expanded ? 'SHOW LESS' : 'SEE ALL $total',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        ),
      ),
    );
  }
}

class _InLidarrBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'IN LIDARR',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
