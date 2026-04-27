import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/remote_session.dart';

final remoteSessionsRepositoryProvider =
    Provider<RemoteSessionsRepository>((ref) {
  return RemoteSessionsRepository(ref.watch(jellyfinApiProvider));
});

/// Lists controllable Jellyfin sessions and sends remote-control commands.
class RemoteSessionsRepository {
  RemoteSessionsRepository(this._api);

  final JellyfinApi _api;

  /// Other sessions on the same server that accept remote control.
  /// The current device is filtered out so users don't see themselves.
  Future<List<RemoteSession>> list() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/Sessions',
      queryParameters: {'ControllableByUserId': _api.session?.userId},
    );
    final raw = (res.data ?? const []).cast<Map<String, dynamic>>();
    final ownDeviceId = _api.deviceId;
    return raw
        .map(RemoteSession.fromJson)
        .where((s) => s.supportsRemoteControl && s.deviceId != ownDeviceId)
        .toList();
  }

  Future<void> playItems(
    String sessionId,
    List<String> itemIds, {
    int startIndex = 0,
  }) async {
    await _api.dio.post<void>(
      '/Sessions/$sessionId/Playing',
      queryParameters: {
        'playCommand': 'PlayNow',
        'itemIds': itemIds.join(','),
        'startIndex': startIndex,
      },
    );
  }

  Future<void> queueItems(
    String sessionId,
    List<String> itemIds, {
    bool playNext = false,
  }) async {
    await _api.dio.post<void>(
      '/Sessions/$sessionId/Playing',
      queryParameters: {
        'playCommand': playNext ? 'PlayNext' : 'PlayLast',
        'itemIds': itemIds.join(','),
      },
    );
  }

  Future<void> playPause(String sessionId) =>
      _command(sessionId, 'PlayPause');
  Future<void> stop(String sessionId) => _command(sessionId, 'Stop');
  Future<void> next(String sessionId) => _command(sessionId, 'NextTrack');
  Future<void> previous(String sessionId) =>
      _command(sessionId, 'PreviousTrack');

  Future<void> seek(String sessionId, Duration position) async {
    await _api.dio.post<void>(
      '/Sessions/$sessionId/Playing/Seek',
      queryParameters: {'seekPositionTicks': position.inMicroseconds * 10},
    );
  }

  /// [volume] is 0–100, matching Jellyfin's `VolumeLevel`.
  Future<void> setVolume(String sessionId, int volume) async {
    await _generalCommand(sessionId, 'SetVolume', {
      'Volume': volume.clamp(0, 100).toString(),
    });
  }

  Future<void> setMute(String sessionId, {required bool muted}) =>
      _generalCommand(sessionId, muted ? 'Mute' : 'Unmute');

  Future<void> _command(String sessionId, String command) async {
    await _api.dio.post<void>('/Sessions/$sessionId/Playing/$command');
  }

  Future<void> _generalCommand(
    String sessionId,
    String name, [
    Map<String, String>? arguments,
  ]) async {
    await _api.dio.post<void>(
      '/Sessions/$sessionId/Command',
      data: {
        'Name': name,
        if (arguments != null) 'Arguments': arguments,
      },
    );
  }
}
