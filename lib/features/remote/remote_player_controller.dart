import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/models/media_item.dart' as jf;
import 'package:altsound/data/jellyfin/models/remote_session.dart';
import 'package:altsound/data/jellyfin/remote_sessions_repository.dart';
import 'package:altsound/features/remote/remote_session_socket.dart';

/// Active remote target. `null` means playback is local.
final activeRemoteSessionIdProvider =
    NotifierProvider<ActiveRemoteSessionId, String?>(ActiveRemoteSessionId.new);

class ActiveRemoteSessionId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
  void clear() => state = null;
}

/// Mirrors the active remote session's now-playing state.
///
/// Jellyfin's web client uses the session WebSocket (`SessionsStart` /
/// `Sessions`) for this, with REST polling only when the message channel is
/// unavailable. We follow the same shape here.
final activeRemoteSessionProvider = StreamProvider.autoDispose<RemoteSession?>((
  ref,
) {
  final id = ref.watch(activeRemoteSessionIdProvider);
  if (id == null) return Stream.value(null);
  final repo = ref.watch(remoteSessionsRepositoryProvider);
  final socket = ref.watch(remoteSessionSocketProvider);

  final controller = StreamController<RemoteSession?>();
  StreamSubscription<RemoteSessionSocketEvent>? socketSub;
  Timer? timer;
  var disposed = false;
  var socketConnected = false;

  RemoteSession? select(List<RemoteSession> sessions) {
    return sessions.where((s) => s.id == id).cast<RemoteSession?>().firstOrNull;
  }

  Future<void> poll() async {
    if (socketConnected) return;
    try {
      final sessions = await repo.list();
      if (disposed) return;
      controller.add(select(sessions));
    } catch (e, st) {
      if (disposed) return;
      controller.addError(e, st);
    }
  }

  socketSub = socket.events.listen((event) {
    switch (event) {
      case RemoteSessionsEvent(:final sessions):
        if (!disposed) controller.add(select(sessions));
      case RemoteSessionSocketStatusEvent(:final connected):
        socketConnected = connected;
        if (!connected) unawaited(poll());
    }
  });

  socket.subscribeSessions().catchError((Object e, StackTrace st) {
    if (!disposed) controller.addError(e, st);
    unawaited(poll());
  });
  unawaited(poll());
  timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    socket.unsubscribeSessions();
    socketSub?.cancel();
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

  Future<void> addToQueue(jf.Track track) => repo.queueItems(_id, [track.id]);

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
