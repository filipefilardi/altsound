class LastInstantMixRecord {
  const LastInstantMixRecord({
    required this.seedItemId,
    required this.seedKind,
    required this.seedTitle,
    required this.artworkUrl,
    required this.updatedAt,
  });

  /// Jellyfin id of the album / artist / playlist / track the mix was seeded from.
  final String seedItemId;

  /// Matches `InstantMixSeedKind.queryValue`. Stored as a string to avoid a
  /// reverse dependency from `data/` into `features/`.
  final String seedKind;

  final String? seedTitle;

  /// Resolved at write-time; may be remote https or local `file://`.
  final String? artworkUrl;

  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'seedItemId': seedItemId,
        'seedKind': seedKind,
        'seedTitle': seedTitle,
        'artworkUrl': artworkUrl,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LastInstantMixRecord.fromJson(Map<String, dynamic> json) =>
      LastInstantMixRecord(
        seedItemId: json['seedItemId'] as String,
        seedKind: json['seedKind'] as String? ?? 'track',
        seedTitle: json['seedTitle'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
