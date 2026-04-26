import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/musicbrainz/listenbrainz_repository.dart';
import '../../data/musicbrainz/musicbrainz_repository.dart';
import '../../data/musicbrainz/wikipedia_repository.dart';
import 'mb_release_sheet.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _discographyProvider =
    FutureProvider.family<List<MusicBrainzReleaseGroup>, MusicBrainzArtist>(
  (ref, artist) => ref.read(musicBrainzRepositoryProvider).artistReleaseGroups(artist.id),
);

/// Set of MusicBrainz release-group IDs already in Lidarr for this artist.
final _lidarrAlbumStatusProvider =
    FutureProvider.family<Set<String>, MusicBrainzArtist>(
  (ref, artist) async {
    final repo = ref.watch(lidarrRepositoryProvider);
    if (repo == null) return const {};

    final monitored = await repo.monitoredArtists();
    final lidarrArtist =
        monitored.where((a) => a.foreignArtistId == artist.id).firstOrNull;
    if (lidarrArtist == null) return const {};

    final albums = await repo.artistAlbums(
      artistName: artist.name,
      foreignArtistId: lidarrArtist.foreignArtistId,
    );
    return {
      for (final a in albums)
        if ((a.raw['id'] as int?) != null) a.foreignAlbumId,
    };
  },
);

const _typeOrder = ['Album', 'EP', 'Single', 'Live', 'Compilation', 'Remix', 'Other'];

int _typeIndex(String? type) {
  final i = _typeOrder.indexOf(type ?? 'Other');
  return i < 0 ? _typeOrder.length : i;
}

// ── Screen ───────────────────────────────────────────────────────────────────

class MbArtistScreen extends ConsumerStatefulWidget {
  const MbArtistScreen({required this.artist, super.key});

  final MusicBrainzArtist artist;

  @override
  ConsumerState<MbArtistScreen> createState() => _MbArtistScreenState();
}

class _MbArtistScreenState extends ConsumerState<MbArtistScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artist.name),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'OVERVIEW'), Tab(text: 'DISCOGRAPHY')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(artist: widget.artist),
          _DiscographyTab(artist: widget.artist),
        ],
      ),
    );
  }
}

// ── Overview tab ─────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab({required this.artist});
  final MusicBrainzArtist artist;

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  bool _albumsExpanded = false;
  bool _songsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final inLidarr = ref.watch(_lidarrAlbumStatusProvider(widget.artist)).when(
          data: (v) => v,
          error: (_, __) => const <String>{},
          loading: () => const <String>{},
        );

    final topAlbumsAsync = ref.watch(artistTopReleasesProvider(widget.artist.id));
    final topSongsAsync = ref.watch(artistTopRecordingsProvider(widget.artist.id));
    final discoAsync = ref.watch(_discographyProvider(widget.artist));
    final bioAsync = ref.watch(artistBioProvider(widget.artist.name));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        _ArtistHeader(artist: widget.artist),

        // ── Popular Albums ──────────────────────────────────────────────
        _GroupHeader(label: 'POPULAR ALBUMS'),
        _buildAlbumsSection(topAlbumsAsync, discoAsync, inLidarr),

        // ── Popular Songs ───────────────────────────────────────────────
        ..._buildSongsSection(topSongsAsync),

        // ── About ───────────────────────────────────────────────────────
        ..._buildAboutSection(bioAsync),
      ],
    );
  }

  Widget _buildAlbumsSection(
    AsyncValue<List<LbArtistRelease>> topAlbumsAsync,
    AsyncValue<List<MusicBrainzReleaseGroup>> discoAsync,
    Set<String> inLidarr,
  ) {
    return topAlbumsAsync.when(
      loading: () => _miniSkeleton(4),
      error: (_, __) => _discoFallback(discoAsync, inLidarr),
      data: (releases) {
        if (releases.isNotEmpty) {
          final shown = _albumsExpanded ? releases : releases.take(5).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in shown)
                _LbAlbumTile(
                  title: r.title,
                  coverArtUrl: r.coverArtUrl,
                  listenCount: r.listenCount,
                  isInLidarr: r.releaseGroupMbid != null &&
                      inLidarr.contains(r.releaseGroupMbid),
                  onTap: r.releaseGroupMbid == null
                      ? null
                      : () => _openSheet(
                            context,
                            MusicBrainzReleaseGroup(
                                id: r.releaseGroupMbid!, title: r.title),
                            inLidarr.contains(r.releaseGroupMbid),
                          ),
                ),
              if (releases.length > 5)
                _SeeMoreButton(
                  expanded: _albumsExpanded,
                  total: releases.length,
                  onTap: () => setState(() => _albumsExpanded = !_albumsExpanded),
                ),
            ],
          );
        }
        // LB has no data — fall back to MusicBrainz discography.
        return _discoFallback(discoAsync, inLidarr);
      },
    );
  }

  Widget _discoFallback(
    AsyncValue<List<MusicBrainzReleaseGroup>> discoAsync,
    Set<String> inLidarr,
  ) {
    return discoAsync.when(
      loading: () => _miniSkeleton(4),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
        final albums = groups
            .where((g) => g.primaryType == 'Album' || g.primaryType == 'EP')
            .take(5)
            .toList();
        if (albums.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in albums)
              _LbAlbumTile(
                title: r.title,
                coverArtUrl: r.coverArtUrl,
                isInLidarr: inLidarr.contains(r.id),
                onTap: () => _openSheet(context, r, inLidarr.contains(r.id)),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildAboutSection(AsyncValue<String?> bioAsync) {
    final bio = bioAsync.value;
    if (bio == null || bio.isEmpty) return const [];
    return [
      const SizedBox(height: 4),
      _GroupHeader(label: 'ABOUT'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: _BioText(bio: bio),
      ),
    ];
  }

  List<Widget> _buildSongsSection(AsyncValue<List<LbRecording>> topSongsAsync) {
    return topSongsAsync.when(
      loading: () => [
        const SizedBox(height: 4),
        _GroupHeader(label: 'POPULAR SONGS'),
        _miniSkeleton(4),
      ],
      error: (_, __) => const [],
      data: (songs) {
        if (songs.isEmpty) return const [];
        final shown = _songsExpanded ? songs : songs.take(5).toList();
        return [
          const SizedBox(height: 4),
          _GroupHeader(label: 'POPULAR SONGS'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in shown) _LbSongTile(recording: s),
              if (songs.length > 5)
                _SeeMoreButton(
                  expanded: _songsExpanded,
                  total: songs.length,
                  onTap: () => setState(() => _songsExpanded = !_songsExpanded),
                ),
            ],
          ),
        ];
      },
    );
  }

  void _openSheet(
    BuildContext context,
    MusicBrainzReleaseGroup release,
    bool isInLidarr,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MbReleaseSheet(
        release: release,
        artist: widget.artist,
        isInLidarr: isInLidarr,
      ),
    );
  }

  Widget _miniSkeleton(int count) => Skeleton.group(
        child: Column(
          children: [
            for (int i = 0; i < count; i++)
              ListTile(
                leading: Skeleton.box(width: 48, height: 48),
                title: Skeleton.line(height: 13),
                subtitle: Skeleton.line(width: 80, height: 11),
              ),
          ],
        ),
      );
}

// ── Discography tab ───────────────────────────────────────────────────────────

class _DiscographyTab extends ConsumerWidget {
  const _DiscographyTab({required this.artist});
  final MusicBrainzArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoAsync = ref.watch(_discographyProvider(artist));
    final inLidarr = ref.watch(_lidarrAlbumStatusProvider(artist)).when(
          data: (v) => v,
          error: (_, __) => const <String>{},
          loading: () => const <String>{},
        );

    return discoAsync.when(
      loading: () => const _DiscographySkeleton(),
      error: (e, _) => ErrorStateView(
        title: "Couldn't load discography",
        message: e.toString(),
        onRetry: () => ref.invalidate(_discographyProvider(artist)),
      ),
      data: (releases) {
        if (releases.isEmpty) {
          return const EmptyState(
            icon: Icons.album_outlined,
            title: 'No releases found',
            message: 'This artist has no releases in MusicBrainz.',
          );
        }
        final grouped = <String, List<MusicBrainzReleaseGroup>>{};
        for (final r in releases) {
          grouped.putIfAbsent(r.primaryType ?? 'Other', () => []).add(r);
        }
        final sortedTypes = grouped.keys.toList()
          ..sort((a, b) => _typeIndex(a).compareTo(_typeIndex(b)));

        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final type in sortedTypes) ...[
              _GroupHeader(label: type.toUpperCase()),
              for (final release in grouped[type]!)
                _ReleaseRow(
                  artist: artist,
                  release: release,
                  isInLidarr: inLidarr.contains(release.id),
                ),
            ],
          ],
        );
      },
    );
  }
}

// ── Shared header ─────────────────────────────────────────────────────────────

class _ArtistHeader extends ConsumerWidget {
  const _ArtistHeader({required this.artist});
  final MusicBrainzArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(artistImageProvider(artist.name)).value;
    final meta = [
      if (artist.type != null) artist.type!,
      if (artist.country != null) artist.country!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => _ArtistInitial(artist.name),
                    )
                  : _ArtistInitial(artist.name),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
                if (artist.disambiguation != null) ...[
                  const SizedBox(height: 2),
                  Text(artist.disambiguation!,
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BioText extends StatefulWidget {
  const _BioText({required this.bio});
  final String bio;

  @override
  State<_BioText> createState() => _BioTextState();
}

class _BioTextState extends State<_BioText> {
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

class _ArtistInitial extends StatelessWidget {
  const _ArtistInitial(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceElevated,
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
      );
}

// ── Shared section header ─────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      );
}

// ── See more button ───────────────────────────────────────────────────────────

class _SeeMoreButton extends StatelessWidget {
  const _SeeMoreButton(
      {required this.expanded, required this.total, required this.onTap});
  final bool expanded;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          expanded ? 'SHOW LESS' : 'SEE ALL $total',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ── ListenBrainz album tile (overview) ───────────────────────────────────────

class _LbAlbumTile extends StatelessWidget {
  const _LbAlbumTile({
    required this.title,
    required this.coverArtUrl,
    this.listenCount,
    required this.isInLidarr,
    this.onTap,
  });

  final String title;
  final String? coverArtUrl;
  final int? listenCount;
  final bool isInLidarr;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: coverArtUrl == null
              ? Container(
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.album,
                      color: AppColors.textTertiary, size: 20),
                )
              : CachedNetworkImage(
                  imageUrl: coverArtUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.album,
                        color: AppColors.textTertiary, size: 20),
                  ),
                ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: listenCount != null
          ? Text(
              _formatListens(listenCount!),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: isInLidarr ? _InLidarrBadge() : const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}

// ── ListenBrainz song tile (overview) ────────────────────────────────────────

class _LbSongTile extends StatelessWidget {
  const _LbSongTile({required this.recording});
  final LbRecording recording;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (recording.releaseName != null) recording.releaseName!,
      _formatListens(recording.listenCount),
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.music_note, color: AppColors.textTertiary),
      ),
      title: Text(recording.trackName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}

// ── Discography release row (tap to open track sheet) ────────────────────────

class _ReleaseRow extends ConsumerStatefulWidget {
  const _ReleaseRow({
    required this.artist,
    required this.release,
    required this.isInLidarr,
  });

  final MusicBrainzArtist artist;
  final MusicBrainzReleaseGroup release;
  final bool isInLidarr;

  @override
  ConsumerState<_ReleaseRow> createState() => _ReleaseRowState();
}

class _ReleaseRowState extends ConsumerState<_ReleaseRow> {
  bool _busy = false;
  bool _requested = false;

  Future<void> _request() async {
    final repo = ref.read(lidarrRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Configure Lidarr in Settings to request albums.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final lidarrArtists = await repo.searchArtists(widget.artist.name);
      final lidarrArtist =
          lidarrArtists.where((a) => a.foreignArtistId == widget.artist.id).firstOrNull ??
              lidarrArtists.firstOrNull;
      if (lidarrArtist == null) throw Exception('Artist not found in Lidarr catalog');

      final lidarrAlbums = await repo.artistAlbums(
        artistName: widget.artist.name,
        foreignArtistId: lidarrArtist.foreignArtistId,
      );
      final lidarrAlbum =
          lidarrAlbums.where((a) => a.foreignAlbumId == widget.release.id).firstOrNull;
      if (lidarrAlbum == null) throw Exception('Album not found in Lidarr catalog');

      final defaults = await repo.defaults();
      await repo.addAlbum(lidarrArtist, lidarrAlbum, defaults: defaults);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _requested = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Requested "${widget.release.title}" via Lidarr')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MbReleaseSheet(
        release: widget.release,
        artist: widget.artist,
        isInLidarr: widget.isInLidarr || _requested,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;

    Widget trailing;
    if (widget.isInLidarr) {
      trailing = _InLidarrBadge();
    } else if (_requested) {
      trailing = const Icon(Icons.check_circle_outline, color: AppColors.primary);
    } else if (_busy) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else {
      trailing = TextButton(
        onPressed: _request,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('REQUEST'),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: _openSheet,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedNetworkImage(
            imageUrl: r.coverArtUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.surfaceElevated,
              child: const Icon(Icons.album,
                  color: AppColors.textTertiary, size: 20),
            ),
          ),
        ),
      ),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: r.year.isNotEmpty
          ? Text(r.year,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12))
          : null,
      trailing: trailing,
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _InLidarrBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
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

String _formatListens(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M plays';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(0)}K plays';
  return '$count plays';
}

class _DiscographySkeleton extends StatelessWidget {
  const _DiscographySkeleton();

  @override
  Widget build(BuildContext context) => Skeleton.group(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Skeleton.line(width: 60, height: 11),
            const SizedBox(height: 12),
            for (int i = 0; i < 8; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Skeleton.box(width: 48, height: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton.line(height: 13),
                          const SizedBox(height: 6),
                          Skeleton.line(width: 50, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}
