import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
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
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
            padding: const EdgeInsets.only(top: 8, bottom: 24),
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
                  subtitle: 'Playlist',
                  onTap: () => context.push('/playlist/${playlist.id}'),
                ),
              ),
              if (rest.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'No playlists yet. Use the 3-dot menu on a song to add it to a playlist.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final _likedSongsPlaylistProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
});

final _playlistsProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).playlists();
});

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
