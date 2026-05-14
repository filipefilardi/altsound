import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';
import 'package:altsound/features/player/widgets/track_more_menu_button.dart';

/// Tile used in the artist screen's "Popular tracks" section. Unlike
/// [TrackListTile], this one shows the track's album artwork as the leading
/// thumbnail and prefixes the title with the popularity rank.
class PopularTrackTile extends ConsumerWidget {
  const PopularTrackTile({
    required this.rank,
    required this.track,
    required this.allTracks,
    required this.contextId,
    super.key,
  });

  /// 1-based popularity rank shown in the title (e.g. "3. Song Name").
  final int rank;
  final Track track;
  final List<Track> allTracks;
  final String contextId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack =
        current != null && current.extras?['jellyfinId'] == track.id;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = repo.imageUrl(
      track.imageItemId,
      imageTag: track.imageTag,
      size: 200,
    );
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SearchTrackArtwork(
        imageUrl: imageUrl,
        jellyfinTrackId: track.id,
        isArtistShape: false,
      ),
      title: Text(
        '$rank. ${track.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrentTrack ? AppColors.primary : null,
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        track.albumName ?? 'Single',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDownloaded)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                Icons.download_for_offline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          PlayingTrackDuration(
            jellyfinTrackId: track.id,
            trackDuration: track.duration,
          ),
          TrackMoreMenuButton(track: track),
        ],
      ),
      onTap: () {
        final isCurrentInContext =
            isCurrentTrack && current.extras?['contextId'] == contextId;
        if (isCurrentInContext) {
          context.pushNowPlayingIfNeeded();
          return;
        }
        ref
            .read(playerControllerProvider)
            .playTracks(
              allTracks,
              startIndex: rank - 1,
              contextId: contextId,
              selectedTrack: true,
            );
      },
    );
  }
}
