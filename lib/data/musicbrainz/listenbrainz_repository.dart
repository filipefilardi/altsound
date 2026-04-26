import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class LbArtist {
  const LbArtist({
    required this.artistName,
    this.artistMbid,
    required this.listenCount,
  });

  final String artistName;
  final String? artistMbid;
  final int listenCount;

  factory LbArtist.fromJson(Map<String, dynamic> json) {
    final mbids = json['artist_mbids'] as List?;
    return LbArtist(
      artistName: json['artist_name'] as String? ?? 'Unknown',
      artistMbid: (mbids?.isNotEmpty ?? false) ? mbids!.first as String? : null,
      listenCount: json['listen_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'artist_name': artistName,
        'artist_mbids': artistMbid != null ? [artistMbid] : <String>[],
        'listen_count': listenCount,
      };
}

class LbReleaseGroup {
  const LbReleaseGroup({
    required this.title,
    this.mbid,
    required this.artistName,
    this.artistMbid,
    required this.listenCount,
  });

  final String title;
  final String? mbid;
  final String artistName;
  final String? artistMbid;
  final int listenCount;

  String? get coverArtUrl =>
      mbid != null ? 'https://coverartarchive.org/release-group/$mbid/front' : null;

  factory LbReleaseGroup.fromJson(Map<String, dynamic> json) {
    final mbids = json['artist_mbids'] as List?;
    return LbReleaseGroup(
      title: json['release_group_name'] as String? ?? 'Unknown Album',
      mbid: json['release_group_mbid'] as String?,
      artistName: json['artist_name'] as String? ?? 'Unknown Artist',
      artistMbid: (mbids?.isNotEmpty ?? false) ? mbids!.first as String? : null,
      listenCount: json['listen_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'release_group_name': title,
        'release_group_mbid': mbid,
        'artist_name': artistName,
        'artist_mbids': artistMbid != null ? [artistMbid] : <String>[],
        'listen_count': listenCount,
      };
}

/// A single recording (track) from ListenBrainz stats.
class LbRecording {
  const LbRecording({
    required this.trackName,
    this.recordingMbid,
    required this.artistName,
    this.artistMbid,
    this.releaseName,
    this.releaseGroupMbid,
    required this.listenCount,
  });

  final String trackName;
  final String? recordingMbid;
  final String artistName;
  final String? artistMbid;
  final String? releaseName;
  final String? releaseGroupMbid;
  final int listenCount;

  factory LbRecording.fromJson(Map<String, dynamic> json) {
    final mbids = json['artist_mbids'] as List?;
    return LbRecording(
      trackName: json['track_name'] as String? ?? 'Unknown',
      recordingMbid: json['recording_mbid'] as String?,
      artistName: json['artist_name'] as String? ?? '',
      artistMbid: (mbids?.isNotEmpty ?? false) ? mbids!.first as String? : null,
      releaseName: json['release_name'] as String?,
      releaseGroupMbid: json['release_group_mbid'] as String?,
      listenCount: json['listen_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'track_name': trackName,
        'recording_mbid': recordingMbid,
        'artist_name': artistName,
        'artist_mbids': artistMbid != null ? [artistMbid] : <String>[],
        'release_name': releaseName,
        'release_group_mbid': releaseGroupMbid,
        'listen_count': listenCount,
      };
}

/// A release (album) from per-artist ListenBrainz stats.
class LbArtistRelease {
  const LbArtistRelease({
    required this.title,
    this.releaseGroupMbid,
    required this.listenCount,
  });

  final String title;
  final String? releaseGroupMbid;
  final int listenCount;

  String? get coverArtUrl => releaseGroupMbid != null
      ? 'https://coverartarchive.org/release-group/$releaseGroupMbid/front'
      : null;

  factory LbArtistRelease.fromJson(Map<String, dynamic> json) => LbArtistRelease(
        title: json['release_name'] as String? ??
            json['release_group_name'] as String? ??
            'Unknown',
        releaseGroupMbid: json['release_group_mbid'] as String?,
        listenCount: json['listen_count'] as int? ?? 0,
      );
}

// ── Providers ────────────────────────────────────────────────────────────────

final listenBrainzRepositoryProvider = Provider<ListenBrainzRepository>(
  (ref) => ListenBrainzRepository(),
);

final trendingArtistsProvider = FutureProvider<List<LbArtist>>((ref) {
  return ref.read(listenBrainzRepositoryProvider).topArtists();
});

final trendingReleaseGroupsProvider = FutureProvider<List<LbReleaseGroup>>((ref) {
  return ref.read(listenBrainzRepositoryProvider).topReleaseGroups();
});

final trendingRecordingsProvider = FutureProvider<List<LbRecording>>((ref) {
  return ref.read(listenBrainzRepositoryProvider).topRecordings();
});

/// Per-artist top releases from ListenBrainz. Not autoDispose — artist screen
/// switches tabs and we don't want to re-fetch.
final artistTopReleasesProvider =
    FutureProvider.family<List<LbArtistRelease>, String>((ref, mbid) {
  return ref.read(listenBrainzRepositoryProvider).artistTopReleases(mbid);
});

/// Per-artist top recordings from ListenBrainz.
final artistTopRecordingsProvider =
    FutureProvider.family<List<LbRecording>, String>((ref, mbid) {
  return ref.read(listenBrainzRepositoryProvider).artistTopRecordings(mbid);
});

// ── Repository ───────────────────────────────────────────────────────────────

class ListenBrainzRepository {
  ListenBrainzRepository() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.listenbrainz.org/1',
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  late final Dio _dio;

  static const _kCacheTtl = Duration(hours: 6);

  // In-memory cache for per-artist stats (keyed by MBID).
  final _artistReleasesCache = <String, List<LbArtistRelease>>{};
  final _artistRecordingsCache = <String, List<LbRecording>>{};

  // ── Disk cache helpers ──────────────────────────────────────────────────

  Future<File> _cacheFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/altsound_cache');
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/$key.json');
  }

  Future<List<Map<String, dynamic>>?> _readCache(String key) async {
    try {
      final file = await _cacheFile(key);
      if (!file.existsSync()) return null;
      if (DateTime.now().difference(file.lastModifiedSync()) > _kCacheTtl) return null;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (data['items'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, List<Map<String, dynamic>> items) async {
    try {
      final file = await _cacheFile(key);
      await file.writeAsString(jsonEncode({'items': items}));
    } catch (_) {}
  }

  // ── Sitewide trending ───────────────────────────────────────────────────

  Future<List<LbArtist>> topArtists({int count = 12}) async {
    final cached = await _readCache('lb_artists');
    if (cached != null) return cached.map(LbArtist.fromJson).toList();

    final res = await _dio.get<Map<String, dynamic>>(
      '/stats/sitewide/artists',
      queryParameters: {'count': count, 'range': 'week'},
    );
    final items = (res.data?['payload']?['artists'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LbArtist.fromJson)
        .toList();
    await _writeCache('lb_artists', items.map((a) => a.toJson()).toList());
    return items;
  }

  Future<List<LbReleaseGroup>> topReleaseGroups({int count = 10}) async {
    final cached = await _readCache('lb_releases');
    if (cached != null) return cached.map(LbReleaseGroup.fromJson).toList();

    final res = await _dio.get<Map<String, dynamic>>(
      '/stats/sitewide/release-groups',
      queryParameters: {'count': count, 'range': 'week'},
    );
    final items = (res.data?['payload']?['release_groups'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LbReleaseGroup.fromJson)
        .toList();
    await _writeCache('lb_releases', items.map((r) => r.toJson()).toList());
    return items;
  }

  Future<List<LbRecording>> topRecordings({int count = 10}) async {
    final cached = await _readCache('lb_recordings');
    if (cached != null) return cached.map(LbRecording.fromJson).toList();

    final res = await _dio.get<Map<String, dynamic>>(
      '/stats/sitewide/recordings',
      queryParameters: {'count': count, 'range': 'week'},
    );
    final items = (res.data?['payload']?['recordings'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LbRecording.fromJson)
        .toList();
    await _writeCache('lb_recordings', items.map((r) => r.toJson()).toList());
    return items;
  }

  // ── Per-artist stats ────────────────────────────────────────────────────

  Future<List<LbArtistRelease>> artistTopReleases(String artistMbid,
      {int count = 10}) async {
    if (_artistReleasesCache.containsKey(artistMbid)) {
      return _artistReleasesCache[artistMbid]!;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/stats/artist/$artistMbid/releases',
        queryParameters: {'count': count, 'range': 'all_time'},
      );
      final items = (res.data?['payload']?['releases'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LbArtistRelease.fromJson)
          .toList();
      _artistReleasesCache[artistMbid] = items;
      return items;
    } on DioException catch (e) {
      // 204 = no stats available for this artist; treat as empty.
      if (e.response?.statusCode == 204 || e.response?.statusCode == 404) {
        _artistReleasesCache[artistMbid] = const [];
        return const [];
      }
      rethrow;
    }
  }

  Future<List<LbRecording>> artistTopRecordings(String artistMbid,
      {int count = 10}) async {
    if (_artistRecordingsCache.containsKey(artistMbid)) {
      return _artistRecordingsCache[artistMbid]!;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/stats/artist/$artistMbid/recordings',
        queryParameters: {'count': count, 'range': 'all_time'},
      );
      final items = (res.data?['payload']?['recordings'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LbRecording.fromJson)
          .toList();
      _artistRecordingsCache[artistMbid] = items;
      return items;
    } on DioException catch (e) {
      if (e.response?.statusCode == 204 || e.response?.statusCode == 404) {
        _artistRecordingsCache[artistMbid] = const [];
        return const [];
      }
      rethrow;
    }
  }
}
