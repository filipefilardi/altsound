import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart' as jf;
import '../../data/jellyfin/models/syncplay.dart';
import '../../data/jellyfin/syncplay_repository.dart';
import '../player/audio_player_handler.dart';
import '../player/media_item_mapper.dart';
import '../player/player_providers.dart';
import 'syncplay_socket.dart';

final syncPlayControllerProvider =
    NotifierProvider<SyncPlayController, SyncPlayState>(SyncPlayController.new);

const _emptyGuid = '00000000000000000000000000000000';

class SyncPlayState {
  const SyncPlayState({
    this.activeGroup,
    this.groups = const [],
    this.loading = false,
    this.connected = false,
    this.error,
  });

  final SyncPlayGroup? activeGroup;
  final List<SyncPlayGroup> groups;
  final bool loading;
  final bool connected;
  final String? error;

  SyncPlayState copyWith({
    SyncPlayGroup? activeGroup,
    bool clearActiveGroup = false,
    List<SyncPlayGroup>? groups,
    bool? loading,
    bool? connected,
    String? error,
    bool clearError = false,
  }) {
    return SyncPlayState(
      activeGroup: clearActiveGroup ? null : activeGroup ?? this.activeGroup,
      groups: groups ?? this.groups,
      loading: loading ?? this.loading,
      connected: connected ?? this.connected,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SyncPlayController extends Notifier<SyncPlayState> {
  @override
  SyncPlayState build() {
    _repo = ref.watch(syncPlayRepositoryProvider);
    _socket = ref.watch(syncPlaySocketProvider);
    _jellyfin = ref.watch(jellyfinRepositoryProvider);
    _handler = ref.watch(audioHandlerProvider);
    _downloads = ref.watch(downloadManagerProvider.notifier);
    _socketSub = _socket.events.listen(_handleSocketEvent);
    ref.onDispose(() {
      _socketSub?.cancel();
      _scheduledCommandTimer?.cancel();
    });
    return const SyncPlayState();
  }

  late final SyncPlayRepository _repo;
  late final SyncPlaySocket _socket;
  late final JellyfinRepository _jellyfin;
  late final JellymusicAudioHandler _handler;
  late final DownloadManager _downloads;
  StreamSubscription<SyncPlaySocketEvent>? _socketSub;
  List<SyncPlayQueueItem> _queue = const [];
  final Map<String, jf.Track> _syncPlayTrackCache = {};
  SyncPlayQueueUpdate? _pendingPlayQueueUpdate;
  bool _processingPlayQueueUpdate = false;
  String? _lastAppliedPlayQueueKey;
  String? _lastCommandKey;
  DateTime? _lastCommandAt;
  Timer? _scheduledCommandTimer;

  Future<void> attach() => _socket.connect();

  Future<void> disconnect() async {
    _queue = const [];
    _syncPlayTrackCache.clear();
    _pendingPlayQueueUpdate = null;
    _lastAppliedPlayQueueKey = null;
    state = const SyncPlayState();
    await _socket.disconnect();
  }

  Future<void> refreshGroups() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      final groups = await _repo.listGroups();
      state = state.copyWith(
        groups: groups,
        loading: false,
        connected: _socket.connected,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> createGroup(String name) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      final groupName = _safeGroupName(name);
      final wasPlaying = _handler.playbackState.value.playing;
      await _repo.createGroup(groupName);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final group = state.activeGroup ?? await _findJoinedGroup(groupName);
      state = state.copyWith(
        activeGroup: group ?? state.activeGroup,
        groups: group == null
            ? state.groups
            : [group, ...state.groups.where((g) => g.id != group.id)],
        loading: false,
        connected: _socket.connected,
      );
      // Only push the current queue to the group if we were already playing.
      // SyncPlay's SetNewQueue auto-starts playback for everyone, so a paused
      // creator pushing their queue would surprise-play the room.
      if (wasPlaying) {
        await _publishCurrentQueue();
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> joinGroup(String groupId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      await _repo.joinGroup(groupId);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final group = state.activeGroup ?? await _findGroupById(groupId);
      state = state.copyWith(
        activeGroup: group ?? state.activeGroup,
        loading: false,
        connected: _socket.connected,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> leaveGroup() async {
    try {
      await _repo.leaveGroup();
    } finally {
      _queue = const [];
      _syncPlayTrackCache.clear();
      _pendingPlayQueueUpdate = null;
      _lastAppliedPlayQueueKey = null;
      state = state.copyWith(clearActiveGroup: true, clearError: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await refreshGroups();
    }
  }

  Future<void> playTracks(List<jf.Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return Future.value();
    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    await _repo.setNewQueue(
      tracks.map((track) => track.id).toList(growable: false),
      playingItemPosition: safeIndex,
    );
  }

  Future<void> playNext(jf.Track track) async {
    await _repo.queueItems([track.id], playNext: true);
  }

  Future<void> addToQueue(jf.Track track) => _repo.queueItems([track.id]);

  Future<void> togglePlay() async {
    final playing = _handler.playbackState.value.playing;
    if (playing) {
      await _repo.pause();
      return;
    }
    // If the group has no queue yet (e.g. group was created while paused),
    // pushing our local queue via SetNewQueue auto-starts playback for the
    // whole room. Otherwise just resume the existing queue.
    if (_queue.isEmpty) {
      await _publishCurrentQueue();
    } else {
      await _repo.unpause();
    }
  }

  Future<void> stop() async {
    await _repo.stop();
  }

  Future<void> seek(Duration position) async {
    await _repo.seek(position);
  }

  Future<void> next() async {
    final playlistItemId = _currentPlaylistItemId();
    if (playlistItemId != null && playlistItemId.isNotEmpty) {
      await _repo.nextItem(playlistItemId);
    } else {
      await _setServerQueuePosition((_handler.player.currentIndex ?? 0) + 1);
    }
  }

  Future<void> previous() async {
    final playlistItemId = _currentPlaylistItemId();
    if (playlistItemId != null && playlistItemId.isNotEmpty) {
      await _repo.previousItem(playlistItemId);
    } else {
      await _setServerQueuePosition((_handler.player.currentIndex ?? 0) - 1);
    }
  }

  Future<void> skipToIndex(int index) async {
    final queue = _handler.queue.value;
    if (index < 0 || index >= queue.length) return;
    if (index < _queue.length && _queue[index].playlistItemId.isNotEmpty) {
      await _repo.setPlaylistItem(_queue[index].playlistItemId);
    } else {
      await _setServerQueuePosition(index);
    }
  }

  String? _currentPlaylistItemId() {
    final mediaItem = _handler.mediaItem.value;
    final playlistId = mediaItem?.extras?['syncPlayPlaylistItemId'] as String?;
    if (playlistId != null && playlistId.isNotEmpty) return playlistId;
    final currentIndex = _handler.player.currentIndex;
    if (currentIndex != null &&
        currentIndex >= 0 &&
        currentIndex < _queue.length) {
      return _queue[currentIndex].playlistItemId;
    }
    return null;
  }

  void _handleSocketEvent(SyncPlaySocketEvent event) {
    switch (event) {
      case SyncPlaySocketStatusEvent(:final connected):
        state = state.copyWith(connected: connected);
        break;
      case SyncPlayCommandEvent(:final command):
        unawaited(_handleCommand(command));
        break;
      case SyncPlayGroupUpdateEvent(:final type, :final data):
        unawaited(_handleGroupUpdate(type, data));
        break;
    }
  }

  Future<void> _handleGroupUpdate(
    String type,
    Map<String, dynamic> data,
  ) async {
    final rawGroup = data['Data'] ?? data['data'];
    final groupId = _groupIdFromUpdate(data);
    if (type == 'GroupJoined' && rawGroup is Map) {
      state = state.copyWith(
        activeGroup: SyncPlayGroup.fromJson(
          Map<String, dynamic>.from(rawGroup),
        ),
        clearError: true,
      );
      return;
    }
    if (type == 'GroupLeft' || type == 'NotInGroup') {
      _queue = const [];
      _syncPlayTrackCache.clear();
      _pendingPlayQueueUpdate = null;
      _lastAppliedPlayQueueKey = null;
      state = state.copyWith(clearActiveGroup: true);
      return;
    }
    if (type == 'PlayQueue') {
      final raw = data['Data'] ?? data['data'];
      if (raw is Map) {
        _enqueuePlayQueueUpdate(
          SyncPlayQueueUpdate.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
    } else if (type == 'UserJoined' || type == 'UserLeft') {
      _applyParticipantUpdate(type, data, groupId);
    } else if (type == 'StateUpdate') {
      final raw = data['Data'] ?? data['data'];
      if (raw is Map) {
        final stateName = raw['State'] as String? ?? raw['state'] as String?;
        final active = state.activeGroup;
        if (active != null && stateName != null) {
          state = state.copyWith(
            activeGroup: active.copyWith(state: stateName),
          );
        }
      }
    }
  }

  String _safeGroupName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final username = _repo.username;
    return username == null || username.isEmpty
        ? 'AltSound group'
        : "$username's group";
  }

  Future<SyncPlayGroup?> _findJoinedGroup(String groupName) async {
    final groups = await _repo.listGroups();
    final username = _repo.username;
    final matches = groups.where((group) {
      final nameMatches = group.name == groupName;
      final userMatches =
          username == null || group.participants.contains(username);
      return nameMatches && userMatches;
    }).toList();
    if (matches.isNotEmpty) return matches.first;
    if (username != null) {
      final ownGroups = groups
          .where((group) => group.participants.contains(username))
          .toList();
      if (ownGroups.isNotEmpty) return ownGroups.first;
    }
    return null;
  }

  Future<SyncPlayGroup?> _findGroupById(String groupId) async {
    final groups = await _repo.listGroups();
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  String? _groupIdFromUpdate(Map<String, dynamic> data) {
    final raw = data['GroupId'] ?? data['groupId'];
    return raw is String ? raw : null;
  }

  void _applyParticipantUpdate(
    String type,
    Map<String, dynamic> data,
    String? groupId,
  ) {
    final active = state.activeGroup;
    if (active == null || (groupId != null && groupId != active.id)) return;
    final raw = data['Data'] ?? data['data'];
    if (raw is! String || raw.isEmpty) return;
    final participants = [...active.participants];
    if (type == 'UserJoined') {
      if (!participants.contains(raw)) participants.add(raw);
    } else {
      participants.remove(raw);
    }
    state = state.copyWith(
      activeGroup: active.copyWith(participants: participants),
    );
  }

  Future<void> _publishCurrentQueue() async {
    final itemIds = _localQueueItemIds();
    if (itemIds.isEmpty) return;
    final currentIndex = (_handler.player.currentIndex ?? 0).clamp(
      0,
      itemIds.length - 1,
    );
    await _repo.setNewQueue(
      itemIds,
      playingItemPosition: currentIndex,
      startPosition: _handler.player.position,
    );
  }

  Future<void> _setServerQueuePosition(int index) async {
    final itemIds = _localQueueItemIds();
    if (itemIds.isEmpty) return;
    final safeIndex = index.clamp(0, itemIds.length - 1);
    await _repo.setNewQueue(itemIds, playingItemPosition: safeIndex);
  }

  List<String> _localQueueItemIds() {
    return _handler.queue.value
        .map((item) => item.extras?['jellyfinId'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  void _enqueuePlayQueueUpdate(SyncPlayQueueUpdate update) {
    _pendingPlayQueueUpdate = update;
    if (_processingPlayQueueUpdate) return;
    _processingPlayQueueUpdate = true;
    unawaited(_drainPlayQueueUpdates());
  }

  Future<void> _drainPlayQueueUpdates() async {
    while (true) {
      final next = _pendingPlayQueueUpdate;
      if (next == null) break;
      _pendingPlayQueueUpdate = null;
      try {
        await _applyPlayQueueUpdate(next);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncPlay] play queue apply failed: $e');
        }
      }
    }
    _processingPlayQueueUpdate = false;
    if (_pendingPlayQueueUpdate != null) {
      _processingPlayQueueUpdate = true;
      unawaited(_drainPlayQueueUpdates());
    }
  }

  String _playQueueKey(SyncPlayQueueUpdate update) {
    final playlistKey = update.playlist
        .map((item) => '${item.itemId}:${item.playlistItemId}')
        .join(',');
    return '${update.playingItemIndex}|${update.startPosition.inMilliseconds}|'
        '${update.isPlaying}|$playlistKey';
  }

  Future<void> _applyPlayQueueUpdate(SyncPlayQueueUpdate update) async {
    if (update.playlist.isEmpty) return;
    final updateKey = _playQueueKey(update);
    if (_lastAppliedPlayQueueKey == updateKey) return;
    if (kDebugMode) {
      debugPrint(
        '[SyncPlay] play queue: ${update.playlist.length} items, index ${update.playingItemIndex}, playing=${update.isPlaying}, groupState=${state.activeGroup?.state}',
      );
    }
    _queue = update.playlist;
    final uniqueIds = <String>{};
    final missingIds = <String>[];
    for (final item in update.playlist) {
      final id = item.itemId;
      if (id.isEmpty || !uniqueIds.add(id)) continue;
      if (!_syncPlayTrackCache.containsKey(id)) missingIds.add(id);
    }
    if (missingIds.isNotEmpty) {
      final tracks = await _jellyfin.tracksByIds(missingIds);
      for (final track in tracks) {
        _syncPlayTrackCache[track.id] = track;
      }
    }
    final items = <MediaItem>[];
    for (final queueItem in update.playlist) {
      final track = _syncPlayTrackCache[queueItem.itemId];
      if (track == null) continue;
      items.add(
        mediaItemForTrack(
          ref: ref,
          repo: _jellyfin,
          downloads: _downloads,
          track: track,
          syncPlayPlaylistItemId: queueItem.playlistItemId,
        ),
      );
    }
    if (items.isEmpty) return;
    // Resolve the playing item by playlistItemId — clamping the server index
    // would land on a different song if any track failed to load locally.
    final playingItemId = update.playingItemIndex >= 0 &&
            update.playingItemIndex < update.playlist.length
        ? update.playlist[update.playingItemIndex].playlistItemId
        : null;
    final localIndex = playingItemId == null
        ? 0
        : items.indexWhere(
            (m) => m.extras?['syncPlayPlaylistItemId'] == playingItemId,
          );
    final index = localIndex < 0 ? 0 : localIndex;
    await _handler.loadQueue(
      items,
      initialIndex: index,
      initialPosition: update.startPosition,
      autoPlay: false,
      randomizeStart: false,
      respectShuffle: false,
    );
    _lastAppliedPlayQueueKey = updateKey;
    await _sendReady();
  }

  Future<void> _handleCommand(SyncPlayCommand command) async {
    if (_isDuplicateCommand(command)) return;
    if (kDebugMode) {
      debugPrint(
        '[SyncPlay] command: ${command.command}, position=${command.position}, item=${command.playlistItemId}',
      );
    }
    // Drop commands targeting a different playlist item than the one we're
    // currently on (Stop is unconditional, and the empty-GUID sentinel means
    // "no specific item" — apply globally). Auto-skipping locally desyncs
    // clients when their queues differ; the next PlayQueue update from the
    // server is the source of truth for which track we should be on.
    final cmdItem = command.playlistItemId;
    final isWildcardItem =
        cmdItem == null || cmdItem.isEmpty || cmdItem == _emptyGuid;
    if (command.command != 'Stop' &&
        !isWildcardItem &&
        cmdItem != _currentPlaylistItemId()) {
      if (kDebugMode) {
        debugPrint(
          '[SyncPlay] command playlist item mismatch — dropping: cmd=$cmdItem local=${_currentPlaylistItemId()}',
        );
      }
      return;
    }
    // Cancel any previously scheduled command — this one supersedes it.
    _scheduledCommandTimer?.cancel();
    _scheduledCommandTimer = null;
    final delay = _delayUntil(command.when);
    if (delay > Duration.zero) {
      final completer = Completer<void>();
      _scheduledCommandTimer = Timer(delay, () {
        _scheduledCommandTimer = null;
        completer.complete();
      });
      await completer.future;
    }
    final targetPosition = _adjustedPosition(command);
    switch (command.command) {
      case 'Unpause':
        if (targetPosition != null) await _handler.seek(targetPosition);
        await _handler.play();
        break;
      case 'Pause':
        if (targetPosition != null) await _handler.seek(targetPosition);
        await _handler.pause();
        break;
      case 'Seek':
        if (targetPosition != null) await _handler.seek(targetPosition);
        await _sendReady();
        break;
      case 'Stop':
        await _handler.stop();
        break;
    }
  }

  bool _isDuplicateCommand(SyncPlayCommand command) {
    final key = [
      command.command,
      command.playlistItemId ?? '',
      command.position?.inMilliseconds ?? '',
      command.when?.toIso8601String() ?? '',
    ].join('|');
    final now = DateTime.now();
    final lastAt = _lastCommandAt;
    final duplicate =
        _lastCommandKey == key &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 2);
    _lastCommandKey = key;
    _lastCommandAt = now;
    if (duplicate && kDebugMode) {
      debugPrint('[SyncPlay] duplicate command ignored: ${command.command}');
    }
    return duplicate;
  }

  Duration _delayUntil(DateTime? when) {
    if (when == null) return Duration.zero;
    final delay = when.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) return Duration.zero;
    return delay > const Duration(seconds: 20)
        ? const Duration(seconds: 20)
        : delay;
  }

  Duration? _adjustedPosition(SyncPlayCommand command) {
    final position = command.position;
    if (position == null) return null;
    if (command.command != 'Unpause' || command.when == null) return position;
    final elapsed = DateTime.now().toUtc().difference(command.when!);
    if (elapsed <= Duration.zero) return position;
    return position + elapsed;
  }

  Future<void> _sendReady() async {
    final playlistItemId = _currentPlaylistItemId();
    if (playlistItemId == null || playlistItemId.isEmpty) return;
    try {
      await _repo.ready(
        playlistItemId: playlistItemId,
        position: _handler.player.position,
        isPlaying: _handler.playbackState.value.playing,
      );
    } catch (_) {
      // SyncPlay readiness is best-effort; playback should keep working.
    }
  }
}
