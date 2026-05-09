import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/syncplay.dart';

final syncPlayRepositoryProvider = Provider<SyncPlayRepository>((ref) {
  return SyncPlayRepository(ref.watch(jellyfinApiProvider));
});

class SyncPlayRepository {
  SyncPlayRepository(this._api);

  final JellyfinApi _api;

  String? get username => _api.session?.username;

  Future<List<SyncPlayGroup>> listGroups() async {
    final res = await _api.dio.get<List<dynamic>>('/SyncPlay/List');
    return (res.data ?? const [])
        .whereType<Map>()
        .map((m) => SyncPlayGroup.fromJson(Map<String, dynamic>.from(m)))
        .where((g) => g.id.isNotEmpty && g.participants.isNotEmpty)
        .toList();
  }

  Future<void> createGroup(String groupName) async {
    final safeName = groupName.trim().isEmpty
        ? 'AltSound group'
        : groupName.trim();
    final truncatedName = safeName.substring(
      0,
      safeName.length > 80 ? 80 : safeName.length,
    );
    await _post('/SyncPlay/New', data: {'GroupName': truncatedName});
  }

  Future<void> joinGroup(String groupId) async {
    await _post('/SyncPlay/Join', data: {'GroupId': groupId});
  }

  Future<void> leaveGroup() => _post('/SyncPlay/Leave');

  Future<void> setNewQueue(
    List<String> itemIds, {
    int playingItemPosition = 0,
    Duration startPosition = Duration.zero,
  }) async {
    if (itemIds.isEmpty) return;
    await _post(
      '/SyncPlay/SetNewQueue',
      data: {
        'PlayingQueue': itemIds,
        'PlayingItemPosition': playingItemPosition.clamp(0, itemIds.length - 1),
        'StartPositionTicks': durationToJellyfinTicks(startPosition),
      },
    );
  }

  Future<void> queueItems(List<String> itemIds, {bool playNext = false}) async {
    if (itemIds.isEmpty) return;
    await _post(
      '/SyncPlay/Queue',
      data: {'ItemIds': itemIds, 'Mode': playNext ? 'QueueNext' : 'Queue'},
    );
  }

  Future<void> setPlaylistItem(String playlistItemId) async {
    if (playlistItemId.isEmpty) return;
    await _post(
      '/SyncPlay/SetPlaylistItem',
      data: {'PlaylistItemId': playlistItemId},
    );
  }

  Future<void> nextItem(String playlistItemId) async {
    await _post('/SyncPlay/NextItem', data: {'PlaylistItemId': playlistItemId});
  }

  Future<void> previousItem(String playlistItemId) async {
    await _post(
      '/SyncPlay/PreviousItem',
      data: {'PlaylistItemId': playlistItemId},
    );
  }

  Future<void> pause() => _post('/SyncPlay/Pause');
  Future<void> unpause() => _post('/SyncPlay/Unpause');
  Future<void> stop() => _post('/SyncPlay/Stop');

  Future<void> seek(Duration position) async {
    await _post(
      '/SyncPlay/Seek',
      data: {'PositionTicks': durationToJellyfinTicks(position)},
    );
  }

  Future<void> ready({
    required String playlistItemId,
    required Duration position,
    required bool isPlaying,
  }) async {
    await _post(
      '/SyncPlay/Ready',
      data: {
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': durationToJellyfinTicks(position),
        'IsPlaying': isPlaying,
        'PlaylistItemId': playlistItemId,
      },
    );
  }

  Future<void> _post(String path, {Object? data}) async {
    final response = await _api.dio.post<void>(path, data: data);
    if (kDebugMode && path != '/SyncPlay/Ready') {
      debugPrint('[SyncPlay] POST $path -> ${response.statusCode}');
    }
  }
}
