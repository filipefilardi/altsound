import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
final lidarrMonitoredArtistIdsProvider = FutureProvider<Set<String>>((
  ref,
) async {
  final repo = ref.watch(lidarrRepositoryProvider);
  if (repo == null) return const {};
  try {
    final artists = await repo.monitoredArtists();
    return {
      for (final a in artists)
        if (a.foreignArtistId.isNotEmpty) a.foreignArtistId,
    };
  } catch (_) {
    return const {};
  }
});

/// MusicBrainz release-group IDs already known to Lidarr, keyed to their
/// Lidarr album rows so UI can decide whether the album is actually missing.
final lidarrAlbumsByForeignIdProvider =
    FutureProvider<Map<String, LidarrAlbumResult>>((ref) async {
      final repo = ref.watch(lidarrRepositoryProvider);
      if (repo == null) return const {};
      try {
        final albums = await repo.albums();
        return {
          for (final album in albums)
            if (album.foreignAlbumId.isNotEmpty) album.foreignAlbumId: album,
        };
      } catch (_) {
        return const {};
      }
    });

class LidarrRepository {
  LidarrRepository(this._config) {
    final base = _normalize(_config.url);
    _dio = Dio(
      BaseOptions(
        baseUrl: base,
        headers: {'X-Api-Key': _config.apiKey},
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
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

  Future<List<LidarrAlbumResult>> albums({int? artistId}) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/album',
      queryParameters: {if (artistId != null) 'artistId': artistId},
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry('$k', v)))
        .map(LidarrAlbumResult.fromJson)
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
    try {
      if (album.foreignAlbumId.isEmpty) {
        throw const LidarrException(
          'Album has no MusicBrainz ID — cannot request it.',
        );
      }
      final existingArtist = await _existingArtist(artist);
      if (existingArtist?.id case final int artistId) {
        await _requestArtistAlbum(artistId, album, refreshFirst: true);
        return;
      }

      await _addArtistWithSpecificAlbum(artist, album, defaults: defaults);
    } on LidarrException {
      rethrow;
    } on DioException catch (e) {
      throw LidarrException(_dioErrorMessage(e));
    }
  }

  Future<void> addMusicBrainzAlbum(
    LidarrArtistResult artist, {
    required String foreignAlbumId,
    required String title,
    required String artistName,
    required LidarrDefaults defaults,
  }) {
    return addAlbum(
      artist,
      LidarrAlbumResult.musicBrainzRelease(
        foreignAlbumId: foreignAlbumId,
        title: title,
        artistName: artistName,
      ),
      defaults: defaults,
    );
  }

  Future<LidarrArtistResult?> _existingArtist(LidarrArtistResult artist) async {
    if (artist.id != null) return artist;
    if (artist.foreignArtistId.isEmpty) return null;
    final artists = await monitoredArtists();
    for (final existing in artists) {
      if (existing.foreignArtistId == artist.foreignArtistId) return existing;
    }
    return null;
  }

  Future<void> _requestArtistAlbum(
    int artistId,
    LidarrAlbumResult album, {
    required bool refreshFirst,
  }) async {
    if (refreshFirst) {
      await _refreshArtist(artistId);
    }
    final existingAlbum = await _findArtistAlbum(
      artistId,
      album.foreignAlbumId,
    );
    if (existingAlbum?.id case final int albumId) {
      await _monitorAndSearchAlbum(albumId);
      return;
    }

    throw LidarrException(
      'Lidarr knows this artist, but "${album.title}" is not available under '
      'that artist. Check the artist metadata profile in Lidarr, refresh the '
      'artist, then request it again.',
    );
  }

  Future<LidarrAlbumResult?> _findArtistAlbum(
    int artistId,
    String foreignAlbumId,
  ) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      final existingAlbum = (await albums(
        artistId: artistId,
      )).where((a) => a.foreignAlbumId == foreignAlbumId).firstOrNull;
      if (existingAlbum != null) return existingAlbum;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  Future<void> _monitorAndSearchAlbum(int albumId) async {
    await _dio.put<dynamic>(
      '/api/v1/album/monitor',
      data: {
        'albumIds': [albumId],
        'monitored': true,
      },
    );
    await _dio.post<dynamic>(
      '/api/v1/command',
      data: {
        'name': 'AlbumSearch',
        'albumIds': [albumId],
      },
    );
  }

  Future<void> _refreshArtist(int artistId) async {
    await _dio.post<dynamic>(
      '/api/v1/command',
      data: {'name': 'RefreshArtist', 'artistId': artistId},
    );
  }

  Future<void> _addArtistWithSpecificAlbum(
    LidarrArtistResult artist,
    LidarrAlbumResult album, {
    required LidarrDefaults defaults,
  }) async {
    final payload = <String, dynamic>{
      ...artist.raw,
      'qualityProfileId': defaults.qualityProfileId,
      'metadataProfileId': defaults.metadataProfileId,
      'rootFolderPath': defaults.rootFolderPath,
      'monitored': true,
      'monitorNewItems': 'none',
      'addOptions': {'monitor': 'none', 'searchForMissingAlbums': false},
    };
    payload.remove('id');
    final res = await _dio.post<dynamic>('/api/v1/artist', data: payload);
    final addedArtist = res.data;
    final artistId = addedArtist is Map
        ? (addedArtist['id'] as num?)?.toInt()
        : null;
    if (artistId == null) {
      throw const LidarrException(
        'Lidarr added the artist, but did not return an artist ID.',
      );
    }
    await _requestArtistAlbum(artistId, album, refreshFirst: true);
  }

  String _dioErrorMessage(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    final details = _responseMessages(data).toSet().join('\n');
    _logDioException(e, details);
    if (details.isNotEmpty) {
      return status == null ? details : 'Lidarr $status: $details';
    }
    return e.message ?? e.toString();
  }

  void _logDioException(DioException e, String details) {
    final request = e.requestOptions;
    final status = e.response?.statusCode;
    debugPrint(
      '[Lidarr] ${request.method} ${request.uri} failed'
      '${status == null ? '' : ' with HTTP $status'}',
    );
    if (request.data != null) {
      debugPrint('[Lidarr] Request body:\n${_formatForLog(request.data)}');
    }
    debugPrint('[Lidarr] Response body:\n${_formatForLog(e.response?.data)}');
    if (details.isNotEmpty) {
      debugPrint('[Lidarr] Parsed validation:\n$details');
    }
  }

  String _formatForLog(Object? value) {
    if (value == null) return '<empty>';
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  List<String> _responseMessages(Object? data) {
    if (data == null) return const [];
    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty ? const [] : [trimmed];
    }
    if (data is List) {
      return [for (final item in data) ..._responseMessages(item)];
    }
    if (data is Map) {
      final messages = <String>[];
      final property = data['propertyName'] ?? data['property'];
      final message = data['errorMessage'] ?? data['message'];
      if (property != null && message != null) {
        messages.add('$property: $message');
      }

      for (final key in [
        'errors',
        'validationErrors',
        'validationFailures',
        'details',
      ]) {
        messages.addAll(_responseMessages(data[key]));
      }

      if (messages.isEmpty) {
        for (final entry in data.entries) {
          final nestedMessages = _responseMessages(entry.value);
          for (final nestedMessage in nestedMessages) {
            messages.add('${entry.key}: $nestedMessage');
          }
        }
      }

      if (messages.isEmpty) {
        for (final key in ['errorMessage', 'message', 'error', 'title']) {
          final value = data[key];
          if (value is String && value.trim().isNotEmpty) {
            messages.add(value.trim());
          }
        }
      }

      return messages.isEmpty ? [data.toString()] : messages;
    }
    return [data.toString()];
  }
}
