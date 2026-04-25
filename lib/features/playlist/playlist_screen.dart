import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
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
        Text(
          playlist.name,
          style: Theme.of(context).textTheme.headlineSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${playlist.tracks.length} songs • ${formatLongDuration(playlist.totalDuration)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (playlist.tracks.isNotEmpty)
          FilledButton.icon(
            onPressed: () =>
                ref.read(playerControllerProvider).playTracks(playlist.tracks),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
        const SizedBox(height: 12),
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
        trackDuration: track.duration,
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
          Skeleton.line(width: 160, height: 24),
          const SizedBox(height: 8),
          Skeleton.line(width: 130, height: 12),
          const SizedBox(height: 16),
          Skeleton.box(width: 92, height: 40, radius: 20),
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
