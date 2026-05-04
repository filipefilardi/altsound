import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

/// Snapshot of "For you" picks rendered on Home. Each `because*` field is the
/// daily-rotated seed for a one-tap Instant Mix; [forgottenFavorites] is a
/// flat list of high-played-but-cold tracks meant to be played directly.
class HomeRecommendations {
  const HomeRecommendations({
    required this.becauseAlbum,
    required this.becauseTrack,
    required this.becauseArtist,
    required this.forgottenFavorites,
  });

  final BrowseItem? becauseAlbum;
  final Track? becauseTrack;
  final BrowseItem? becauseArtist;
  final List<Track> forgottenFavorites;

  bool get isEmpty =>
      becauseAlbum == null &&
      becauseTrack == null &&
      becauseArtist == null &&
      forgottenFavorites.isEmpty;
}

/// Daily-rotated For You recommendations. Refetches when the day changes
/// (the cache key embeds today's date). Within a day, the same picks come
/// back deterministically even after pull-to-refresh — the underlying
/// Instant Mix stays session-cached as before.
final homeRecommendationsProvider =
    FutureProvider.autoDispose<HomeRecommendations>((ref) async {
  final repo = ref.watch(jellyfinRepositoryProvider);

  final results = await Future.wait([
    repo.recentlyPlayedAlbums(limit: 20),
    repo.recentlyPlayedTracks(limit: 20),
    repo.recentlyPlayedArtists(limit: 20),
    repo.forgottenFavorites(limit: 30),
  ]);
  final albums = results[0] as List<BrowseItem>;
  final tracks = results[1] as List<Track>;
  final artists = results[2] as List<BrowseItem>;
  final forgotten = results[3] as List<Track>;

  // Deterministic seed = days since epoch, so picks rotate once per local day.
  final today = DateTime.now();
  final daySeed =
      DateTime(today.year, today.month, today.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;

  T? pick<T>(List<T> list, int salt) =>
      list.isEmpty ? null : list[Random(daySeed + salt).nextInt(list.length)];

  return HomeRecommendations(
    becauseAlbum: pick(albums, 1),
    becauseTrack: pick(tracks, 2),
    becauseArtist: pick(artists, 3),
    forgottenFavorites: forgotten,
  );
});
