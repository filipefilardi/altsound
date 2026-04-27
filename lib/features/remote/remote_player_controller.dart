import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/models/media_item.dart' as jf;
import '../../data/jellyfin/models/remote_session.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';

/// Active remote target. `null` means playback is local.
final activeRemoteSessionIdProvider =
    NotifierProvider<ActiveRemoteSessionId, String?>(
  ActiveRemoteSessionId.new,
);

class ActiveRemoteSessionId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
  void clear() => state = null;
}

/// Polls `/Sessions` every few seconds while a remote target is active so the
/// UI can mirror its now-playing state. Replace with the Jellyfin WebSocket
/// (`/socket?api_key=...`) once we want push updates.
final activeRemoteSessionProvider = StreamProvider<RemoteSession?>((ref) {
  final id = ref.watch(activeRemoteSessionIdProvider);
  if (id == null) return Stream.value(null);
  final repo = ref.watch(remoteSessionsRepositoryProvider);

  final controller = StreamController<RemoteSession?>();
  Timer? timer;

  Future<void> tick() async {
    try {
      final sessions = await repo.list();
      controller.add(
        sessions.where((s) => s.id == id).cast<RemoteSession?>().firstOrNull,
      );
    } catch (e, st) {
      controller.addError(e, st);
    }
  }

  tick();
  timer = Timer.periodic(const Duration(seconds: 3), (_) => tick());
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

final remotePlayerControllerProvider = Provider<RemotePlayerController>((ref) {
  return RemotePlayerController(
    repo: ref.watch(remoteSessionsRepositoryProvider),
    sessionId: () => ref.read(activeRemoteSessionIdProvider),
  );
});

/// Mirrors `PlayerController`'s shape but routes everything to a remote
/// session. Caller is expected to have set [activeRemoteSessionIdProvider]
/// before invoking any method.
class RemotePlayerController {
  RemotePlayerController({required this.repo, required this.sessionId});

  final RemoteSessionsRepository repo;
  final String? Function() sessionId;

  String get _id {
    final id = sessionId();
    if (id == null) {
      throw StateError('No active remote session');
    }
    return id;
  }

  Future<void> playTracks(List<jf.Track> tracks, {int startIndex = 0}) {
    if (tracks.isEmpty) return Future.value();
    return repo.playItems(
      _id,
      tracks.map((t) => t.id).toList(),
      startIndex: startIndex,
    );
  }

  Future<void> playNext(jf.Track track) =>
      repo.queueItems(_id, [track.id], playNext: true);

  Future<void> addToQueue(jf.Track track) =>
      repo.queueItems(_id, [track.id]);

  Future<void> togglePlay() => repo.playPause(_id);
  Future<void> stop() => repo.stop(_id);
  Future<void> next() => repo.next(_id);
  Future<void> previous() => repo.previous(_id);
  Future<void> seek(Duration p) => repo.seek(_id, p);

  Future<void> setVolume(double v) =>
      repo.setVolume(_id, (v.clamp(0.0, 1.0) * 100).round());

  Future<void> setMuted(bool muted) => repo.setMute(_id, muted: muted);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
