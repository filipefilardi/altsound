import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_player_handler.dart';
import 'player_providers.dart';

final playbackSessionPersistenceProvider = Provider<PlaybackSessionPersistence>(
  (ref) {
    return PlaybackSessionPersistence(
      handler: ref.read(audioHandlerProvider),
      store: const PlaybackSessionStore(),
    );
  },
);

class PlaybackSessionPersistence {
  PlaybackSessionPersistence({required this.handler, required this.store});

  final JellymusicAudioHandler handler;
  final PlaybackSessionStore store;

  bool _attached = false;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _debounce;
  Timer? _positionTicker;

  void attach() {
    if (_attached) return;
    _attached = true;

    _subs.add(handler.queue.listen((_) => _schedulePersist()));
    _subs.add(handler.playbackState.listen((_) => _schedulePersist()));
    _subs.add(handler.mediaItem.listen((_) => _schedulePersist()));

    _positionTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (handler.player.playing) {
        _schedulePersist();
      }
    });
  }

  Future<void> persistNow() async {
    final snapshot = handler.buildPersistenceSnapshot();
    if (snapshot == null) {
      await store.clear();
      return;
    }
    await store.write(snapshot);
  }

  Future<void> close() async {
    _debounce?.cancel();
    _positionTicker?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(persistNow());
    });
  }
}

class PlaybackSessionStore {
  const PlaybackSessionStore();

  static const _filename = 'playback_session_v1.json';

  Future<Map<String, dynamic>?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> payload) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort.
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/playback/$_filename');
  }
}

Future<Map<String, dynamic>?> readPlaybackSessionSnapshot() async {
  return const PlaybackSessionStore().read();
}
