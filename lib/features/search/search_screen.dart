import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/search_normalization.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/downloaded_track.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../../data/local/connectivity_provider.dart';
import '../player/player_providers.dart';
import '../player/widgets/add_track_to_playlist_sheet.dart';
import '../player/widgets/playing_track_leading.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _term = '';
  Future<List<BrowseItem>> _future = Future.value(const []);

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _term = v.trim();
        _future = _term.isEmpty ? Future.value(const []) : _search(_term);
      });
    });
  }

  Future<List<BrowseItem>> _search(String term) async {
    final downloads = ref.read(downloadManagerProvider);
    final localResults = _searchDownloads(downloads, term);
    if (ref.read(isOfflineProvider)) return localResults;

    try {
      final remoteResults = await ref
          .read(jellyfinRepositoryProvider)
          .search(term);
      return _mergeResults(remoteResults, localResults);
    } catch (_) {
      if (localResults.isNotEmpty) return localResults;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Songs, albums, artists',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _term.isEmpty
                ? const _IdleHint()
                : FutureBuilder<List<BrowseItem>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const _SearchResultsSkeleton();
                      }
                      if (snap.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          title: 'Search failed',
                          message: '${snap.error}',
                        );
                      }
                      final results = snap.data ?? const [];
                      if (results.isEmpty) {
                        return _NoResults(term: _term);
                      }
                      return _GroupedResults(results: results);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.item});
  final BrowseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final localArtwork = _localArtworkFor(item, downloads);
    final imageUrl =
        localArtwork ??
        (item.imageTag == null || item.imageTag!.isEmpty
            ? null
            : repo.imageUrl(item.id, imageTag: item.imageTag, size: 200));
    final isArtist = item.kind == MediaKind.artist;
    final isTrack = item.kind == MediaKind.track;
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack =
        isTrack && current != null && current.extras?['jellyfinId'] == item.id;

    final isDownloaded =
        isTrack && ref.watch(downloadManagerProvider).isDownloaded(item.id);

    final leading = isTrack
        ? SearchTrackArtwork(
            imageUrl: imageUrl,
            jellyfinTrackId: item.id,
            isArtistShape: false,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(isArtist ? 28 : 4),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imageUrl == null
                  ? Container(
                      color: AppColors.surfaceElevated,
                      child: Icon(
                        _iconFor(item.kind),
                        color: AppColors.textTertiary,
                      ),
                    )
                  : LocalOrNetworkImage(
                      source: imageUrl,
                      fit: BoxFit.cover,
                      placeholderBuilder: (_) =>
                          Container(color: AppColors.surfaceElevated),
                      errorBuilder: (_) => Container(
                        color: AppColors.surfaceElevated,
                        child: Icon(
                          _iconFor(item.kind),
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
            ),
          );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading,
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrentTrack ? AppColors.primary : null,
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        item.subtitle ?? _labelFor(item.kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: isTrack
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloaded)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.download_for_offline,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                if (item.runTime != null)
                  PlayingTrackDuration(
                    jellyfinTrackId: item.id,
                    trackDuration: item.runTime!,
                  ),
                _SearchTrackMenuButton(trackId: item.id),
              ],
            )
          : null,
      onTap: () => _onTap(context, ref),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    switch (item.kind) {
      case MediaKind.album:
        context.push('/album/${item.id}');
      case MediaKind.track:
        final downloaded = ref.read(downloadManagerProvider).tracks[item.id];
        final track =
            downloaded?.toTrack() ??
            await ref.read(jellyfinRepositoryProvider).track(item.id);
        await ref.read(playerControllerProvider).playTracks([
          track,
        ], selectedTrack: true);
      case MediaKind.artist:
        context.push('/artist/${item.id}');
      case MediaKind.playlist:
        context.push('/playlist/${item.id}');
    }
  }

  IconData _iconFor(MediaKind k) => switch (k) {
    MediaKind.album => Icons.album,
    MediaKind.artist => Icons.person,
    MediaKind.track => Icons.music_note,
    MediaKind.playlist => Icons.queue_music,
  };

  String _labelFor(MediaKind k) => switch (k) {
    MediaKind.album => 'Album',
    MediaKind.artist => 'Artist',
    MediaKind.track => 'Song',
    MediaKind.playlist => 'Playlist',
  };
}

class _SearchTrackMenuButton extends ConsumerWidget {
  const _SearchTrackMenuButton({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onPressed: () async {
        final repo = ref.read(jellyfinRepositoryProvider);
        final downloaded = ref.read(downloadManagerProvider).tracks[trackId];
        final track = downloaded?.toTrack() ?? await repo.track(trackId);
        if (!context.mounted) return;
        final localArtwork = downloaded?.artworkPath;
        final imageUrl =
            localArtwork ??
            (track.imageTag == null || track.imageTag!.isEmpty
                ? null
                : repo.imageUrl(
                    track.imageItemId,
                    imageTag: track.imageTag,
                    size: 200,
                  ));
        final action = await showModalBottomSheet<_TrackMenuAction>(
          context: context,
          showDragHandle: true,
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Track header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: imageUrl == null
                              ? Container(
                                  color: AppColors.surfaceHighlight,
                                  child: const Icon(
                                    Icons.music_note,
                                    color: AppColors.textTertiary,
                                    size: 20,
                                  ),
                                )
                              : LocalOrNetworkImage(
                                  source: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholderBuilder: (_) => Container(
                                    color: AppColors.surfaceHighlight,
                                  ),
                                  errorBuilder: (_) => Container(
                                    color: AppColors.surfaceHighlight,
                                    child: const Icon(
                                      Icons.music_note,
                                      color: AppColors.textTertiary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            if (track.albumName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${track.artistName} · ${track.albumName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 2),
                              Text(
                                track.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── Actions ──
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text('Add to playlist'),
                  onTap: () => Navigator.of(
                    sheetCtx,
                  ).pop(_TrackMenuAction.addToPlaylist),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: const Text('Add to queue'),
                  onTap: () =>
                      Navigator.of(sheetCtx).pop(_TrackMenuAction.addToQueue),
                ),
                if (track.albumId != null && track.albumId!.isNotEmpty) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: const Text('Go to album'),
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(_TrackMenuAction.goToAlbum),
                  ),
                ],
                if (track.artistId != null && track.artistId!.isNotEmpty) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Go to artist'),
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(_TrackMenuAction.goToArtist),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (action == null || !context.mounted) return;
        switch (action) {
          case _TrackMenuAction.addToPlaylist:
            await openAddTrackToPlaylistFlow(
              context,
              ref,
              trackId: track.id,
              includeLikedSongsShortcut: true,
            );
          case _TrackMenuAction.addToQueue:
            await ref.read(playerControllerProvider).addToQueue(track);
          case _TrackMenuAction.goToAlbum:
            context.push('/album/${track.albumId}');
          case _TrackMenuAction.goToArtist:
            context.push('/artist/${track.artistId}');
        }
      },
    );
  }
}

enum _TrackMenuAction { addToPlaylist, addToQueue, goToAlbum, goToArtist }

class _GroupedResults extends StatelessWidget {
  const _GroupedResults({required this.results});
  final List<BrowseItem> results;

  @override
  Widget build(BuildContext context) {
    final tracks = results.where((r) => r.kind == MediaKind.track).toList();
    final albums = results.where((r) => r.kind == MediaKind.album).toList();
    final artists = results.where((r) => r.kind == MediaKind.artist).toList();
    final playlists = results
        .where((r) => r.kind == MediaKind.playlist)
        .toList();

    final sections = <(String, List<BrowseItem>)>[
      if (artists.isNotEmpty) ('Artists', artists),
      if (tracks.isNotEmpty) ('Songs', tracks),
      if (albums.isNotEmpty) ('Albums', albums),
      if (playlists.isNotEmpty) ('Playlists', playlists),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: sections.fold<int>(
        0,
        (count, section) => count + 1 + section.$2.length,
      ),
      itemBuilder: (context, index) {
        int cursor = 0;
        for (final (label, items) in sections) {
          if (index == cursor) {
            return _SectionHeader(label: label);
          }
          cursor++;
          final itemIndex = index - cursor;
          if (itemIndex < items.length) {
            final item = items[itemIndex];
            final isLast = itemIndex == items.length - 1;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResultTile(item: item),
                if (!isLast) const Divider(height: 1, indent: 80),
              ],
            );
          }
          cursor += items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _SearchResultsSkeleton extends StatelessWidget {
  const _SearchResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: 8,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Skeleton.box(width: 52, height: 52, radius: 6),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180, height: 14),
                    const SizedBox(height: 8),
                    Skeleton.line(width: 100, height: 10),
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

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search,
      title: 'Search your Jellyfin library',
      message: 'Find songs, albums, and artists you already have.',
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.term});
  final String term;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off,
      title: 'No matches in your library',
      message: 'Nothing matched "$term". Try a different spelling.',
    );
  }
}

List<BrowseItem> _searchDownloads(DownloadsState downloads, String term) {
  final candidates = <({BrowseItem item, List<String?> fields})>[];

  for (final track in downloads.tracks.values) {
    candidates.add((
      item: BrowseItem(
        id: track.id,
        name: track.name,
        subtitle: track.artistName,
        imageTag: track.imageTag,
        kind: MediaKind.track,
        runTime: track.duration,
      ),
      fields: [track.name, track.artistName, track.albumName],
    ));
  }

  final albumsById = <String, List<DownloadedTrack>>{};
  for (final track in downloads.tracks.values) {
    final albumId = track.albumId;
    if (albumId == null || albumId.isEmpty) continue;
    (albumsById[albumId] ??= []).add(track);
  }
  for (final entry in albumsById.entries) {
    final first = entry.value.first;
    candidates.add((
      item: BrowseItem(
        id: entry.key,
        name: first.albumName ?? 'Unknown Album',
        subtitle: first.artistName,
        imageTag: first.imageTag,
        kind: MediaKind.album,
        childCount: entry.value.length,
      ),
      fields: [first.albumName, first.artistName],
    ));
  }

  for (final playlist in downloads.playlists.values) {
    final playlistTracks = playlist.trackIds
        .map((id) => downloads.tracks[id])
        .whereType<DownloadedTrack>()
        .toList();
    candidates.add((
      item: BrowseItem(
        id: playlist.id,
        name: playlist.name,
        subtitle: 'Playlist',
        imageTag: playlist.imageTag,
        kind: MediaKind.playlist,
        childCount: playlistTracks.length,
      ),
      fields: [
        playlist.name,
        ...playlistTracks.expand(
          (track) => [track.name, track.artistName, track.albumName],
        ),
      ],
    ));
  }

  final matches = candidates
      .where((candidate) => searchMatches(term, candidate.fields))
      .toList();
  matches.sort((a, b) {
    final relevance = searchRelevance(
      term,
      b.fields,
    ).compareTo(searchRelevance(term, a.fields));
    if (relevance != 0) return relevance;
    return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
  });
  return matches.map((match) => match.item).take(50).toList();
}

List<BrowseItem> _mergeResults(
  List<BrowseItem> remoteResults,
  List<BrowseItem> localResults,
) {
  final merged = <BrowseItem>[];
  final seenIds = <String>{};
  for (final item in [...remoteResults, ...localResults]) {
    if (seenIds.add(item.id)) {
      merged.add(item);
    }
  }
  return merged;
}

String? _localArtworkFor(BrowseItem item, DownloadsState downloads) {
  switch (item.kind) {
    case MediaKind.track:
      return downloads.tracks[item.id]?.artworkPath;
    case MediaKind.album:
      for (final track in downloads.tracks.values) {
        if (track.albumId == item.id && track.artworkPath != null) {
          return track.artworkPath;
        }
      }
      return null;
    case MediaKind.playlist:
      final playlist = downloads.playlists[item.id];
      if (playlist == null) return null;
      for (final trackId in playlist.trackIds) {
        final artworkPath = downloads.tracks[trackId]?.artworkPath;
        if (artworkPath != null) return artworkPath;
      }
      return null;
    case MediaKind.artist:
      return null;
  }
}
