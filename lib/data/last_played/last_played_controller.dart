import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/player/player_providers.dart';
import 'last_played_record.dart';

final lastPlayedProvider =
    NotifierProvider<LastPlayedController, LastPlayedRecord?>(
        LastPlayedController.new);

/// Tracks the last played track + position locally so we can render a
/// "pick up where you left off" card without depending on Jellyfin.
///
/// Listens to the audio handler streams and persists a small JSON record to
/// `documents/last_played.json`. Periodically flushes position updates while
/// playback is active.
class LastPlayedController extends Notifier<LastPlayedRecord?> {
  static const _persistInterval = Duration(seconds: 5);

  File? _file;
  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<PlaybackState>? _stateSub;
  Timer? _ticker;
  bool _dirty = false;

  @override
  LastPlayedRecord? build() {
    if (kIsWeb) return null;
    _bootstrap();
    _attachStreams();
    ref.onDispose(_disposeAll);
    return null;
  }

  void _disposeAll() {
    _itemSub?.cancel();
    _stateSub?.cancel();
    _ticker?.cancel();
  }

  Future<void> _bootstrap() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/last_played.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        if (raw.isNotEmpty) {
          state = LastPlayedRecord.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Corrupt or unreadable record — ignore and start fresh.
    }
  }

  void _attachStreams() {
    final handler = ref.read(audioHandlerProvider);
    _itemSub = handler.mediaItem.stream.listen((item) {
      if (item == null) return;
      _capture(item);
    });
    _stateSub = handler.playbackState.stream.listen((s) {
      _ticker?.cancel();
      if (s.playing) {
        _ticker = Timer.periodic(_persistInterval, (_) => _tick());
      } else {
        // Pause / stop — capture final position and flush immediately.
        _tick(force: true);
      }
    });
  }

  void _capture(MediaItem item) {
    final handler = ref.read(audioHandlerProvider);
    final pos = handler.player.position;
    final dur = item.duration ?? Duration.zero;

    state = LastPlayedRecord(
      trackId: item.id,
      trackName: item.title,
      albumId: item.extras?['albumId'] as String?,
      albumName: item.album,
      artistName: item.artist ?? '',
      imageUrl: item.artUri?.toString(),
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      updatedAt: DateTime.now(),
    );
    _dirty = true;
    unawaited(_flush());
  }

  void _tick({bool force = false}) {
    final current = state;
    if (current == null) return;
    final handler = ref.read(audioHandlerProvider);
    final pos = handler.player.position;
    if (!force && pos.inMilliseconds == current.positionMs) return;
    state = current.copyWith(
      positionMs: pos.inMilliseconds,
      updatedAt: DateTime.now(),
    );
    _dirty = true;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    final file = _file;
    final value = state;
    if (file == null || value == null) return;
    _dirty = false;
    try {
      await file.writeAsString(jsonEncode(value.toJson()));
    } catch (_) {
      // Best-effort persistence — never crash playback over this.
      _dirty = true;
    }
  }

  /// Wipe the local record. Call on logout so the next user doesn't see the
  /// previous user's last-played item.
  Future<void> clear() async {
    state = null;
    _dirty = false;
    final file = _file;
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
