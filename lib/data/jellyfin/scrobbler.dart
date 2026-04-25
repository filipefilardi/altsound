import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';

const _ticksPerMs = 10000;

final scrobblerProvider = Provider<Scrobbler>((ref) {
  final scrobbler = Scrobbler(ref.watch(jellyfinApiProvider));
  ref.onDispose(scrobbler.dispose);
  return scrobbler;
});

class Scrobbler {
  Scrobbler(this._api);

  final JellyfinApi _api;
  String? _currentId;
  Timer? _timer;
  bool _disposed = false;

  /// Wire the scrobbler to player streams. Returns nothing — fire-and-forget.
  void attach({
    required Stream<MediaItem?> mediaItemStream,
    required Stream<PlaybackState> playbackStateStream,
    required Duration Function() position,
    required bool Function() isOffline,
  }) {
    mediaItemStream.listen((item) async {
      if (_disposed) return;
      final newId = item?.extras?['jellyfinId'] as String?;
      if (newId == _currentId) return;
      // Stop previous
      if (_currentId != null) {
        await _safe(() => _post(
              '/Sessions/Playing/Stopped',
              {'ItemId': _currentId, 'PositionTicks': 0},
            ));
      }
      _currentId = newId;
      // Start new
      if (newId != null && !isOffline()) {
        await _safe(() => _post('/Sessions/Playing', {
              'ItemId': newId,
              'PositionTicks':
                  position().inMilliseconds * _ticksPerMs,
              'IsPaused': false,
              'PlayMethod': 'DirectStream',
            }));
      }
    });

    playbackStateStream.listen((state) async {
      if (_disposed) return;
      _timer?.cancel();
      if (state.playing && _currentId != null && !isOffline()) {
        _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
          await _safe(() => _post('/Sessions/Playing/Progress', {
                'ItemId': _currentId,
                'PositionTicks': position().inMilliseconds * _ticksPerMs,
                'IsPaused': false,
                'EventName': 'TimeUpdate',
              }));
        });
      } else if (_currentId != null && !isOffline()) {
        // Pause notice
        await _safe(() => _post('/Sessions/Playing/Progress', {
              'ItemId': _currentId,
              'PositionTicks': position().inMilliseconds * _ticksPerMs,
              'IsPaused': !state.playing,
              'EventName': 'Pause',
            }));
      }
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    if (_api.session == null) return;
    await _api.dio.post<dynamic>(path, data: body);
  }

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Scrobbling is best-effort; never let it crash playback.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
