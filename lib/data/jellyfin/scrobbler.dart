import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:altsound/data/jellyfin/auth_repository.dart';
import 'package:altsound/data/jellyfin/jellyfin_api.dart';

const _ticksPerMs = 10000;
const _progressInterval = Duration(seconds: 10);

final scrobblerProvider = Provider<Scrobbler>((ref) {
  final scrobbler = Scrobbler(ref.watch(jellyfinApiProvider));
  ref.onDispose(scrobbler.dispose);
  return scrobbler;
});

/// Reports playback to Jellyfin so the server (and the Playback Reporting
/// plugin) can record what's been listened to.
///
/// Each track gets a fresh `PlaySessionId` so the plugin can correlate the
/// Playing → Stopped pair. The last seen position is tracked locally so the
/// Stopped event can report the actual duration played, even though
/// `audio_service` resets the position to 0 of the *next* track before our
/// `mediaItem` listener sees the change.
class Scrobbler {
  Scrobbler(this._api);

  final JellyfinApi _api;
  final _uuid = const Uuid();

  String? _currentItemId;
  String? _currentSessionId;
  int _lastPositionTicks = 0;
  bool? _wasPlaying;

  Timer? _progressTimer;
  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<PlaybackState>? _stateSub;
  Duration Function()? _position;
  bool Function()? _isOffline;
  bool _disposed = false;

  /// Wire the scrobbler to player streams. Returns nothing — fire-and-forget.
  void attach({
    required Stream<MediaItem?> mediaItemStream,
    required Stream<PlaybackState> playbackStateStream,
    required Duration Function() position,
    required bool Function() isOffline,
  }) {
    _position = position;
    _isOffline = isOffline;

    _itemSub = mediaItemStream.listen((item) {
      if (_disposed) return;
      final newId = item?.extras?['jellyfinId'] as String?;
      if (newId == _currentItemId) return;
      _onItemChanged(newId);
    });

    // Only react to actual play/pause transitions — `playbackState` emits on
    // every `playbackEvent` (buffered position changes, etc.), and reacting
    // to every emission would cancel/restart the progress timer continuously
    // and the 10s tick would never fire.
    _stateSub = playbackStateStream.listen((state) {
      if (_disposed) return;
      if (state.playing == _wasPlaying) return;
      _wasPlaying = state.playing;
      _onPlayingChanged(state.playing);
    });
  }

  void _onItemChanged(String? newId) {
    _progressTimer?.cancel();
    _progressTimer = null;

    if (_currentItemId != null && _currentSessionId != null) {
      _safe(() => _post('/Sessions/Playing/Stopped', {
            'ItemId': _currentItemId,
            'MediaSourceId': _currentItemId,
            'PlaySessionId': _currentSessionId,
            'PositionTicks': _lastPositionTicks,
          }));
    }

    _currentItemId = newId;
    _lastPositionTicks = 0;
    if (newId == null) {
      _currentSessionId = null;
      return;
    }

    _currentSessionId = _uuid.v4();
    if (_isOnline) {
      _safe(() => _post('/Sessions/Playing', {
            'ItemId': newId,
            'MediaSourceId': newId,
            'PlaySessionId': _currentSessionId,
            'PositionTicks': _capturePosition(),
            'IsPaused': false,
            'PlayMethod': 'DirectStream',
          }));
    }

    if (_wasPlaying == true) _startProgressTimer();
  }

  void _onPlayingChanged(bool playing) {
    _progressTimer?.cancel();
    _progressTimer = null;

    if (_currentItemId == null || _currentSessionId == null || !_isOnline) {
      return;
    }

    final eventName = playing ? 'Unpause' : 'Pause';
    _safe(() => _post('/Sessions/Playing/Progress', {
          'ItemId': _currentItemId,
          'MediaSourceId': _currentItemId,
          'PlaySessionId': _currentSessionId,
          'PositionTicks': _capturePosition(),
          'IsPaused': !playing,
          'EventName': eventName,
        }));

    if (playing) _startProgressTimer();
  }

  void _startProgressTimer() {
    _progressTimer = Timer.periodic(_progressInterval, (_) {
      if (_disposed ||
          _currentItemId == null ||
          _currentSessionId == null ||
          !_isOnline) {
        return;
      }
      _safe(() => _post('/Sessions/Playing/Progress', {
            'ItemId': _currentItemId,
            'MediaSourceId': _currentItemId,
            'PlaySessionId': _currentSessionId,
            'PositionTicks': _capturePosition(),
            'IsPaused': false,
            'EventName': 'TimeUpdate',
          }));
    });
  }

  /// Reads the current position, persists it as the last-known ticks for the
  /// active item, and returns it. Used as the Stopped position when the track
  /// changes (by which time `audio_service` has already reset position to 0
  /// for the next track).
  int _capturePosition() {
    final ticks = (_position?.call().inMilliseconds ?? 0) * _ticksPerMs;
    if (ticks > 0) _lastPositionTicks = ticks;
    return _lastPositionTicks;
  }

  bool get _isOnline => !(_isOffline?.call() ?? false);

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
    _progressTimer?.cancel();
    _itemSub?.cancel();
    _stateSub?.cancel();
    if (_currentItemId != null && _currentSessionId != null) {
      _safe(() => _post('/Sessions/Playing/Stopped', {
            'ItemId': _currentItemId,
            'MediaSourceId': _currentItemId,
            'PlaySessionId': _currentSessionId,
            'PositionTicks': _lastPositionTicks,
          }));
    }
  }
}
