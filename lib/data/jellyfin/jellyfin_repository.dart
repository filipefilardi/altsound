import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/data/jellyfin/jellyfin_api.dart';
import 'package:altsound/data/jellyfin/models/jellyfin_session.dart';
import 'package:altsound/data/jellyfin/models/lyrics.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/jellyfin/playback_reporting_api.dart';

class _NoSession implements Exception {
  @override
  String toString() => 'No active Jellyfin session';
}

class JellyfinServerInfo {
  const JellyfinServerInfo({required this.serverName, required this.version});
  final String serverName;
  final String version;
}

final jellyfinRepositoryProvider = Provider<JellyfinRepository>((ref) {
  return JellyfinRepository(
    ref.watch(jellyfinApiProvider),
    ref.watch(playbackReportingApiProvider),
  );
});

class JellyfinRepository {
  JellyfinRepository(this._api, this._reporting);

  final JellyfinApi _api;
  final PlaybackReportingApi _reporting;
  String? _likedSongsPlaylistId;
  Future<List<BrowseItem>>? _searchCatalogFuture;
  Future<List<BrowseItem>>? _searchRefreshFuture;
  String? _searchCatalogSessionKey;

  static const _searchIndexVersion = 1;
  static const _searchIndexMaxAge = Duration(hours: 12);

  JellyfinSession get _session {
    final s = _api.session;
    if (s == null) throw _NoSession();
    return s;
  }

  static const _trackFields =
      'AlbumArtist,Artists,ArtistItems,AlbumId,ParentIndexNumber,ProductionYear,MediaSources,PlaylistItemId,DateCreated';

  Future<List<BrowseItem>> recentlyAddedAlbums({int limit = 20}) async {
    final s = _session;
    final res = await _api.dio.get<List<dynamic>>(
      '/Users/${s.userId}/Items/Latest',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'Limit': limit,
        'EnableImages': true,
      },
    );
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<List<BrowseItem>> recentlyPlayedAlbums({int limit = 20}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Recursive': true,
        'Limit': limit,
        'EnableUserData': true,
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((json) => (json['UserData']?['PlayCount'] as int? ?? 0) > 0)
        .toList();
    if (items.isNotEmpty) {
      return items.map(BrowseItem.fromJson).toList();
    }

    // Fallback: some Jellyfin servers don't return played albums reliably when
    // sorting MusicAlbum by DatePlayed. Build recent albums from played tracks.
    final tracksRes = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Recursive': true,
        'Limit': limit * 10,
        'Fields': 'AlbumId,UserData',
      },
    );
    final trackItems = ((tracksRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final albumIds = <String>{};
    final orderedAlbumIds = <String>[];
    for (final t in trackItems) {
      final playCount = (t['UserData']?['PlayCount'] as int? ?? 0);
      final albumId = t['AlbumId'] as String?;
      if (playCount <= 0 || albumId == null || albumId.isEmpty) continue;
      if (albumIds.add(albumId)) {
        orderedAlbumIds.add(albumId);
        if (orderedAlbumIds.length >= limit) break;
      }
    }
    if (orderedAlbumIds.isEmpty) return const [];

    final albumFutures = orderedAlbumIds.map((id) async {
      final albumRes = await _api.dio.get<Map<String, dynamic>>(
        '/Users/${s.userId}/Items/$id',
      );
      return albumRes.data;
    });
    final albumJson = (await Future.wait(
      albumFutures,
    )).whereType<Map<String, dynamic>>();
    return albumJson.map(BrowseItem.fromJson).toList();
  }

  Future<List<BrowseItem>> mostPlayedAlbums({int limit = 20}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'PlayCount',
        'SortOrder': 'Descending',
        'Recursive': true,
        'Limit': limit,
      },
    );
    final items = (res.data?['Items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>().map(BrowseItem.fromJson).toList();
  }

  /// Most-played albums touched since [since] for the current user.
  Future<List<BrowseItem>> mostPlayedAlbumsSince({
    required DateTime since,
    int limit = 20,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'SortBy': 'PlayCount',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Recursive': true,
        'MinDateLastPlayed': since.toUtc().toIso8601String(),
        'Limit': limit,
        'EnableUserData': true,
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((json) => (json['UserData']?['PlayCount'] as int? ?? 0) > 0)
        .toList();
    return items.map(BrowseItem.fromJson).toList();
  }

  Future<List<Track>> recentlyPlayedTracks({int limit = 20}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Recursive': true,
        'Limit': limit,
        'Fields': const ['MediaSources', 'DateCreated'],
        'EnableUserData': true,
      },
      options: Options(listFormat: ListFormat.multi),
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items.map(Track.fromJson).toList();
  }

  Future<List<BrowseItem>> recentlyPlayedArtists({int limit = 20}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicArtist',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Recursive': true,
        'Limit': limit,
        'EnableUserData': true,
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((json) => (json['UserData']?['PlayCount'] as int? ?? 0) > 0)
        .toList();
    if (items.isNotEmpty) {
      return items.map(BrowseItem.fromJson).toList();
    }

    // Fallback: derive recent artists from recently played tracks when the
    // server doesn't return MusicArtist sorted by DatePlayed reliably.
    final tracks = await recentlyPlayedTracks(limit: limit * 5);
    final seen = <String>{};
    final ordered = <String>[];
    for (final t in tracks) {
      final id = t.artistId;
      if (id == null || id.isEmpty) continue;
      if (seen.add(id)) {
        ordered.add(id);
        if (ordered.length >= limit) break;
      }
    }
    if (ordered.isEmpty) return const [];

    final artistJson = await Future.wait(
      ordered.map((id) async {
        final r = await _api.dio.get<Map<String, dynamic>>(
          '/Users/${s.userId}/Items/$id',
        );
        return r.data;
      }),
    );
    return artistJson
        .whereType<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  /// High-played tracks the user hasn't listened to in [coldFor]. The Jellyfin
  /// API exposes `MinDateLastPlayed` but not a "max" filter, so we sort by
  /// PlayCount, fetch a wider window, and filter client-side on
  /// `UserData.LastPlayedDate`. Tracks never played are excluded.
  Future<List<Track>> forgottenFavorites({
    int limit = 30,
    Duration coldFor = const Duration(days: 180),
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'SortBy': 'PlayCount',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Recursive': true,
        'Limit': limit * 6,
        'Fields': const [
          'MediaSources',
          'DateCreated',
          'UserDataLastPlayedDate',
        ],
        'EnableUserData': true,
      },
      options: Options(listFormat: ListFormat.multi),
    );
    final cutoff = DateTime.now().toUtc().subtract(coldFor);
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((json) {
          final lastPlayedRaw = json['UserData']?['LastPlayedDate'] as String?;
          if (lastPlayedRaw == null) return false;
          final lastPlayed = DateTime.tryParse(lastPlayedRaw);
          if (lastPlayed == null) return false;
          return lastPlayed.toUtc().isBefore(cutoff);
        })
        .take(limit)
        .toList();
    return items.map(Track.fromJson).toList();
  }

  Future<List<BrowseItem>> search(String term) async {
    final t = term.trim();
    if (t.isEmpty) return const [];
    _ensureSearchCatalogSession();
    final catalogFuture = _searchCatalogFuture ??=
        _loadPersistedSearchCatalog();
    final List<BrowseItem> catalog;
    try {
      catalog = await catalogFuture;
    } catch (_) {
      if (identical(_searchCatalogFuture, catalogFuture)) {
        _searchCatalogFuture = null;
      }
      rethrow;
    }

    final indexedResults = _filterSearchCatalog(catalog, t).take(50).toList();
    try {
      final liveResults = await _searchLive(t);
      unawaited(_upsertLoadedSearchCatalog(liveResults));
      unawaited(
        catalog.isEmpty
            ? refreshSearchCatalog()
            : _refreshSearchCatalogIfStale(),
      );
      return _mergeSearchResults(
        indexedResults,
        liveResults,
        t,
      ).take(50).toList();
    } catch (_) {
      if (catalog.isEmpty) {
        final refreshed = await refreshSearchCatalog();
        return _filterSearchCatalog(refreshed, t).take(50).toList();
      }

      unawaited(_refreshSearchCatalogIfStale());
      return indexedResults;
    }
  }

  Future<List<BrowseItem>> searchCached(String term) async {
    final t = term.trim();
    if (t.isEmpty) return const [];
    _ensureSearchCatalogSession();
    final catalog = await (_searchCatalogFuture ??=
        _loadPersistedSearchCatalog());
    return _filterSearchCatalog(catalog, t).take(50).toList();
  }

  Future<void> warmSearchCatalog({bool forceRefresh = false}) async {
    _ensureSearchCatalogSession();
    await (_searchCatalogFuture ??= _loadPersistedSearchCatalog());
    if (forceRefresh) {
      unawaited(refreshSearchCatalog());
    } else {
      unawaited(_refreshSearchCatalogIfStale());
    }
  }

  Future<List<BrowseItem>> refreshSearchCatalog() {
    _ensureSearchCatalogSession();
    final existing = _searchRefreshFuture;
    if (existing != null) return existing;

    final future = _loadSearchCatalog().then((catalog) async {
      _searchCatalogFuture = Future.value(catalog);
      await _persistSearchCatalog(catalog);
      return catalog;
    });
    _searchRefreshFuture = future;
    return future.whenComplete(() {
      if (identical(_searchRefreshFuture, future)) {
        _searchRefreshFuture = null;
      }
    });
  }

  Future<void> _refreshSearchCatalogIfStale() async {
    _ensureSearchCatalogSession();
    if (_searchRefreshFuture != null) return;
    if (!await _isSearchCatalogStale()) return;
    try {
      await refreshSearchCatalog();
    } catch (_) {
      // Search can keep using the last persisted catalog.
    }
  }

  void _ensureSearchCatalogSession() {
    final key = '${_session.serverId}_${_session.userId}';
    if (_searchCatalogSessionKey == key) return;
    _searchCatalogSessionKey = key;
    _searchCatalogFuture = null;
    _searchRefreshFuture = null;
  }

  Future<List<BrowseItem>> _loadSearchCatalog() async {
    final s = _session;
    const pageSize = 500;
    var startIndex = 0;
    final results = <BrowseItem>[];
    final seenIds = <String>{};

    while (true) {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/Users/${s.userId}/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum,MusicArtist,Audio,Playlist',
          'Recursive': true,
          'StartIndex': startIndex,
          'Limit': pageSize,
          'SortBy': 'SortName',
          'Fields': 'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks',
        },
      );
      final rawItems = ((res.data?['Items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final json in rawItems) {
        final item = BrowseItem.fromJson(json);
        if (seenIds.add(item.id)) {
          results.add(item);
        }
      }
      final total = res.data?['TotalRecordCount'] as int?;
      startIndex += rawItems.length;
      if (rawItems.length < pageSize) break;
      if (total != null && startIndex >= total) break;
    }
    return results;
  }

  Future<List<BrowseItem>> _searchLive(String term) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum,MusicArtist,Audio,Playlist',
        'Recursive': true,
        'searchTerm': term,
        'Limit': 50,
        'Fields': 'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks',
      },
    );
    final rawItems = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return rawItems.map(BrowseItem.fromJson).toList();
  }

  Future<List<BrowseItem>> _loadPersistedSearchCatalog() async {
    final file = await _searchCatalogFile();
    if (file == null || !file.existsSync()) return const [];
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const [];
      if (json['version'] != _searchIndexVersion) return const [];
      if (json['serverId'] != _session.serverId ||
          json['userId'] != _session.userId) {
        return const [];
      }
      final rawItems = (json['items'] as List?) ?? const [];
      return rawItems
          .whereType<Map<String, dynamic>>()
          .map(BrowseItem.fromSearchJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistSearchCatalog(List<BrowseItem> catalog) async {
    final file = await _searchCatalogFile();
    if (file == null) return;
    try {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(
        jsonEncode({
          'version': _searchIndexVersion,
          'serverId': _session.serverId,
          'userId': _session.userId,
          'updatedAt': DateTime.now().toIso8601String(),
          'items': catalog.map((item) => item.toSearchJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<bool> _isSearchCatalogStale() async {
    final file = await _searchCatalogFile();
    if (file == null || !file.existsSync()) return true;
    try {
      final stat = await file.stat();
      return DateTime.now().difference(stat.modified) > _searchIndexMaxAge;
    } catch (_) {
      return true;
    }
  }

  Future<File?> _searchCatalogFile() async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    final key = _safeFilePart('${_session.serverId}_${_session.userId}');
    return File('${dir.path}/search/catalog_$key.json');
  }

  String _safeFilePart(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  List<BrowseItem> _filterSearchCatalog(List<BrowseItem> catalog, String term) {
    final matches = catalog
        .where((item) => searchMatches(term, [item.name, item.subtitle]))
        .toList();
    _sortSearchResults(matches, term);
    return matches;
  }

  List<BrowseItem> _mergeSearchResults(
    List<BrowseItem> indexedResults,
    List<BrowseItem> liveResults,
    String term,
  ) {
    final byId = <String, BrowseItem>{
      for (final item in indexedResults) item.id: item,
      for (final item in liveResults) item.id: item,
    };
    final results = byId.values.toList();
    _sortSearchResults(results, term);
    return results;
  }

  void _sortSearchResults(List<BrowseItem> results, String term) {
    results.sort((a, b) {
      final relevance = searchRelevance(term, [
        b.name,
        b.subtitle,
      ]).compareTo(searchRelevance(term, [a.name, a.subtitle]));
      if (relevance != 0) return relevance;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _upsertLoadedSearchCatalog(List<BrowseItem> items) async {
    if (items.isEmpty) return;
    final catalogFuture = _searchCatalogFuture;
    if (catalogFuture == null) return;

    final List<BrowseItem> catalog;
    try {
      catalog = await catalogFuture;
    } catch (_) {
      return;
    }
    if (catalog.isEmpty) return;

    final byId = <String, BrowseItem>{
      for (final item in catalog) item.id: item,
    };
    var changed = false;
    for (final item in items) {
      final existing = byId[item.id];
      if (existing == null ||
          !mapEquals(existing.toSearchJson(), item.toSearchJson())) {
        byId[item.id] = item;
        changed = true;
      }
    }
    if (!changed) return;

    final updated = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _searchCatalogFuture = Future.value(updated);

    final file = await _searchCatalogFile();
    final previousModified = file != null && file.existsSync()
        ? (await file.stat()).modified
        : null;
    await _persistSearchCatalog(updated);
    if (previousModified != null) {
      try {
        await file!.setLastModified(previousModified);
      } catch (_) {}
    }
  }

  /// Top-played audio tracks among those played at least once after [since].
  /// Sorted by Jellyfin's all-time `PlayCount` descending.
  ///
  /// Used as a fallback for the home "For you" picks when the Playback
  /// Reporting plugin is unavailable or its per-user endpoint fails — the
  /// semantics aren't identical (plugin = "most played in this window",
  /// Jellyfin = "all-time favorites the user touched in this window") but
  /// both make sensible "Because you played" recommendations.
  Future<List<Track>> topPlayedSince({
    required DateTime since,
    int limit = 50,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'SortBy': 'PlayCount',
        'SortOrder': 'Descending',
        'Filters': 'IsPlayed',
        'Recursive': true,
        'MinDateLastPlayed': since.toUtc().toIso8601String(),
        'Limit': limit,
        'Fields': _trackFields,
        'EnableUserData': true,
      },
      options: Options(listFormat: ListFormat.multi),
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((json) => (json['UserData']?['PlayCount'] as int? ?? 0) > 0)
        .toList();
    return items.map(Track.fromJson).toList();
  }

  /// Fetch multiple tracks by id, preserving the input order. Chunked into
  /// batches so very long id lists don't trip Dio's receive timeout (large
  /// SyncPlay queues can hit 100+ ids).
  Future<List<Track>> tracksByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    const chunkSize = 50;
    final s = _session;
    final byId = <String, Track>{};
    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) continue;
      uniqueIds.add(id);
    }
    for (var i = 0; i < uniqueIds.length; i += chunkSize) {
      final chunk = uniqueIds.sublist(
        i,
        math.min(i + chunkSize, uniqueIds.length),
      );
      Map<String, dynamic>? data;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final res = await _api.dio.get<Map<String, dynamic>>(
            '/Users/${s.userId}/Items',
            queryParameters: {
              'Ids': chunk.join(','),
              'IncludeItemTypes': 'Audio',
              'Fields': _trackFields,
              'EnableUserData': true,
            },
          );
          data = res.data;
          break;
        } on DioException catch (e) {
          final status = e.response?.statusCode ?? 0;
          final shouldRetry =
              status == 429 ||
              status >= 500 ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError;
          if (!shouldRetry || attempt == 2) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
        }
      }
      if (data == null) continue;
      for (final raw in (data['Items'] as List?) ?? const []) {
        final map = raw as Map<String, dynamic>;
        byId[map['Id'] as String] = Track.fromJson(map);
      }
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Fetch multiple browse items (artists/albums/playlists) by id in a single
  /// call, preserving the input order.
  Future<List<BrowseItem>> itemsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {'Ids': ids.join(','), 'Fields': 'AlbumArtist,Artists'},
    );
    final byId = {
      for (final raw in (res.data?['Items'] as List?) ?? const [])
        (raw as Map<String, dynamic>)['Id'] as String: BrowseItem.fromJson(raw),
    };
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<Track> track(String trackId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$trackId',
      queryParameters: {'Fields': _trackFields},
    );
    return Track.fromJson(res.data ?? {});
  }

  /// Fetches lyrics for [trackId] from Jellyfin's `/Audio/{id}/Lyrics`.
  /// Returns `null` when the server has no lyrics (HTTP 404).
  Future<Lyrics?> lyrics(String trackId) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/Audio/$trackId/Lyrics',
      );
      final data = res.data;
      if (data == null) return null;
      return Lyrics.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Track>> instantMix(String itemId, {int limit = 100}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Items/$itemId/InstantMix',
      queryParameters: {
        'UserId': s.userId,
        'Limit': limit,
        'Fields': const ['MediaSources', 'DateCreated'],
        'EnableImages': true,
        'EnableUserData': true,
      },
      options: Options(listFormat: ListFormat.multi),
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items.map(Track.fromJson).toList();
  }

  Future<Album> album(String albumId) async {
    final s = _session;
    final detail = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$albumId',
    );
    final tracksRes = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'Fields': _trackFields,
      },
    );
    final tracks = ((tracksRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    return Album.fromJson(detail.data ?? {}, tracks: tracks);
  }

  Future<List<BrowseItem>> moreAlbumsByArtist({
    required String artistId,
    required String excludeAlbumId,
    int limit = 12,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'ArtistIds': artistId,
        'SortBy': 'ProductionYear,SortName',
        'SortOrder': 'Descending',
        'Limit': limit + 1,
        'Fields': 'AlbumArtist,Artists',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .where((item) => item.id != excludeAlbumId)
        .take(limit)
        .toList();
    return items;
  }

  Future<List<BrowseItem>> similarAlbums(
    String albumId, {
    String? excludeArtistName,
    int limit = 12,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Items/$albumId/Similar',
      queryParameters: {
        'UserId': s.userId,
        'Limit': limit + 1,
        'Fields': 'AlbumArtist,Artists',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .where((item) => item.kind == MediaKind.album && item.id != albumId)
        .take(limit)
        .toList();

    final artistKey = normalizeForSearch(excludeArtistName ?? '');
    if (artistKey.isNotEmpty &&
        items.isNotEmpty &&
        items.every(
          (item) => normalizeForSearch(item.subtitle ?? '') == artistKey,
        )) {
      return const [];
    }
    return items;
  }

  Future<Artist> artist(String artistId) async {
    final s = _session;
    final detail = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$artistId',
    );
    final albumsRes = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'ArtistIds': artistId,
        'SortBy': 'ProductionYear,SortName',
        'SortOrder': 'Descending',
      },
    );
    final albums = ((albumsRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
    final topTracksRes = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'ArtistIds': artistId,
        'SortBy': 'PlayCount',
        'SortOrder': 'Descending',
        'Limit': 500,
        'EnableUserData': true,
        'Fields':
            'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks,UserData',
      },
    );
    final popularTracks = ((topTracksRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    final global = await _globalPopularTracksForArtist(
      artistId: artistId,
      fallbackTracks: popularTracks,
    );
    return Artist.fromJson(
      detail.data ?? {},
      popularTracks: global,
      albums: albums,
    );
  }

  Future<List<Track>> _globalPopularTracksForArtist({
    required String artistId,
    required List<Track> fallbackTracks,
  }) async {
    final breakdown = await _reporting.globalItemBreakdown(days: 3650, limit: 2000);
    if (breakdown == null || breakdown.isEmpty) return fallbackTracks;

    final scoreByTrackId = <String, int>{};
    final orderByTrackId = <String, int>{};
    var order = 0;
    for (final row in breakdown) {
      final trackId = row.label;
      if (trackId.isEmpty) continue;
      final score = row.count > 0 ? row.count : row.timeSeconds;
      if (score <= 0) continue;
      scoreByTrackId.update(trackId, (value) => value + score, ifAbsent: () => score);
      orderByTrackId.putIfAbsent(trackId, () => order++);
    }
    if (scoreByTrackId.isEmpty) return fallbackTracks;

    final tracks = await tracksByIds(scoreByTrackId.keys.toList(growable: false));
    final byId = {for (final track in tracks) track.id: track};
    final ranked =
        scoreByTrackId.keys
            .map((id) => byId[id])
            .whereType<Track>()
            .where((track) => track.artistId == artistId)
            .toList(growable: false)
          ..sort((a, b) {
            final byScore = scoreByTrackId[b.id]!.compareTo(scoreByTrackId[a.id]!);
            if (byScore != 0) return byScore;
            return orderByTrackId[a.id]!.compareTo(orderByTrackId[b.id]!);
          });
    if (ranked.isEmpty) return fallbackTracks;
    return ranked;
  }

  Future<PlaylistDetail> playlist(String playlistId) async {
    final s = _session;
    final detail = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$playlistId',
    );
    final tracksRes = await _api.dio.get<Map<String, dynamic>>(
      '/Playlists/$playlistId/Items',
      queryParameters: {
        'UserId': s.userId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'PlaylistItemId,SortName',
        'Fields': _trackFields,
      },
    );
    final tracks = ((tracksRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    return PlaylistDetail.fromJson(detail.data ?? {}, tracks: tracks);
  }

  Future<BrowseItem?> likedSongsPlaylist() async {
    final s = _session;
    if (_likedSongsPlaylistId != null && _likedSongsPlaylistId!.isNotEmpty) {
      final detail = await _api.dio.get<Map<String, dynamic>>(
        '/Users/${s.userId}/Items/${_likedSongsPlaylistId!}',
      );
      return BrowseItem.fromJson(detail.data ?? {});
    }
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Playlist',
        'Recursive': true,
        'searchTerm': 'Liked Songs',
        'Limit': 25,
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final liked = items.firstWhere(
      (item) =>
          (item['Name'] as String?)?.toLowerCase().trim() == 'liked songs',
      orElse: () => const <String, dynamic>{},
    );
    if (liked.isEmpty) return null;
    _likedSongsPlaylistId = liked['Id'] as String?;
    return BrowseItem.fromJson(liked);
  }

  Future<List<BrowseItem>> playlists({int limit = 100}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Playlist',
        'Recursive': true,
        'Limit': limit,
        'SortBy': 'SortName',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items.map(BrowseItem.fromJson).toList();
  }

  Future<List<BrowseItem>> albums({int limit = 500}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': true,
        'Limit': limit,
        'SortBy': 'SortName',
        'Fields': 'AlbumArtist,Artists',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items.map(BrowseItem.fromJson).toList();
  }

  Future<List<BrowseItem>> artists({int limit = 500}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'MusicArtist',
        'Recursive': true,
        'Limit': limit,
        'SortBy': 'SortName',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items.map(BrowseItem.fromJson).toList();
  }

  Future<BrowseItem> createPlaylist(String name) async {
    final s = _session;
    final created = await _api.dio.post<Map<String, dynamic>>(
      '/Playlists',
      queryParameters: {'Name': name.trim(), 'UserId': s.userId},
    );
    return BrowseItem.fromJson(created.data ?? {});
  }

  Future<void> renamePlaylist({
    required String playlistId,
    required String name,
  }) async {
    await _api.dio.post<void>(
      '/Playlists/$playlistId',
      data: {'Name': name.trim()},
    );
  }

  Future<bool> addTrackToPlaylist({
    required String trackId,
    required String playlistId,
  }) async {
    final s = _session;
    final existing = await _api.dio.get<Map<String, dynamic>>(
      '/Playlists/$playlistId/Items',
      queryParameters: {
        'UserId': s.userId,
        'IncludeItemTypes': 'Audio',
        'Fields': 'Id',
      },
    );
    final alreadyInPlaylist =
        (((existing.data?['Items'] as List?) ?? const [])
                .cast<Map<String, dynamic>>())
            .any((item) => item['Id'] == trackId);
    if (alreadyInPlaylist) return false;
    await _api.dio.post<void>(
      '/Playlists/$playlistId/Items',
      queryParameters: {'Ids': trackId, 'UserId': s.userId},
    );
    return true;
  }

  Future<void> addTracksToPlaylist({
    required List<String> trackIds,
    required String playlistId,
  }) async {
    if (trackIds.isEmpty) return;
    final s = _session;
    await _api.dio.post<void>(
      '/Playlists/$playlistId/Items',
      queryParameters: {'Ids': trackIds.join(','), 'UserId': s.userId},
    );
  }

  /// Jellyfin playlist entry id for [trackId] inside [playlistId], or null.
  Future<String?> playlistEntryIdForTrack({
    required String playlistId,
    required String trackId,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Playlists/$playlistId/Items',
      queryParameters: {
        'UserId': s.userId,
        'IncludeItemTypes': 'Audio',
        'Fields': 'Id',
      },
    );
    for (final raw in (res.data?['Items'] as List?) ?? const []) {
      final item = raw as Map<String, dynamic>;
      if (item['Id'] != trackId) continue;
      final pid = item['PlaylistItemId'];
      if (pid is String && pid.isNotEmpty) return pid;
    }
    return null;
  }

  /// Playlists that contain this audio track (parallel checks).
  Future<List<PlaylistMembership>> playlistsContainingTrack(
    String trackId, {
    List<BrowseItem>? playlistsCache,
  }) async {
    final list = playlistsCache ?? await playlists();
    final futures = list.map((p) async {
      final entryId = await playlistEntryIdForTrack(
        playlistId: p.id,
        trackId: trackId,
      );
      if (entryId == null) return null;
      return PlaylistMembership(
        playlistId: p.id,
        playlistName: p.name,
        playlistItemEntryId: entryId,
      );
    });
    final results = await Future.wait(futures);
    return results.whereType<PlaylistMembership>().toList();
  }

  /// Removes one entry from a playlist ([playlistItemEntryId] is the
  /// `PlaylistItemId` from `GET /Playlists/{id}/Items`, not the track id).
  Future<void> removeTrackFromPlaylistByEntry({
    required String playlistId,
    required String playlistItemEntryId,
  }) async {
    final s = _session;
    await _api.dio.delete<void>(
      '/Playlists/$playlistId/Items',
      queryParameters: {'entryIds': playlistItemEntryId, 'UserId': s.userId},
    );
  }

  Future<void> movePlaylistItem({
    required String playlistId,
    required String playlistItemId,
    required int newIndex,
  }) async {
    final s = _session;
    await _api.dio.post<void>(
      '/Playlists/$playlistId/Items/$playlistItemId/Move/$newIndex',
      queryParameters: {'UserId': s.userId},
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    final s = _session;
    await _api.dio.delete<void>(
      '/Items/$playlistId',
      queryParameters: {'UserId': s.userId},
    );
    if (_likedSongsPlaylistId == playlistId) {
      _likedSongsPlaylistId = null;
    }
  }

  Future<void> addTrackToLikedSongs(String trackId) async {
    final playlistId = await _ensureLikedSongsPlaylistId();
    await addTrackToPlaylist(trackId: trackId, playlistId: playlistId);
  }

  Future<String> _ensureLikedSongsPlaylistId() async {
    if (_likedSongsPlaylistId != null && _likedSongsPlaylistId!.isNotEmpty) {
      return _likedSongsPlaylistId!;
    }
    final existing = await likedSongsPlaylist();
    if (existing != null) {
      _likedSongsPlaylistId = existing.id;
      return existing.id;
    }
    final s = _session;
    final created = await _api.dio.post<Map<String, dynamic>>(
      '/Playlists',
      queryParameters: {'Name': 'Liked Songs', 'UserId': s.userId},
    );
    final id = created.data?['Id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('Failed to create "Liked Songs" playlist');
    }
    _likedSongsPlaylistId = id;
    return id;
  }

  String imageUrl(String itemId, {String? imageTag, int size = 400}) {
    final s = _session;
    final params = <String, String>{
      'fillHeight': '$size',
      'fillWidth': '$size',
      'quality': '90',
      if (imageTag != null) 'tag': imageTag,
      'api_key': s.accessToken,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '${s.serverUrl}/Items/$itemId/Images/Primary?$query';
  }

  Future<String?> primaryImageUrl(String itemId, {int size = 400}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$itemId',
    );
    final tags = res.data?['ImageTags'];
    final tag = tags is Map ? tags['Primary'] as String? : null;
    if (tag == null || tag.isEmpty) return null;
    return imageUrl(itemId, imageTag: tag, size: size);
  }

  /// Whether this item is favorited (requires `UserData` on the item).
  Future<bool> isFavorite(String itemId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$itemId',
      queryParameters: const {'Fields': 'UserData'},
    );
    final data = res.data?['UserData'] as Map<String, dynamic>?;
    return (data?['IsFavorite'] as bool?) ?? false;
  }

  /// Adds or removes a user favorite in Jellyfin.
  Future<void> setFavorite(String itemId, {required bool favorite}) async {
    if (_api.session == null) throw _NoSession();
    if (favorite) {
      await _api.dio.post<void>('/UserFavoriteItems/$itemId');
    } else {
      await _api.dio.delete<void>('/UserFavoriteItems/$itemId');
    }
  }

  /// Public server info (no auth required). Returns `null` if the server
  /// can't be reached or the response isn't shaped as expected.
  Future<JellyfinServerInfo?> serverInfo() async {
    final s = _api.session;
    if (s == null) return null;
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/System/Info/Public',
      );
      final data = res.data;
      if (data == null) return null;
      return JellyfinServerInfo(
        serverName: data['ServerName'] as String? ?? '',
        version: data['Version'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Build a Jellyfin stream URL for [trackId].
  ///
  /// [maxBitrate] caps transcoding bitrate (in bps). Pass `null` to request
  /// the source file untouched (no transcoding).
  String streamUrl(String trackId, {int? maxBitrate = 320000}) {
    final s = _session;
    final params = <String, String>{
      'UserId': s.userId,
      'api_key': s.accessToken,
      'DeviceId': 'altsound-${s.userId}',
      if (maxBitrate != null && maxBitrate > 0)
        'MaxStreamingBitrate': maxBitrate.toString(),
      // Keep stream progressive (non-HLS) so ExoPlayer/just_audio can parse it
      // through AudioSource.uri without playlist-specific handling.
      'Static': 'true',
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '${s.serverUrl}/Audio/$trackId/stream?$query';
  }
}
