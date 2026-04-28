import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage.dart';

const _bitrateKey = 'playback_streaming_bitrate_v1';
const _gaplessKey = 'playback_gapless_v1';

/// Streaming bitrate options exposed in settings.
///
/// `original` requests the source file without transcoding (sent to Jellyfin
/// by omitting the `MaxStreamingBitrate` parameter).
enum StreamingQuality {
  low(96000, 'Low', '96 kbps'),
  normal(192000, 'Normal', '192 kbps'),
  high(320000, 'High', '320 kbps'),
  original(0, 'Original', 'No transcoding');

  const StreamingQuality(this.bitrate, this.label, this.subtitle);

  final int bitrate;
  final String label;
  final String subtitle;

  static StreamingQuality fromStored(String? raw) {
    if (raw == null) return StreamingQuality.high;
    return StreamingQuality.values.firstWhere(
      (q) => q.name == raw,
      orElse: () => StreamingQuality.high,
    );
  }
}

class PlaybackPreferences {
  const PlaybackPreferences({
    required this.streamingQuality,
    required this.gaplessPlayback,
  });

  final StreamingQuality streamingQuality;
  final bool gaplessPlayback;

  PlaybackPreferences copyWith({
    StreamingQuality? streamingQuality,
    bool? gaplessPlayback,
  }) {
    return PlaybackPreferences(
      streamingQuality: streamingQuality ?? this.streamingQuality,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
    );
  }
}

final playbackPreferencesProvider =
    NotifierProvider<PlaybackPreferencesController, PlaybackPreferences>(
  PlaybackPreferencesController.new,
);

class PlaybackPreferencesController extends Notifier<PlaybackPreferences> {
  @override
  PlaybackPreferences build() {
    _restore();
    return const PlaybackPreferences(
      streamingQuality: StreamingQuality.high,
      gaplessPlayback: true,
    );
  }

  Future<void> _restore() async {
    final storage = ref.read(secureStorageProvider);
    final bitrateRaw = await storage.read(_bitrateKey);
    final gaplessRaw = await storage.read(_gaplessKey);
    state = PlaybackPreferences(
      streamingQuality: StreamingQuality.fromStored(bitrateRaw),
      gaplessPlayback: gaplessRaw != 'false',
    );
  }

  Future<void> setStreamingQuality(StreamingQuality quality) async {
    state = state.copyWith(streamingQuality: quality);
    await ref.read(secureStorageProvider).write(_bitrateKey, quality.name);
  }

  Future<void> setGaplessPlayback(bool enabled) async {
    state = state.copyWith(gaplessPlayback: enabled);
    await ref
        .read(secureStorageProvider)
        .write(_gaplessKey, enabled.toString());
  }
}
