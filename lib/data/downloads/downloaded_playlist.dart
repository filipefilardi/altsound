class DownloadedPlaylist {
  const DownloadedPlaylist({
    required this.id,
    required this.name,
    required this.imageTag,
    required this.trackIds,
  });

  final String id;
  final String name;
  final String? imageTag;
  final List<String> trackIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageTag': imageTag,
        'trackIds': trackIds,
      };

  factory DownloadedPlaylist.fromJson(Map<String, dynamic> json) =>
      DownloadedPlaylist(
        id: json['id'] as String,
        name: json['name'] as String,
        imageTag: json['imageTag'] as String?,
        trackIds: (json['trackIds'] as List).cast<String>(),
      );
}
