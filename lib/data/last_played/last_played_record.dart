class LastPlayedRecord {
  const LastPlayedRecord({
    required this.trackId,
    required this.trackName,
    required this.albumId,
    required this.albumName,
    required this.artistName,
    required this.imageUrl,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  /// Jellyfin track id of the last item being played.
  final String trackId;
  final String trackName;

  /// Jellyfin album id, if the track belongs to an album. Used for navigation.
  final String? albumId;
  final String? albumName;
  final String artistName;

  /// Resolved at write-time. May be a remote https URL or a local `file://`
  /// path when the track artwork was downloaded.
  final String? imageUrl;

  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);
  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  LastPlayedRecord copyWith({
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
  }) =>
      LastPlayedRecord(
        trackId: trackId,
        trackName: trackName,
        albumId: albumId,
        albumName: albumName,
        artistName: artistName,
        imageUrl: imageUrl,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackName': trackName,
        'albumId': albumId,
        'albumName': albumName,
        'artistName': artistName,
        'imageUrl': imageUrl,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LastPlayedRecord.fromJson(Map<String, dynamic> json) =>
      LastPlayedRecord(
        trackId: json['trackId'] as String,
        trackName: json['trackName'] as String,
        albumId: json['albumId'] as String?,
        albumName: json['albumName'] as String?,
        artistName: json['artistName'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        positionMs: json['positionMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
