import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

void main() {
  group('BrowseItem.fromJson', () {
    test('maps Jellyfin Type strings to MediaKind and picks Primary tag', () {
      final album = BrowseItem.fromJson({
        'Id': 'a1',
        'Name': 'Random Access Memories',
        'Type': 'MusicAlbum',
        'AlbumArtist': 'Daft Punk',
        'ImageTags': {'Primary': 'tag-primary'},
        'RunTimeTicks': 36000000000, // 1 hour
      });
      expect(album.kind, MediaKind.album);
      expect(album.subtitle, 'Daft Punk');
      expect(album.imageTag, 'tag-primary');
      expect(album.runTime, const Duration(hours: 1));
    });

    test('joins track artists into a comma list', () {
      final track = BrowseItem.fromJson({
        'Id': 't1',
        'Name': 'Get Lucky',
        'Type': 'Audio',
        'Artists': ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers'],
      });
      expect(track.kind, MediaKind.track);
      expect(track.subtitle, 'Daft Punk, Pharrell Williams, Nile Rodgers');
    });

    test('uses fixed subtitle for artists and playlists', () {
      final artist = BrowseItem.fromJson({
        'Id': 'ar1',
        'Name': 'Daft Punk',
        'Type': 'MusicArtist',
      });
      final playlist = BrowseItem.fromJson({
        'Id': 'pl1',
        'Name': 'Discover Weekly',
        'Type': 'Playlist',
      });
      expect(artist.subtitle, 'Artist');
      expect(playlist.subtitle, 'Playlist');
    });

    test('falls back to AlbumPrimaryImageTag when ImageTags is missing', () {
      final item = BrowseItem.fromJson({
        'Id': 'a1',
        'Name': 'Untitled',
        'Type': 'MusicAlbum',
        'AlbumPrimaryImageTag': 'fallback-tag',
      });
      expect(item.imageTag, 'fallback-tag');
    });

    test('defaults missing name to "Untitled" and unknown type to album', () {
      final item = BrowseItem.fromJson({'Id': 'x', 'Type': 'Unknown'});
      expect(item.name, 'Untitled');
      expect(item.kind, MediaKind.album);
    });
  });

  group('BrowseItem search JSON round-trip', () {
    test('preserves every field through encode + decode', () {
      const original = BrowseItem(
        id: 'id-1',
        name: 'Album',
        subtitle: 'Artist',
        imageTag: 'tag',
        kind: MediaKind.album,
        runTime: Duration(minutes: 42, seconds: 13),
        childCount: 11,
      );
      final decoded = BrowseItem.fromSearchJson(original.toSearchJson());
      expect(decoded.id, original.id);
      expect(decoded.name, original.name);
      expect(decoded.subtitle, original.subtitle);
      expect(decoded.imageTag, original.imageTag);
      expect(decoded.kind, original.kind);
      expect(decoded.runTime, original.runTime);
      expect(decoded.childCount, original.childCount);
    });
  });

  group('Track.fromJson', () {
    test('joins Artists, parses ticks, and reads DateCreated', () {
      final track = Track.fromJson({
        'Id': 't1',
        'Name': 'Around the World',
        'AlbumId': 'al1',
        'Album': 'Homework',
        'Artists': ['Daft Punk', 'Guest'],
        'ArtistItems': [
          {'Id': 'ar1', 'Name': 'Daft Punk'},
        ],
        'RunTimeTicks': 12000000, // 1.2s
        'IndexNumber': 7,
        'ParentIndexNumber': 1,
        'PlaylistItemId': 'p-1',
        'DateCreated': '2024-01-02T03:04:05Z',
      });
      expect(track.name, 'Around the World');
      expect(track.artistName, 'Daft Punk, Guest');
      expect(track.artistId, 'ar1');
      expect(track.duration, const Duration(milliseconds: 1200));
      expect(track.trackNumber, 7);
      expect(track.discNumber, 1);
      expect(track.playlistItemId, 'p-1');
      expect(track.dateAdded, DateTime.utc(2024, 1, 2, 3, 4, 5));
    });

    test('falls back to AlbumArtist when Artists missing', () {
      final track = Track.fromJson({
        'Id': 't1',
        'Name': 'Solo',
        'AlbumArtist': 'Solo Artist',
      });
      expect(track.artistName, 'Solo Artist');
      expect(track.duration, Duration.zero);
    });

    test('uses "Unknown Artist" when no artist info at all', () {
      final track = Track.fromJson({'Id': 't1', 'Name': 'Mystery'});
      expect(track.artistName, 'Unknown Artist');
    });

    test('imageItemId prefers album image, falls back to track id', () {
      final withAlbum = Track.fromJson({
        'Id': 't1',
        'Name': 'X',
        'AlbumId': 'al1',
      });
      final withoutAlbum = Track.fromJson({'Id': 't2', 'Name': 'X'});
      expect(withAlbum.imageItemId, 'al1');
      expect(withoutAlbum.imageItemId, 't2');
    });
  });

  group('Album', () {
    test('totalDuration sums every track', () {
      final album = Album(
        id: 'a',
        name: 'A',
        artistName: 'X',
        artistId: null,
        year: null,
        imageTag: null,
        tracks: [
          _track(duration: const Duration(minutes: 3)),
          _track(duration: const Duration(minutes: 4, seconds: 30)),
        ],
      );
      expect(album.totalDuration, const Duration(minutes: 7, seconds: 30));
    });

    test('reads first AlbumArtists.Id and falls back to defaults', () {
      final album = Album.fromJson({
        'Id': 'a1',
        'AlbumArtists': [
          {'Id': 'ar1'},
        ],
      });
      expect(album.id, 'a1');
      expect(album.name, 'Untitled');
      expect(album.artistName, 'Unknown Artist');
      expect(album.artistId, 'ar1');
    });
  });
}

Track _track({required Duration duration}) => Track(
  id: 't',
  name: 'T',
  albumId: null,
  albumName: null,
  artistName: 'X',
  artistId: null,
  duration: duration,
  trackNumber: null,
  discNumber: null,
  imageTag: null,
  albumImageItemId: null,
  playlistItemId: null,
  dateAdded: null,
);
