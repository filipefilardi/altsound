import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../../data/jellyfin/playback_reporting_api.dart';
import '../../data/local/connectivity_provider.dart';
import 'recommendations_cache.dart';

/// Snapshot of "For you" picks rendered on Home.
///
/// [topSong] is the user's #1 played track over the last 7 days. [topArtists]
/// are 4 artists drawn daily from the top 8 of the same window — stable for
/// the day, fresh tomorrow. [forgottenFavorites] are high-played tracks the
/// user hasn't returned to recently.
class HomeRecommendations {
  const HomeRecommendations({
    required this.topSong,
    required this.topArtists,
    required this.forgottenFavorites,
  });

  final Track? topSong;
  final List<BrowseItem> topArtists;
  final List<Track> forgottenFavorites;

  bool get isEmpty =>
      topSong == null && topArtists.isEmpty && forgottenFavorites.isEmpty;
}

const _windowDays = 7;
const _historyDays = 365;
const _recentExclusionDays = 60;
const _artistPoolSize = 8;
const _artistsToShow = 4;
const _forgottenLimit = 30;

typedef _RankedTrack = ({Track track, int rank});

/// "For you" recommendations.
///
/// - Prefers the Playback Reporting plugin when it's installed and answering;
///   falls back to Jellyfin's built-in stats (`MinDateLastPlayed` +
///   `SortBy=PlayCount`) when the plugin endpoint is missing or erroring.
///   Both produce sensible "Because you played" picks.
/// - Returns `null` only when nothing usable is available.
/// - Serves the cached picks when today's cache exists or the device is
///   offline; refreshes once per day when online.
final homeRecommendationsProvider =
    FutureProvider.autoDispose<HomeRecommendations?>((ref) async {
  final cache = ref.watch(recommendationsCacheProvider);
  final isOffline = ref.watch(isOfflineProvider);
  final session = ref.watch(jellyfinApiProvider).session;
  if (session == null) return null;

  final cached = await cache.load(session.serverId, session.userId);
  final today = todayDateKey();

  if (cached != null && cached.dateKey == today) return cached.recs;
  if (isOffline) return cached?.recs;

  final fresh = await _fetchFromApi(ref);
  if (fresh != null && !fresh.isEmpty) {
    await cache.save(session.serverId, session.userId, today, fresh);
    return fresh;
  }
  return cached?.recs ?? fresh;
});

Future<HomeRecommendations?> _fetchFromApi(Ref ref) async {
  final repo = ref.read(jellyfinRepositoryProvider);
  final reporting = ref.read(playbackReportingApiProvider);

  final ranked = await _rankedRecent(repo, reporting);
  if (ranked.isEmpty) {
    if (kDebugMode) {
      debugPrint(
          '[ForYou] no recent ranked tracks from plugin or Jellyfin — hiding');
    }
    return null;
  }

  final topSong = ranked.first.track;

  // Sum per-track ranks into per-artist ranks.
  final rankByArtist = <String, int>{};
  final orderByArtist = <String, int>{};
  var artistSeen = 0;
  for (final r in ranked) {
    final aid = r.track.artistId;
    if (aid == null || aid.isEmpty) continue;
    rankByArtist.update(aid, (v) => v + r.rank, ifAbsent: () => r.rank);
    orderByArtist.putIfAbsent(aid, () => artistSeen++);
  }

  // Drop the anchor song's artist so we don't seed two cards from one artist.
  final anchorAid = topSong.artistId;
  if (anchorAid != null && anchorAid.isNotEmpty) {
    rankByArtist.remove(anchorAid);
  }

  final rankedArtists = rankByArtist.entries.toList()
    ..sort((a, b) {
      final byRank = b.value.compareTo(a.value);
      return byRank != 0
          ? byRank
          : orderByArtist[a.key]!.compareTo(orderByArtist[b.key]!);
    });
  final pool = rankedArtists.take(_artistPoolSize).map((e) => e.key).toList();

  // Day-seeded pick from the pool.
  final today = DateTime.now();
  final daySeed =
      DateTime(today.year, today.month, today.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
  final picked = List<String>.from(pool)..shuffle(Random(daySeed));
  final pickedArtistIds = picked.take(_artistsToShow).toList();

  // Run remaining queries independently so a failure in one doesn't collapse
  // the whole shelf.
  final artistsFuture = _safeItemsByIds(repo, pickedArtistIds);
  final forgottenFuture =
      _fetchForgottenFavorites(repo, reporting).catchError((Object e, _) {
    if (kDebugMode) debugPrint('[ForYou] forgottenFavorites failed: $e');
    return const <Track>[];
  });
  final results = await Future.wait([artistsFuture, forgottenFuture]);

  final recs = HomeRecommendations(
    topSong: topSong,
    topArtists: results[0] as List<BrowseItem>,
    forgottenFavorites: results[1] as List<Track>,
  );
  if (kDebugMode) {
    debugPrint(
        '[ForYou] built: topSong=${recs.topSong?.name}, artists=${recs.topArtists.length}, forgotten=${recs.forgottenFavorites.length}');
  }
  return recs;
}

/// Tracks ranked by recency-weighted plays, from whichever source is healthy.
Future<List<_RankedTrack>> _rankedRecent(
  JellyfinRepository repo,
  PlaybackReportingApi reporting,
) async {
  final pluginPlays = await reporting.recentAudioPlays(days: _windowDays);
  if (pluginPlays != null && pluginPlays.isNotEmpty) {
    final ids = pluginPlays.take(50).map((p) => p.itemId).toList();
    final tracks = await _safeTracksByIds(repo, ids);
    final byId = {for (final t in tracks) t.id: t};
    final ranked = <_RankedTrack>[];
    for (final p in pluginPlays) {
      final t = byId[p.itemId];
      if (t != null) ranked.add((track: t, rank: p.rank));
    }
    if (ranked.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('[ForYou] plugin → ${ranked.length} ranked tracks');
      }
      return ranked;
    }
  }

  // Fallback: Jellyfin built-in. Order from the API is descending PlayCount,
  // so use position as the rank (higher index = higher rank).
  if (kDebugMode) {
    debugPrint(
        '[ForYou] plugin yielded nothing usable, falling back to Jellyfin');
  }
  final since = DateTime.now().toUtc().subtract(const Duration(days: _windowDays));
  final tracks = await _safeTopPlayedSince(repo, since);
  return [
    for (var i = 0; i < tracks.length; i++)
      (track: tracks[i], rank: tracks.length - i),
  ];
}

Future<List<Track>> _safeTracksByIds(
    JellyfinRepository repo, List<String> ids) async {
  if (ids.isEmpty) return const [];
  try {
    return await repo.tracksByIds(ids);
  } catch (e) {
    if (kDebugMode) debugPrint('[ForYou] tracksByIds failed: $e');
    return const [];
  }
}

Future<List<BrowseItem>> _safeItemsByIds(
    JellyfinRepository repo, List<String> ids) async {
  if (ids.isEmpty) return const [];
  try {
    return await repo.itemsByIds(ids);
  } catch (e) {
    if (kDebugMode) debugPrint('[ForYou] itemsByIds failed: $e');
    return const [];
  }
}

Future<List<Track>> _safeTopPlayedSince(
    JellyfinRepository repo, DateTime since) async {
  try {
    return await repo.topPlayedSince(since: since);
  } catch (e) {
    if (kDebugMode) debugPrint('[ForYou] topPlayedSince failed: $e');
    return const [];
  }
}

/// Tracks the user used to listen to a lot but hasn't touched recently.
/// Prefers the plugin's 365/60-day diff; falls back to the Jellyfin
/// `forgottenFavorites` query (PlayCount + LastPlayedDate cutoff).
Future<List<Track>> _fetchForgottenFavorites(
  JellyfinRepository repo,
  PlaybackReportingApi reporting,
) async {
  final history = await reporting.recentAudioPlays(days: _historyDays);
  if (history != null && history.isNotEmpty) {
    final recent = await reporting.recentAudioPlays(days: _recentExclusionDays);
    final recentIds = (recent ?? const <PlaybackReportingPlay>[])
        .map((p) => p.itemId)
        .toSet();
    final coldIds = <String>[];
    for (final play in history) {
      if (recentIds.contains(play.itemId)) continue;
      coldIds.add(play.itemId);
      if (coldIds.length >= _forgottenLimit) break;
    }
    if (coldIds.isNotEmpty) {
      final tracks = await _safeTracksByIds(repo, coldIds);
      if (tracks.isNotEmpty) return tracks;
    }
  }

  // Plugin missing/broken/empty → use Jellyfin's PlayCount + cold-period
  // filter. Tighter window (60 days) than the original 180 so more candidates
  // qualify on smaller libraries.
  try {
    return await repo.forgottenFavorites(
      limit: _forgottenLimit,
      coldFor: const Duration(days: _recentExclusionDays),
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[ForYou] forgottenFavorites jellyfin fallback failed: $e');
    }
    return const [];
  }
}
