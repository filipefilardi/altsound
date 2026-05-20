import 'dart:async';

import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/core/widgets/header_action_buttons.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/features/search/widgets/grouped_search_results.dart';
import 'package:altsound/features/search/widgets/search_results_skeleton.dart';

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
    if (ref.read(isOfflineProvider)) {
      final indexedResults = await ref
          .read(jellyfinRepositoryProvider)
          .searchCached(term);
      return _mergeResults(indexedResults, localResults);
    }

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Search',
                    style: Theme.of(context).textTheme.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isDesktopLayout(context)) const HeaderActionButtons(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search songs, albums, artists, playlists',
                prefixIcon: const Icon(PiconsRegular.magnifyingGlass),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(PiconsRegular.x),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: AppSpacing.lg,
              ),
              child: _term.isEmpty
                  ? const _IdleHint()
                  : FutureBuilder<List<BrowseItem>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const SearchResultsSkeleton();
                        }
                        if (snap.hasError) {
                          return EmptyState(
                            icon: PiconsRegular.warningCircle,
                            title: 'Search failed',
                            message: '${snap.error}',
                          );
                        }
                        final results = snap.data ?? const [];
                        if (results.isEmpty) {
                          return _NoResults(term: _term);
                        }
                        return GroupedSearchResults(results: results);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: PiconsRegular.magnifyingGlass,
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
      icon: PiconsRegular.magnifyingGlassMinus,
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
  // Downloaded results come from the app's local manifest, so keep those
  // first when a persisted index and downloaded catalog both have the item.
  for (final item in [...localResults, ...remoteResults]) {
    if (seenIds.add(item.id)) {
      merged.add(item);
    }
  }
  return merged;
}
