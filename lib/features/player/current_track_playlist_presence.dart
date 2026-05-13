import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/player_providers.dart';

/// Jellyfin favorite flag plus playlist rows that contain the current track.
class CurrentTrackPlaylistPresence {
  const CurrentTrackPlaylistPresence({
    required this.isFavorite,
    required this.memberships,
  });

  final bool isFavorite;
  final List<PlaylistMembership> memberships;

  bool get isSaved => isFavorite || memberships.isNotEmpty;
}

final currentTrackPlaylistPresenceProvider =
    FutureProvider.autoDispose<CurrentTrackPlaylistPresence>((ref) async {
  final item = ref.watch(currentMediaItemProvider).value;
  if (item == null || item.extras?['isOffline'] == true) {
    return const CurrentTrackPlaylistPresence(
      isFavorite: false,
      memberships: <PlaylistMembership>[],
    );
  }
  final repo = ref.read(jellyfinRepositoryProvider);
  final trackId = item.id;
  final playlists = await repo.playlists();
  final isFavorite = await repo.isFavorite(trackId);
  final memberships = await repo.playlistsContainingTrack(
    trackId,
    playlistsCache: playlists,
  );
  return CurrentTrackPlaylistPresence(
    isFavorite: isFavorite,
    memberships: memberships,
  );
});
