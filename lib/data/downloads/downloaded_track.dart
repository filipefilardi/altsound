import '../jellyfin/models/media_item.dart';

class DownloadedTrack {
  const DownloadedTrack({
    required this.id,
    required this.name,
    required this.albumId,
    required this.albumName,
    required this.artistName,
    required this.durationMs,
    required this.trackNumber,
    required this.discNumber,
    required this.imageItemId,
    required this.imageTag,
    required this.filePath,
    required this.fileSize,
    required this.downloadedAt,
  });

  final String id;
  final String name;
  final String? albumId;
  final String? albumName;
  final String artistName;
  final int durationMs;
  final int? trackNumber;
  final int? discNumber;
  final String imageItemId;
  final String? imageTag;
  final String filePath;
  final int fileSize;
  final DateTime downloadedAt;

  Duration get duration => Duration(milliseconds: durationMs);

  Track toTrack() => Track(
        id: id,
        name: name,
        albumId: albumId,
        albumName: albumName,
        artistName: artistName,
        artistId: null,
        duration: duration,
        trackNumber: trackNumber,
        discNumber: discNumber,
        imageTag: imageTag,
        albumImageItemId: imageItemId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'albumId': albumId,
        'albumName': albumName,
        'artistName': artistName,
        'durationMs': durationMs,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'imageItemId': imageItemId,
        'imageTag': imageTag,
        'filePath': filePath,
        'fileSize': fileSize,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) {
    return DownloadedTrack(
      id: json['id'] as String,
      name: json['name'] as String,
      albumId: json['albumId'] as String?,
      albumName: json['albumName'] as String?,
      artistName: json['artistName'] as String,
      durationMs: json['durationMs'] as int,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
      imageItemId: json['imageItemId'] as String,
      imageTag: json['imageTag'] as String?,
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
    );
  }
}
