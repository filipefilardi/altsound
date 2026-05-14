import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/local_or_network_image.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';

/// Single row in the search results list. Renders the right leading for the
/// item's [BrowseItem.kind] (artwork for tracks/albums/playlists, circular
/// avatar for artists) and, for tracks, a more menu with quick actions.
class SearchResultTile extends ConsumerWidget {
  const SearchResultTile({required this.item, super.key});
  final BrowseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final localArtwork = _localArtworkFor(item, downloads);
    final imageUrl =
        localArtwork ??
        (item.imageTag == null || item.imageTag!.isEmpty
            ? null
            : repo.imageUrl(item.id, imageTag: item.imageTag, size: 200));
    final isArtist = item.kind == MediaKind.artist;
    final isTrack = item.kind == MediaKind.track;
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrentTrack =
        isTrack && current != null && current.extras?['jellyfinId'] == item.id;

    final isDownloaded =
        isTrack && ref.watch(downloadManagerProvider).isDownloaded(item.id);

    final leading = isTrack
        ? SearchTrackArtwork(
            imageUrl: imageUrl,
            jellyfinTrackId: item.id,
            isArtistShape: false,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(isArtist ? 28 : 4),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imageUrl == null
                  ? Container(
                      color: AppColors.surfaceElevated,
                      child: Icon(
                        _iconFor(item.kind),
                        color: AppColors.textTertiary,
                      ),
                    )
                  : LocalOrNetworkImage(
                      source: imageUrl,
                      fit: BoxFit.cover,
                      placeholderBuilder: (_) =>
                          Container(color: AppColors.surfaceElevated),
                      errorBuilder: (_) => Container(
                        color: AppColors.surfaceElevated,
                        child: Icon(
                          _iconFor(item.kind),
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
            ),
          );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: leading,
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrentTrack ? AppColors.primary : null,
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        item.subtitle ?? _labelFor(item.kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: isTrack
          ? Row(
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
                if (item.runTime != null)
                  PlayingTrackDuration(
                    jellyfinTrackId: item.id,
                    trackDuration: item.runTime!,
                  ),
                _SearchTrackMenuButton(trackId: item.id),
              ],
            )
          : null,
      onTap: () => _onTap(context, ref),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final isOffline = ref.read(isOfflineProvider);
    final downloads = ref.read(downloadManagerProvider);
    switch (item.kind) {
      case MediaKind.album:
        if (isOffline && !_hasDownloadedAlbum(item.id, downloads)) {
          _showOfflineUnavailable(
            context,
            'Download this album to open it offline.',
          );
          return;
        }
        context.push('/album/${item.id}');
      case MediaKind.track:
        final downloaded = downloads.tracks[item.id];
        if (isOffline && downloaded == null) {
          _showOfflineUnavailable(
            context,
            'Download this song to play it offline.',
          );
          return;
        }
        final track =
            downloaded?.toTrack() ??
            await ref.read(jellyfinRepositoryProvider).track(item.id);
        await ref.read(playerControllerProvider).playTracks([
          track,
        ], selectedTrack: true);
      case MediaKind.artist:
        if (isOffline) {
          _showOfflineUnavailable(
            context,
            'Artist pages need the server. Download albums or playlists to open them offline.',
          );
          return;
        }
        context.push('/artist/${item.id}');
      case MediaKind.playlist:
        if (isOffline && !_hasDownloadedPlaylist(item.id, downloads)) {
          _showOfflineUnavailable(
            context,
            'Download this playlist to open it offline.',
          );
          return;
        }
        context.push('/playlist/${item.id}');
    }
  }
}

class _SearchTrackMenuButton extends ConsumerWidget {
  const _SearchTrackMenuButton({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (anchorCtx) => IconButton(
        icon: const Icon(
          Icons.more_vert_rounded,
          color: AppColors.textSecondary,
        ),
        onPressed: () async {
          final repo = ref.read(jellyfinRepositoryProvider);
          final downloaded = ref.read(downloadManagerProvider).tracks[trackId];
          if (downloaded == null && ref.read(isOfflineProvider)) {
            _showOfflineUnavailable(
              context,
              'Download this song to manage it offline.',
            );
            return;
          }
          final track = downloaded?.toTrack() ?? await repo.track(trackId);
          if (!anchorCtx.mounted) return;
          await showGlassPopover<void>(
            context: anchorCtx,
            builder: (_) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassPopoverItem(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to playlist',
                  onTap: () => openAddTrackToPlaylistFlow(
                    context,
                    ref,
                    trackId: track.id,
                    includeLikedSongsShortcut: true,
                  ),
                ),
                GlassPopoverItem(
                  icon: Icons.queue_music_rounded,
                  label: 'Add to queue',
                  onTap: () =>
                      ref.read(playerControllerProvider).addToQueue(track),
                ),
                if (track.albumId != null && track.albumId!.isNotEmpty)
                  GlassPopoverItem(
                    icon: Icons.album_rounded,
                    label: 'Go to album',
                    onTap: () => context.push('/album/${track.albumId}'),
                  ),
                if (track.artistId != null && track.artistId!.isNotEmpty)
                  GlassPopoverItem(
                    icon: Icons.person_rounded,
                    label: 'Go to artist',
                    onTap: () => context.push('/artist/${track.artistId}'),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Private helpers ────────────────────────────────────────────────────────

IconData _iconFor(MediaKind k) => switch (k) {
  MediaKind.album => Icons.album_rounded,
  MediaKind.artist => Icons.person_rounded,
  MediaKind.track => Icons.music_note_rounded,
  MediaKind.playlist => Icons.queue_music_rounded,
};

String _labelFor(MediaKind k) => switch (k) {
  MediaKind.album => 'Album',
  MediaKind.artist => 'Artist',
  MediaKind.track => 'Song',
  MediaKind.playlist => 'Playlist',
};

void _showOfflineUnavailable(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

bool _hasDownloadedAlbum(String albumId, DownloadsState downloads) {
  return downloads.tracks.values.any((track) => track.albumId == albumId);
}

bool _hasDownloadedPlaylist(String playlistId, DownloadsState downloads) {
  final playlist = downloads.playlists[playlistId];
  if (playlist == null) return false;
  return playlist.trackIds.any(downloads.tracks.containsKey);
}

String? _localArtworkFor(BrowseItem item, DownloadsState downloads) {
  switch (item.kind) {
    case MediaKind.track:
      return downloads.tracks[item.id]?.artworkPath;
    case MediaKind.album:
      for (final track in downloads.tracks.values) {
        if (track.albumId == item.id && track.artworkPath != null) {
          return track.artworkPath;
        }
      }
      return null;
    case MediaKind.playlist:
      final playlist = downloads.playlists[item.id];
      if (playlist == null) return null;
      for (final trackId in playlist.trackIds) {
        final artworkPath = downloads.tracks[trackId]?.artworkPath;
        if (artworkPath != null) return artworkPath;
      }
      return null;
    case MediaKind.artist:
      return null;
  }
}
