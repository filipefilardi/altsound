import 'package:flutter_test/flutter_test.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';

void main() {
  final sample = DownloadedTrack(
    id: 't1',
    name: 'Around the World',
    albumId: 'al1',
    albumName: 'Homework',
    artistName: 'Daft Punk',
    durationMs: 423000,
    trackNumber: 7,
    discNumber: 1,
    imageItemId: 'al1',
    imageTag: 'img-tag',
    filePath: '/tmp/t1.mp3',
    fileSize: 5_242_880,
    artworkPath: '/tmp/t1.jpg',
    downloadedAt: DateTime.utc(2024, 6, 1, 12, 30),
  );

  test('JSON round-trip preserves every field', () {
    final decoded = DownloadedTrack.fromJson(sample.toJson());
    expect(decoded.id, sample.id);
    expect(decoded.name, sample.name);
    expect(decoded.albumId, sample.albumId);
    expect(decoded.albumName, sample.albumName);
    expect(decoded.artistName, sample.artistName);
    expect(decoded.durationMs, sample.durationMs);
    expect(decoded.trackNumber, sample.trackNumber);
    expect(decoded.discNumber, sample.discNumber);
    expect(decoded.imageItemId, sample.imageItemId);
    expect(decoded.imageTag, sample.imageTag);
    expect(decoded.filePath, sample.filePath);
    expect(decoded.fileSize, sample.fileSize);
    expect(decoded.artworkPath, sample.artworkPath);
    expect(decoded.downloadedAt, sample.downloadedAt);
  });

  test(
    'toTrack copies metadata and drops fields without local equivalents',
    () {
      final track = sample.toTrack();
      expect(track.id, sample.id);
      expect(track.name, sample.name);
      expect(track.albumId, sample.albumId);
      expect(track.duration, Duration(milliseconds: sample.durationMs));
      expect(track.albumImageItemId, sample.imageItemId);
      // No artistId / playlistItemId / dateAdded stored for offline tracks.
      expect(track.artistId, isNull);
      expect(track.playlistItemId, isNull);
      expect(track.dateAdded, isNull);
    },
  );
}
