import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lidarr_config.dart';
import 'models/lidarr_models.dart';

class LidarrException implements Exception {
  const LidarrException(this.message);
  final String message;
  @override
  String toString() => message;
}

final lidarrRepositoryProvider = Provider<LidarrRepository?>((ref) {
  final config = ref.watch(lidarrConfigProvider);
  if (config == null) return null;
  return LidarrRepository(config);
});

/// Set of MusicBrainz artist MBIDs currently monitored in Lidarr.
/// Used across screens for status badges; not autoDispose so it stays cached.
final lidarrMonitoredArtistIdsProvider = FutureProvider<Set<String>>((ref) async {
  final repo = ref.watch(lidarrRepositoryProvider);
  if (repo == null) return const {};
  try {
    final artists = await repo.monitoredArtists();
    return {for (final a in artists) if (a.foreignArtistId.isNotEmpty) a.foreignArtistId};
  } catch (_) {
    return const {};
  }
});

class LidarrRepository {
  LidarrRepository(this._config) {
    final base = _normalize(_config.url);
    _dio = Dio(BaseOptions(
      baseUrl: base,
      headers: {'X-Api-Key': _config.apiKey},
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  final LidarrConfig _config;
  late final Dio _dio;

  String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Future<bool> ping() async {
    try {
      await _dio.get<dynamic>('/api/v1/system/status');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<LidarrArtistResult>> searchArtists(String term) async {
    if (term.trim().isEmpty) return [];
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/artist/lookup',
      queryParameters: {'term': term},
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry('$k', v)))
        .map(LidarrArtistResult.fromJson)
        .toList();
  }

  Future<List<LidarrArtistResult>> monitoredArtists() async {
    final res = await _dio.get<List<dynamic>>('/api/v1/artist');
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LidarrArtistResult.fromJson)
        .toList();
  }

  Future<List<LidarrAlbumResult>> artistAlbums({
    required String artistName,
    String? foreignArtistId,
  }) async {
    if (artistName.trim().isEmpty) return const [];
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/album/lookup',
      queryParameters: {'term': artistName.trim()},
    );
    final all = (res.data ?? const [])
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry('$k', v)))
        .map(LidarrAlbumResult.fromJson)
        .toList();
    if (foreignArtistId == null || foreignArtistId.isEmpty) return all;
    return all
        .where((a) => a.artistName.toLowerCase() == artistName.toLowerCase())
        .toList();
  }

  Future<LidarrDefaults> defaults() async {
    final results = await Future.wait([
      _dio.get<List<dynamic>>('/api/v1/qualityprofile'),
      _dio.get<List<dynamic>>('/api/v1/metadataprofile'),
      _dio.get<List<dynamic>>('/api/v1/rootfolder'),
    ]);
    final qualities = (results[0].data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LidarrQualityProfile.fromJson)
        .toList();
    final metadatas = (results[1].data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LidarrMetadataProfile.fromJson)
        .toList();
    final folders = (results[2].data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LidarrRootFolder.fromJson)
        .toList();
    if (qualities.isEmpty || metadatas.isEmpty || folders.isEmpty) {
      throw const LidarrException(
        'Lidarr is missing a quality profile, metadata profile, or root folder.',
      );
    }
    return LidarrDefaults(
      qualityProfileId: qualities.first.id,
      metadataProfileId: metadatas.first.id,
      rootFolderPath: folders.first.path,
    );
  }

  Future<void> addAlbum(
    LidarrArtistResult artist,
    LidarrAlbumResult album, {
    required LidarrDefaults defaults,
  }) async {
    if (album.foreignAlbumId.isEmpty) {
      throw const LidarrException('Album has no MusicBrainz ID — cannot request it.');
    }
    final payload = <String, dynamic>{
      ...artist.raw,
      'qualityProfileId': defaults.qualityProfileId,
      'metadataProfileId': defaults.metadataProfileId,
      'rootFolderPath': defaults.rootFolderPath,
      'monitored': true,
      'monitorNewItems': 'none',
      'addOptions': {
        'monitor': 'specificAlbum',
        'albumsToMonitor': [album.foreignAlbumId],
        'searchForMissingAlbums': true,
      },
    };
    payload.remove('id');
    await _dio.post<Map<String, dynamic>>('/api/v1/artist', data: payload);
  }
}
