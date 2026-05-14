import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';
import 'package:altsound/features/player/widgets/track_listing_widgets.dart';
import 'package:altsound/features/player/widgets/track_more_menu_button.dart';

/// Track row for the Instant Mix detail screen. Wraps [TrackListTile] with
/// instant-mix specifics: pushes the now-playing screen if the row is already
/// active in this mix's context, otherwise starts playback from the tapped
/// index using `instant-mix:<seed>` as the `contextId`.
class InstantMixTrackTile extends ConsumerWidget {
  const InstantMixTrackTile({
    required this.seedItemId,
    required this.tracks,
    required this.index,
    super.key,
  });

  final String seedItemId;
  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks[index];
    final contextId = instantMixContextId(seedItemId);
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isCurrentInContext =
        isCurrent && current.extras?['contextId'] == contextId;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);
    return TrackListTile(
      track: track,
      index: index,
      isCurrent: isCurrent,
      isDownloaded: isDownloaded,
      onArtistTap: track.artistId == null || track.artistId!.isEmpty
          ? null
          : () => context.push('/artist/${track.artistId}'),
      onAlbumTap: track.albumId == null || track.albumId!.isEmpty
          ? null
          : () => context.push('/album/${track.albumId}'),
      showAlbumInTrailing: true,
      onTap: () {
        if (isCurrentInContext) {
          context.pushNowPlayingIfNeeded();
          return;
        }
        ref
            .read(playerControllerProvider)
            .playTracks(
              tracks,
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
