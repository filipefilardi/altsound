import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/player_providers.dart';

final nowPlayingFavoriteProvider =
    AsyncNotifierProvider<NowPlayingFavorite, bool?>(NowPlayingFavorite.new);

class NowPlayingFavorite extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() async {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return null;
    if (item.extras?['isOffline'] == true) return null;
    return ref.read(jellyfinRepositoryProvider).isFavorite(item.id);
  }

  Future<void> toggle() async {
    final item = ref.read(currentMediaItemProvider).value;
    if (item == null || item.extras?['isOffline'] == true) return;
    if (!state.hasValue || state.value == null) return;
    final was = state.value!;
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      await repo.setFavorite(item.id, favorite: !was);
      if (!was) {
        await repo.addTrackToLikedSongs(item.id);
      }
      ref.invalidate(currentTrackPlaylistPresenceProvider);
      state = AsyncData(!was);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
