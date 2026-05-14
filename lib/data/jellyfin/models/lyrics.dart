class LyricLine {
  const LyricLine({required this.text, this.start});

  final String text;
  final Duration? start;
}

class Lyrics {
  const Lyrics({required this.lines, required this.isSynced});

  final List<LyricLine> lines;
  final bool isSynced;

  bool get isEmpty => lines.isEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> json) {
    final raw = (json['Lyrics'] as List?) ?? const [];
    final lines = raw
        .cast<Map<String, dynamic>>()
        .map((l) {
          final ticks = l['Start'] as num?;
          return LyricLine(
            text: (l['Text'] as String?) ?? '',
            // Jellyfin returns .NET ticks (100 ns each). Microseconds = ticks / 10.
            start: ticks == null ? null : Duration(microseconds: ticks ~/ 10),
          );
        })
        .toList(growable: false);
    final meta = (json['Metadata'] as Map<String, dynamic>?) ?? const {};
    final isSynced =
        (meta['IsSynced'] as bool?) ?? lines.any((l) => l.start != null);
    return Lyrics(lines: lines, isSynced: isSynced);
  }
}
