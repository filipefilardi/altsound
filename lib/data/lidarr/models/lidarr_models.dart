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
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>();
    final remoteCover = images
        ?.firstWhere(
          (img) => img['coverType'] == 'poster',
          orElse: () => images.first,
        )['remoteUrl'] as String?;

    final stats = json['statistics'] as Map<String, dynamic>?;

    return LidarrArtistResult(
      foreignArtistId: json['foreignArtistId'] as String? ?? '',
      name: json['artistName'] as String? ?? 'Unknown artist',
      overview: json['overview'] as String?,
      imageUrl: remoteCover,
      albumCount: stats?['albumCount'] as int?,
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
