import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';
import 'package:altsound/features/player/widgets/track_listing_widgets.dart';
import 'package:altsound/features/player/widgets/track_more_menu_button.dart';

/// Track tile used in playlist detail. Wraps [TrackListTile] with playlist
/// specifics: selection mode, artist/album navigation taps, and the
/// "if current, push now-playing" tap shortcut.
class PlaylistTrackTile extends ConsumerWidget {
  const PlaylistTrackTile({
    required this.track,
    required this.index,
    required this.allTracks,
    required this.contextId,
    required this.inSelection,
    required this.isSelected,
    required this.onLongPress,
    required this.onToggleSelected,
    super.key,
  });

  final Track track;
  final int index;
  final List<Track> allTracks;
  final String contextId;
  final bool inSelection;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);
    return TrackListTile(
      track: track,
      index: index,
      isCurrent: isCurrent,
      isDownloaded: isDownloaded,
      inSelection: inSelection,
      isSelected: isSelected,
      onLongPress: onLongPress,
      onToggleSelected: onToggleSelected,
      onArtistTap: track.artistId == null || track.artistId!.isEmpty
          ? null
          : () => context.push('/artist/${track.artistId}'),
      onAlbumTap: track.albumId == null || track.albumId!.isEmpty
          ? null
          : () => context.push('/album/${track.albumId}'),
      showAlbumInTrailing: true,
      onTap: () {
        if (inSelection) {
          onToggleSelected();
          return;
        }
        final isCurrentInContext =
            isCurrent && current.extras?['contextId'] == contextId;
        if (isCurrentInContext) {
          context.pushNowPlayingIfNeeded();
          return;
        }
        ref
            .read(playerControllerProvider)
            .playTracks(
              allTracks,
              startIndex: index,
              contextId: contextId,
              selectedTrack: true,
            );
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
    );
  }
}
