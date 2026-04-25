import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../player/player_providers.dart';
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
      final repo = ref.read(jellyfinRepositoryProvider);
      setState(() {
        _term = v.trim();
        _future =
            _term.isEmpty ? Future.value(const []) : repo.search(_term);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            tooltip: 'Discover via Lidarr',
            icon: const Icon(Icons.travel_explore),
            onPressed: () => context.push('/discover'),
          ),
        ],
      ),
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
                ? _IdleHint(onDiscover: () => context.push('/discover'))
                : FutureBuilder<List<BrowseItem>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return _MessageState(
                            message: 'Search failed: ${snap.error}');
                      }
                      final results = snap.data ?? const [];
                      if (results.isEmpty) {
                        return _NoResults(
                          term: _term,
                          onDiscover: () => context.push('/discover'),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 80),
                        itemBuilder: (_, i) =>
                            _ResultTile(item: results[i]),
                      );
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
    final imageUrl = repo.imageUrl(item.id, imageTag: item.imageTag, size: 200);
    final isArtist = item.kind == MediaKind.artist;
    final isTrack = item.kind == MediaKind.track;
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack = isTrack &&
        current != null &&
        current.extras?['jellyfinId'] == item.id;

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
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: AppColors.surfaceElevated),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceElevated,
                  child: Icon(_iconFor(item.kind), color: AppColors.textTertiary),
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
      trailing: isTrack && item.runTime != null
          ? PlayingTrackDuration(
              jellyfinTrackId: item.id,
              trackDuration: item.runTime!,
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
        final track = await ref.read(jellyfinRepositoryProvider).track(item.id);
        await ref.read(playerControllerProvider).playTracks([track]);
      case MediaKind.artist:
      case MediaKind.playlist:
        // Future: artist + playlist detail screens
        break;
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

class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.onDiscover});
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search,
      title: 'Search your Jellyfin library',
      message: 'Find songs, albums, and artists you already have.',
      action: TextButton.icon(
        onPressed: onDiscover,
        icon: const Icon(Icons.travel_explore),
        label: const Text('Discover via Lidarr'),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.term, required this.onDiscover});
  final String term;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off,
      title: 'No matches in your library',
      message: 'Nothing matched "$term". Try a different spelling, or request '
          'it through Lidarr.',
      action: ElevatedButton.icon(
        onPressed: onDiscover,
        icon: const Icon(Icons.travel_explore, color: Color(0xFF1A0F05)),
        label: Text('REQUEST "$term" VIA LIDARR'),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
