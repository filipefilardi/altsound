import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/download_preferences.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/local/connectivity_provider.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../downloads/widgets/playlist_download_button.dart';
import '../player/player_providers.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/widgets/playing_track_leading.dart';
import '../player/widgets/track_more_menu_button.dart';
import 'playlist_providers.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistProvider(playlistId));
    final playlist = async.value;
    final canDelete =
        playlist != null && playlist.name.toLowerCase().trim() != 'liked songs';
    final isOffline = ref.watch(isOfflineProvider);
    final downloads = ref.watch(downloadManagerProvider);

    ref.listen(playlistProvider(playlistId), (prev, next) {
      if (prev?.value == null && next.value != null) {
        final prefs = ref.read(downloadPreferencesProvider);
        if (prefs.autoDownload &&
            prefs.isPlaylistSubscribed(next.value!.id)) {
          ref
              .read(downloadManagerProvider.notifier)
              .enqueuePlaylist(next.value!);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist'),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Delete playlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref, playlist),
            ),
        ],
      ),
      bottomNavigationBar: const MiniPlayerSlot(withTopDivider: true),
      body: async.when(
        loading: () {
          final offlinePlaylist = _buildOfflinePlaylist(playlistId, downloads);
          if (isOffline && offlinePlaylist != null) {
            return _PlaylistView(playlist: offlinePlaylist);
          }
          return const _PlaylistLoading();
        },
        error: (e, _) {
          final offlinePlaylist = _buildOfflinePlaylist(playlistId, downloads);
          if (offlinePlaylist != null) return _PlaylistView(playlist: offlinePlaylist);
          return ErrorStateView(
            title: "Couldn't load this playlist",
            message: e.toString(),
            onRetry: () => ref.invalidate(playlistProvider(playlistId)),
          );
        },
        data: (playlist) => _PlaylistView(playlist: playlist),
      ),
    );
  }

  static PlaylistDetail? _buildOfflinePlaylist(
      String playlistId, DownloadsState downloads) {
    final saved = downloads.playlists[playlistId];
    if (saved == null) return null;
    final tracks = saved.trackIds
        .map((id) => downloads.tracks[id])
        .where((t) => t != null)
        .map((t) => t!.toTrack())
        .toList();
    if (tracks.isEmpty) return null;
    return PlaylistDetail(
      id: playlistId,
      name: saved.name,
      imageTag: saved.imageTag,
      tracks: tracks,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(jellyfinRepositoryProvider).deletePlaylist(playlist.id);
    if (!context.mounted) return;
    context.pop();
  }
}

class _PlaylistView extends ConsumerWidget {
  const _PlaylistView({required this.playlist});

  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _PlaylistHeader(playlist: playlist),
        const SizedBox(height: 16),
        _ActionRow(playlist: playlist),
        const SizedBox(height: 8),
        if (playlist.tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No songs in this playlist yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ...playlist.tracks.asMap().entries.map(
                (entry) => _PlaylistTrackTile(
                  track: entry.value,
                  index: entry.key,
                  allTracks: playlist.tracks,
                ),
              ),
      ],
    );
  }
}

class _PlaylistHeader extends ConsumerWidget {
  const _PlaylistHeader({required this.playlist});
  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PlaylistArtwork(playlist: playlist),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playlist.name,
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${playlist.tracks.length} songs · ${formatLongDuration(playlist.totalDuration)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistArtwork extends ConsumerWidget {
  const _PlaylistArtwork({required this.playlist});

  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(jellyfinRepositoryProvider);
    final uniqueAlbumTracks = <Track>[];
    final seenAlbumIds = <String>{};

    for (final track in playlist.tracks) {
      final albumId = track.albumImageItemId ?? track.albumId ?? track.id;
      if (seenAlbumIds.add(albumId)) {
        uniqueAlbumTracks.add(track);
      }
      if (uniqueAlbumTracks.length == 4) break;
    }

    // Build cover from current playlist tracks to keep artwork synchronized.
    if (uniqueAlbumTracks.length > 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 120,
          height: 120,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
            ),
            itemCount: 4,
            itemBuilder: (_, index) {
              final track = uniqueAlbumTracks[index % uniqueAlbumTracks.length];
              if (track.imageTag == null || track.imageTag!.isEmpty) {
                return const _ArtFallback();
              }
              final artId = track.albumImageItemId ?? track.id;
              final imageUrl = repo.imageUrl(
                artId,
                imageTag: track.imageTag,
                size: 300,
              );
              return CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppColors.surfaceElevated),
                errorWidget: (_, __, ___) => const _ArtFallback(),
              );
            },
          ),
        ),
      );
    }

    final firstTrack = playlist.tracks.firstOrNull;
    final artId = firstTrack?.albumImageItemId ?? firstTrack?.id ?? playlist.id;
    final artTag = firstTrack?.imageTag ?? playlist.imageTag;
    final imageUrl = (artTag == null || artTag.isEmpty)
        ? null
        : repo.imageUrl(artId, imageTag: artTag, size: 300);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 120,
        height: 120,
        child: imageUrl == null
            ? const _ArtFallback()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppColors.surfaceElevated),
                errorWidget: (_, __, ___) => const _ArtFallback(),
              ),
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.playlist});
  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    final playbackState = ref.watch(playbackStateProvider).value;
    final queue = ref.watch(queueProvider).value ?? const [];
    final playlistTrackIds = playlist.tracks.map((t) => t.id).toList();
    final queueTrackIds = queue
        .map((item) => item.extras?['jellyfinId'] as String?)
        .whereType<String>()
        .toList();
    final matchesPlaylistQueue = playlistTrackIds.length == queueTrackIds.length &&
        List<int>.generate(playlistTrackIds.length, (i) => i).every(
          (i) => playlistTrackIds[i] == queueTrackIds[i],
        );
    final isPlaylistPlaying =
        playbackState?.playing == true && matchesPlaylistQueue;
    final enabled = playlist.tracks.isNotEmpty;

    return Row(
      children: [
        _PlayPill(
          onTap: enabled
              ? () {
                  if (isPlaylistPlaying) {
                    controller.stop();
                    return;
                  }
                  controller.playTracks(
                    playlist.tracks,
                    continueCurrentIfSameQueueAndPaused: true,
                  );
                }
              : null,
          icon: isPlaylistPlaying ? Icons.stop : Icons.play_arrow,
          tooltip: isPlaylistPlaying ? 'Stop' : 'Play',
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Shuffle',
          icon: const Icon(Icons.shuffle, color: AppColors.textPrimary),
          onPressed: enabled
              ? () async {
                  await controller.toggleShuffle();
                  if (!context.mounted) return;
                  controller.playTracks(playlist.tracks);
                }
              : null,
        ),
        PlaylistDownloadButton(playlist: playlist),
      ],
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({
    required this.onTap,
    required this.icon,
    required this.tooltip,
  });
  final VoidCallback? onTap;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Tooltip(
        message: tooltip,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: AppColors.primary.withValues(alpha: 0.2),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(icon, color: const Color(0xFF1A0F05), size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(Icons.queue_music, color: AppColors.textTertiary, size: 40),
      ),
    );
  }
}

class _PlaylistTrackTile extends ConsumerWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.index,
    required this.allTracks,
  });

  final Track track;
  final int index;
  final List<Track> allTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isDownloaded =
        ref.watch(downloadManagerProvider).isDownloaded(track.id);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: () => ref
          .read(playerControllerProvider)
          .playTracks(allTracks, startIndex: index),
      leading: PlayingTrackLeading(
        jellyfinTrackId: track.id,
        indexLabel: '${index + 1}',
      ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? AppColors.primary : AppColors.textPrimary,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: InkWell(
        onTap: track.artistId == null || track.artistId!.isEmpty
            ? null
            : () => context.push('/artist/${track.artistId}'),
        child: Text(
          track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: track.artistId == null || track.artistId!.isEmpty
                ? AppColors.textSecondary
                : AppColors.primary,
            fontSize: 12,
          ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDownloaded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.download_for_offline,
                  size: 14, color: AppColors.primary),
            ),
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

class _PlaylistLoading extends StatelessWidget {
  const _PlaylistLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Skeleton.box(width: 120, height: 120, radius: 12),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 160, height: 20),
                    const SizedBox(height: 8),
                    Skeleton.line(width: 120, height: 13),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Skeleton.box(width: 56, height: 56, radius: 28),
          const SizedBox(height: 16),
          for (int i = 0; i < 8; i++) ...[
            Skeleton.line(height: 14),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
