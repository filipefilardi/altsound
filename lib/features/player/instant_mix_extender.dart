import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/features/player/playback_handler.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Auto-extends the queue when an Instant Mix nears its end so playback
/// continues forever, seeded by whatever track is currently playing.
///
/// Triggers when the playing item's `contextId` starts with `instant-mix:`
/// and the current index is within [_extendTriggerLookahead] of the queue end.
/// Fetches a fresh mix from the *currently playing track* (not the original
/// seed) so suggestions follow the listener's drift.
class InstantMixExtender {
  InstantMixExtender({
    required this.repo,
    required this.handler,
    required this.controller,
  });

  final JellyfinRepository repo;
  final PlaybackHandler handler;
  final PlayerController controller;

  static const _instantMixContextPrefix = 'instant-mix:';
  static const _extendTriggerLookahead = 2;
  static const _extendBatchSize = 40;

  StreamSubscription<MediaItem?>? _sub;
  bool _fetching = false;
  String? _lastSeedId;

  void attach() {
    _sub ??= handler.mediaItem.stream.listen((_) => _maybeExtend());
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _maybeExtend() async {
    if (_fetching) return;

    final current = handler.mediaItem.value;
    final contextId = current?.extras?['contextId'] as String?;
    if (contextId == null || !contextId.startsWith(_instantMixContextPrefix)) {
      return;
    }

    final queue = handler.queue.value;
    final index = handler.player.currentIndex;
    if (index == null || queue.isEmpty) return;
    if (index < queue.length - 1 - _extendTriggerLookahead) return;

    final seedId = current?.extras?['jellyfinId'] as String?;
    if (seedId == null || seedId == _lastSeedId) return;

    _fetching = true;
    _lastSeedId = seedId;
    try {
      final tracks = await repo.instantMix(seedId, limit: _extendBatchSize);
      final existingIds = queue
          .map((m) => m.extras?['jellyfinId'] as String?)
          .whereType<String>()
          .toSet();
      final fresh = tracks.where((t) => !existingIds.contains(t.id)).toList();
      if (fresh.isEmpty) return;
      await controller.appendTracks(fresh, contextId: contextId);
    } catch (e) {
      debugPrint('[InstantMixExtender] failed to extend: $e');
    } finally {
      _fetching = false;
    }
  }
}

final instantMixExtenderProvider = Provider<InstantMixExtender>((ref) {
  final extender = InstantMixExtender(
    repo: ref.watch(jellyfinRepositoryProvider),
    handler: ref.watch(audioHandlerProvider),
    controller: ref.watch(playerControllerProvider),
  );
  ref.onDispose(extender.dispose);
  return extender;
});
