import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/jellyfin/models/media_item.dart';
import 'recommendations_provider.dart';

/// Persisted form of `HomeRecommendations`. The `dateKey` is local-day
/// (`YYYY-MM-DD`) — comparing it against today's local-day key tells the
/// provider whether the cache is fresh or needs a daily refresh.
class CachedRecommendations {
  const CachedRecommendations({
    required this.dateKey,
    required this.recs,
  });
  final String dateKey;
  final HomeRecommendations recs;
}

const _cacheVersion = 1;

final recommendationsCacheProvider = Provider<RecommendationsCache>((ref) {
  return const RecommendationsCache();
});

class RecommendationsCache {
  const RecommendationsCache();

  Future<CachedRecommendations?> load(String serverId, String userId) async {
    final file = await _file(serverId, userId);
    if (file == null || !file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return null;
      if (raw['version'] != _cacheVersion) return null;
      if (raw['serverId'] != serverId || raw['userId'] != userId) return null;
      final dateKey = raw['date'] as String?;
      if (dateKey == null || dateKey.isEmpty) return null;
      final recs = HomeRecommendations(
        topSong: _trackFromJson(raw['topSong']),
        topArtists: ((raw['topArtists'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BrowseItem.fromSearchJson)
            .toList(),
        forgottenFavorites: ((raw['forgottenFavorites'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_trackFromJson)
            .whereType<Track>()
            .toList(),
      );
      return CachedRecommendations(dateKey: dateKey, recs: recs);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String serverId,
    String userId,
    String dateKey,
    HomeRecommendations recs,
  ) async {
    final file = await _file(serverId, userId);
    if (file == null) return;
    try {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(jsonEncode({
        'version': _cacheVersion,
        'serverId': serverId,
        'userId': userId,
        'date': dateKey,
        'topSong': _trackToJson(recs.topSong),
        'topArtists':
            recs.topArtists.map((a) => a.toSearchJson()).toList(),
        'forgottenFavorites': recs.forgottenFavorites
            .map((t) => _trackToJson(t))
            .toList(),
      }));
    } catch (_) {
      // Cache failure is non-fatal — picks just won't survive across launches.
    }
  }

  Future<void> clear(String serverId, String userId) async {
    final file = await _file(serverId, userId);
    if (file == null || !file.existsSync()) return;
    try {
      await file.delete();
    } catch (_) {
      // Cache deletion is best-effort.
    }
  }

  Future<File?> _file(String serverId, String userId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final key = base64Url.encode(utf8.encode('${serverId}_$userId'))
          .replaceAll('=', '');
      return File('${dir.path}/recommendations/v${_cacheVersion}_$key.json');
    } catch (_) {
      return null;
    }
  }
}

/// Local-day stamp ("YYYY-MM-DD") used to decide whether the cache is fresh.
String todayDateKey() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

Map<String, dynamic>? _trackToJson(Track? t) {
  if (t == null) return null;
  return {
    'id': t.id,
    'name': t.name,
    'albumId': t.albumId,
    'albumName': t.albumName,
    'artistName': t.artistName,
    'artistId': t.artistId,
    'durationMs': t.duration.inMilliseconds,
    'trackNumber': t.trackNumber,
    'discNumber': t.discNumber,
    'imageTag': t.imageTag,
    'albumImageItemId': t.albumImageItemId,
    'playlistItemId': t.playlistItemId,
    'dateAdded': t.dateAdded?.toIso8601String(),
  };
}

Track? _trackFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final id = raw['id'] as String?;
  if (id == null || id.isEmpty) return null;
  final dateAddedRaw = raw['dateAdded'] as String?;
  return Track(
    id: id,
    name: raw['name'] as String? ?? 'Untitled',
    albumId: raw['albumId'] as String?,
    albumName: raw['albumName'] as String?,
    artistName: raw['artistName'] as String? ?? 'Unknown Artist',
    artistId: raw['artistId'] as String?,
    duration: Duration(milliseconds: (raw['durationMs'] as int?) ?? 0),
    trackNumber: raw['trackNumber'] as int?,
    discNumber: raw['discNumber'] as int?,
    imageTag: raw['imageTag'] as String?,
    albumImageItemId: raw['albumImageItemId'] as String?,
    playlistItemId: raw['playlistItemId'] as String?,
    dateAdded:
        dateAddedRaw == null ? null : DateTime.tryParse(dateAddedRaw),
  );
}
