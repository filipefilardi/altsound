class LidarrArtistResult {
  const LidarrArtistResult({
    required this.foreignArtistId,
    required this.name,
    required this.overview,
    required this.imageUrl,
    required this.albumCount,
    required this.alreadyMonitored,
    required this.id,
    required this.raw,
  });

  final String foreignArtistId;
  final String name;
  final String? overview;
  final String? imageUrl;
  final int? albumCount;
  final bool alreadyMonitored;
  final int? id;
  final Map<String, dynamic> raw;

  factory LidarrArtistResult.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'] as List?;
    final images = rawImages
            ?.whereType<Map>()
            .map((img) => img.map((k, v) => MapEntry('$k', v)))
            .toList() ??
        const <Map<String, dynamic>>[];
    final coverImage = images.cast<Map<String, dynamic>?>().firstWhere(
          (img) => img?['coverType'] == 'poster',
          orElse: () => images.isEmpty ? null : images.first,
        );
    final remoteCover = coverImage?['remoteUrl'] as String?;

    final rawStats = json['statistics'];
    final stats = rawStats is Map
        ? rawStats.map((k, v) => MapEntry('$k', v))
        : <String, dynamic>{};

    return LidarrArtistResult(
      foreignArtistId: json['foreignArtistId'] as String? ?? '',
      name: json['artistName'] as String? ??
          json['artist'] as String? ??
          json['name'] as String? ??
          'Unknown artist',
      overview: json['overview'] as String?,
      imageUrl: remoteCover,
      albumCount: (stats['albumCount'] as num?)?.toInt(),
      alreadyMonitored: (json['id'] as int?) != null,
      id: json['id'] as int?,
      raw: json,
    );
  }
}

class LidarrQualityProfile {
  const LidarrQualityProfile({required this.id, required this.name});
  final int id;
  final String name;

  factory LidarrQualityProfile.fromJson(Map<String, dynamic> json) =>
      LidarrQualityProfile(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Profile',
      );
}

class LidarrMetadataProfile {
  const LidarrMetadataProfile({required this.id, required this.name});
  final int id;
  final String name;

  factory LidarrMetadataProfile.fromJson(Map<String, dynamic> json) =>
      LidarrMetadataProfile(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Profile',
      );
}

class LidarrRootFolder {
  const LidarrRootFolder({required this.id, required this.path});
  final int id;
  final String path;

  factory LidarrRootFolder.fromJson(Map<String, dynamic> json) =>
      LidarrRootFolder(
        id: json['id'] as int,
        path: json['path'] as String? ?? '/',
      );
}

class LidarrDefaults {
  const LidarrDefaults({
    required this.qualityProfileId,
    required this.metadataProfileId,
    required this.rootFolderPath,
  });

  final int qualityProfileId;
  final int metadataProfileId;
  final String rootFolderPath;
}

class LidarrAlbumResult {
  const LidarrAlbumResult({
    required this.title,
    required this.artistName,
    required this.releaseDate,
    required this.albumType,
  });

  final String title;
  final String artistName;
  final String? releaseDate;
  final String? albumType;

  factory LidarrAlbumResult.fromJson(Map<String, dynamic> json) {
    return LidarrAlbumResult(
      title: json['title'] as String? ?? 'Untitled album',
      artistName: json['artistName'] as String? ?? 'Unknown artist',
      releaseDate: json['releaseDate'] as String?,
      albumType: json['albumType'] as String?,
    );
  }
}
