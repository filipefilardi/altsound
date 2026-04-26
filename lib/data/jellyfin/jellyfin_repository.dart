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
  String? _likedSongsPlaylistId;

  JellyfinSession get _session {
    final s = _api.session;
    if (s == null) throw _NoSession();
    return s;
  }

  static const _trackFields =
      'AlbumArtist,Artists,ArtistItems,AlbumId,ParentIndexNumber,ProductionYear,MediaSources';

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
        'IncludeItemTypes': 'MusicAlbum,MusicArtist,Audio,Playlist',
        'Recursive': true,
        'Limit': 50,
        'Fields': 'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks',
      },
    );
    final rawItems = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final results = rawItems
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();

    final artistIds = rawItems
        .where((item) => item['Type'] == 'MusicArtist')
        .map((item) => item['Id'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (artistIds.isEmpty) return results;

    final tracksForArtists = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'ArtistIds': artistIds.join(','),
        'Limit': 100,
        'SortBy': 'SortName',
        'Fields': 'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks',
      },
    );
    final extraTracks = (((tracksForArtists.data?['Items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
        .map(BrowseItem.fromJson)
        .where((item) => item.kind == MediaKind.track)
        .toList();

    final existingIds = results.map((item) => item.id).toSet();
    for (final track in extraTracks) {
      if (existingIds.add(track.id)) {
        results.add(track);
      }
    }
    return results;
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
        'SortOrder': 'Ascending',
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
        'Fields': 'AlbumArtist,Artists,ArtistItems,AlbumId,RunTimeTicks,UserData',
      },
    );
    final popularTracks = ((topTracksRes.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    return Artist.fromJson(
      detail.data ?? {},
      popularTracks: popularTracks,
      albums: albums,
    );
  }

  Future<PlaylistDetail> playlist(String playlistId) async {
    final s = _session;
    final detail = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$playlistId',
    );
    final tracksRes = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'ParentId': playlistId,
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
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

  Future<BrowseItem> createPlaylist(String name) async {
    final s = _session;
    final created = await _api.dio.post<Map<String, dynamic>>(
      '/Playlists',
      queryParameters: {
        'Name': name.trim(),
        'UserId': s.userId,
      },
    );
    return BrowseItem.fromJson(created.data ?? {});
  }

  Future<void> addTrackToPlaylist({
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
    final alreadyInPlaylist = (((existing.data?['Items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
        .any((item) => item['Id'] == trackId);
    if (alreadyInPlaylist) return;
    await _api.dio.post<void>(
      '/Playlists/$playlistId/Items',
      queryParameters: {
        'Ids': trackId,
        'UserId': s.userId,
      },
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
      final entryId =
          await playlistEntryIdForTrack(playlistId: p.id, trackId: trackId);
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
      queryParameters: {
        'entryIds': playlistItemEntryId,
        'UserId': s.userId,
      },
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
      queryParameters: {
        'Name': 'Liked Songs',
        'UserId': s.userId,
      },
    );
    final id = created.data?['Id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('Failed to create "Liked Songs" playlist');
    }
    _likedSongsPlaylistId = id;
    return id;
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
