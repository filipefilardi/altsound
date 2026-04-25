import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/jellyfin_session.dart';
import 'models/media_item.dart';

class _NoSession implements Exception {
  @override
  String toString() => 'No active Jellyfin session';
}

final jellyfinRepositoryProvider = Provider<JellyfinRepository>((ref) {
  return JellyfinRepository(ref.watch(jellyfinApiProvider));
});

class JellyfinRepository {
  JellyfinRepository(this._api);

  final JellyfinApi _api;

  JellyfinSession get _session {
    final s = _api.session;
    if (s == null) throw _NoSession();
    return s;
  }

  static const _trackFields =
      'AlbumArtist,Artists,AlbumId,ParentIndexNumber,ProductionYear,MediaSources';

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
    final albumJson = (await Future.wait(albumFutures)).whereType<Map<String, dynamic>>();
    return albumJson
        .map(BrowseItem.fromJson)
        .toList();
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
    return items
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<List<BrowseItem>> search(String term) async {
    final t = term.trim();
    if (t.isEmpty) return const [];
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'searchTerm': t,
        'IncludeItemTypes': 'MusicAlbum,MusicArtist,Audio',
        'Recursive': true,
        'Limit': 50,
        'Fields': 'AlbumArtist,Artists,AlbumId,RunTimeTicks',
      },
    );
    final items = (res.data?['Items'] as List?) ?? const [];
    return items
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<Track> track(String trackId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$trackId',
      queryParameters: {'Fields': _trackFields},
    );
    return Track.fromJson(res.data ?? {});
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

  String imageUrl(
    String itemId, {
    String? imageTag,
    int size = 400,
  }) {
    final s = _session;
    final params = <String, String>{
      'fillHeight': '$size',
      'fillWidth': '$size',
      'quality': '90',
      if (imageTag != null) 'tag': imageTag,
      'api_key': s.accessToken,
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '${s.serverUrl}/Items/$itemId/Images/Primary?$query';
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

  String streamUrl(String trackId) {
    final s = _session;
    final params = <String, String>{
      'UserId': s.userId,
      'api_key': s.accessToken,
      'DeviceId': 'jellymusic-${s.userId}',
      'MaxStreamingBitrate': '320000',
      // Keep stream progressive (non-HLS) so ExoPlayer/just_audio can parse it
      // through AudioSource.uri without playlist-specific handling.
      'Static': 'true',
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '${s.serverUrl}/Audio/$trackId/stream?$query';
  }
}
