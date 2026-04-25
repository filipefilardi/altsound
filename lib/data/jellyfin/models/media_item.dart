enum MediaKind { album, artist, playlist, track }

MediaKind? _kindFromJellyfinType(String? type) {
  switch (type) {
    case 'MusicAlbum':
      return MediaKind.album;
    case 'MusicArtist':
      return MediaKind.artist;
    case 'Playlist':
      return MediaKind.playlist;
    case 'Audio':
      return MediaKind.track;
    default:
      return null;
  }
}

Duration _durationFromTicks(int? ticks) {
  if (ticks == null) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

class BrowseItem {
  const BrowseItem({
    required this.id,
    required this.name,
    required this.kind,
    this.subtitle,
    this.imageTag,
    this.runTime,
    this.childCount,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? imageTag;
  final MediaKind kind;
  final Duration? runTime;
  final int? childCount;

  factory BrowseItem.fromJson(Map<String, dynamic> json) {
    final type = json['Type'] as String?;
    final kind = _kindFromJellyfinType(type) ?? MediaKind.album;

    String? subtitle;
    switch (kind) {
      case MediaKind.album:
        subtitle = json['AlbumArtist'] as String? ??
            (json['Artists'] as List?)?.cast<String>().firstOrNull;
      case MediaKind.track:
        subtitle = json['Artists'] is List
            ? (json['Artists'] as List).cast<String>().join(', ')
            : json['AlbumArtist'] as String?;
      case MediaKind.artist:
        subtitle = 'Artist';
      case MediaKind.playlist:
        subtitle = 'Playlist';
    }

    return BrowseItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      subtitle: subtitle,
      imageTag: _primaryImageTag(json),
      kind: kind,
      runTime: json['RunTimeTicks'] != null
          ? _durationFromTicks(json['RunTimeTicks'] as int?)
          : null,
      childCount: json['ChildCount'] as int?,
    );
  }
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artistName,
    required this.artistId,
    required this.year,
    required this.imageTag,
    required this.tracks,
  });

  final String id;
  final String name;
  final String artistName;
  final String? artistId;
  final int? year;
  final String? imageTag;
  final List<Track> tracks;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (sum, t) => sum + t.duration,
      );

  factory Album.fromJson(
    Map<String, dynamic> json, {
    List<Track> tracks = const [],
  }) {
    return Album(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      artistName: json['AlbumArtist'] as String? ?? 'Unknown Artist',
      artistId: (json['AlbumArtists'] as List?)
          ?.cast<Map<String, dynamic>>()
          .firstOrNull?['Id'] as String?,
      year: json['ProductionYear'] as int?,
      imageTag: _primaryImageTag(json),
      tracks: tracks,
    );
  }
}

class Track {
  const Track({
    required this.id,
    required this.name,
    required this.albumId,
    required this.albumName,
    required this.artistName,
    required this.artistId,
    required this.duration,
    required this.trackNumber,
    required this.discNumber,
    required this.imageTag,
    required this.albumImageItemId,
  });

  final String id;
  final String name;
  final String? albumId;
  final String? albumName;
  final String artistName;
  final String? artistId;
  final Duration duration;
  final int? trackNumber;
  final int? discNumber;
  final String? imageTag;
  final String? albumImageItemId;

  factory Track.fromJson(Map<String, dynamic> json) {
    final artists = (json['Artists'] as List?)?.cast<String>();
    final artistId = (json['ArtistItems'] as List?)
        ?.cast<Map<String, dynamic>>()
        .firstOrNull?['Id'] as String?;
    return Track(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      albumId: json['AlbumId'] as String?,
      albumName: json['Album'] as String?,
      artistName: artists?.join(', ') ??
          json['AlbumArtist'] as String? ??
          'Unknown Artist',
      artistId: artistId,
      duration: _durationFromTicks(json['RunTimeTicks'] as int?),
      trackNumber: json['IndexNumber'] as int?,
      discNumber: json['ParentIndexNumber'] as int?,
      imageTag: _primaryImageTag(json),
      albumImageItemId: json['AlbumId'] as String?,
    );
  }

  String get imageItemId => albumImageItemId ?? id;
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.imageTag,
    required this.popularTracks,
    required this.albums,
  });

  final String id;
  final String name;
  final String? imageTag;
  final List<Track> popularTracks;
  final List<BrowseItem> albums;

  factory Artist.fromJson(
    Map<String, dynamic> json, {
    List<Track> popularTracks = const [],
    List<BrowseItem> albums = const [],
  }) {
    return Artist(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Unknown Artist',
      imageTag: _primaryImageTag(json),
      popularTracks: popularTracks,
      albums: albums,
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.imageTag,
    required this.tracks,
  });

  final String id;
  final String name;
  final String? imageTag;
  final List<Track> tracks;

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  factory PlaylistDetail.fromJson(
    Map<String, dynamic> json, {
    List<Track> tracks = const [],
  }) {
    return PlaylistDetail(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled Playlist',
      imageTag: _primaryImageTag(json),
      tracks: tracks,
    );
  }
}

/// A playlist that currently contains a given track, plus the Jellyfin playlist
/// entry id required to remove it (`DELETE /Playlists/.../Items`).
class PlaylistMembership {
  const PlaylistMembership({
    required this.playlistId,
    required this.playlistName,
    required this.playlistItemEntryId,
  });

  final String playlistId;
  final String playlistName;
  final String playlistItemEntryId;
}

String? _primaryImageTag(Map<String, dynamic> json) {
  final tags = json['ImageTags'];
  if (tags is Map && tags['Primary'] is String) {
    return tags['Primary'] as String;
  }
  return json['AlbumPrimaryImageTag'] as String?;
}
