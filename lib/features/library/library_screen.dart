import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likedSongsAsync = ref.watch(_likedSongsPlaylistProvider);
    final playlistsAsync = ref.watch(_playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPlaylist(context, ref),
        tooltip: 'New playlist',
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        loading: () => const _LibraryLoading(),
        error: (e, _) => Center(
          child: Text(
            'Could not load playlists: $e',
            style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
        data: (playlists) {
          final liked = likedSongsAsync.value;
          final rest = playlists
              .where((p) =>
                  p.kind == MediaKind.playlist &&
                  p.id != liked?.id &&
                  p.name.toLowerCase().trim() != 'liked songs')
              .toList();
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              _SectionTile(
                icon: Icons.favorite_outline,
                title: 'Liked Songs',
                subtitle: liked == null
                    ? 'Songs you heart appear here automatically'
                    : 'Open your liked songs playlist',
                onTap: () async {
                  final playlist =
                      await ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
                  if (playlist == null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Like any song to create your Liked Songs playlist.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  context.push('/playlist/${playlist.id}');
                },
              ),
              ...rest.map(
                (playlist) => _SectionTile(
                  icon: Icons.queue_music_outlined,
                  title: playlist.name,
                  subtitle: playlist.childCount != null
                      ? 'Playlist · ${playlist.childCount} songs'
                      : 'Playlist',
                  onTap: () => context.push('/playlist/${playlist.id}'),
                ),
              ),
              if (rest.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'No playlists yet. Tap + to create one.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final playlistName = name?.trim() ?? '';
    if (playlistName.isEmpty) return;
    await ref.read(jellyfinRepositoryProvider).createPlaylist(playlistName);
    ref.invalidate(_playlistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$playlistName" created')),
    );
  }
}

final _likedSongsPlaylistProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
});

final _playlistsProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).playlists();
});

class _LibraryLoading extends StatelessWidget {
  const _LibraryLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Skeleton.box(width: 52, height: 52, radius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton.line(width: 160, height: 14),
                        const SizedBox(height: 6),
                        Skeleton.line(width: 100, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
