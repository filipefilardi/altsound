import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../player/player_providers.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/widgets/playing_track_leading.dart';
import '../player/widgets/track_more_menu_button.dart';

final playlistProvider =
    FutureProvider.family<PlaylistDetail, String>((ref, playlistId) {
  return ref.read(jellyfinRepositoryProvider).playlist(playlistId);
});

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistProvider(playlistId));
    final playlist = async.value;
    final canDelete =
        playlist != null && playlist.name.toLowerCase().trim() != 'liked songs';
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
        loading: () => const _PlaylistLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load this playlist",
          message: e.toString(),
          onRetry: () => ref.invalidate(playlistProvider(playlistId)),
        ),
        data: (playlist) => _PlaylistView(playlist: playlist),
      ),
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
    final repo = ref.read(jellyfinRepositoryProvider);
    final firstTrack = playlist.tracks.firstOrNull;

    // Use playlist image tag if available, else fall back to first track's art
    final String? artId = playlist.imageTag != null
        ? playlist.id
        : firstTrack?.albumImageItemId ?? firstTrack?.id;
    final String? artTag = playlist.imageTag ?? firstTrack?.imageTag;
    final imageUrl =
        artId != null ? repo.imageUrl(artId, imageTag: artTag, size: 300) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 120,
            height: 120,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const ColoredBox(color: AppColors.surfaceElevated),
                    errorWidget: (_, __, ___) => const _ArtFallback(),
                  )
                : const _ArtFallback(),
          ),
        ),
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

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.playlist});
  final PlaylistDetail playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    final enabled = playlist.tracks.isNotEmpty;

    return Row(
      children: [
        _PlayPill(
          onTap: enabled ? () => controller.playTracks(playlist.tracks) : null,
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
      ],
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
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
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.play_arrow, color: Color(0xFF1A0F05), size: 30),
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
