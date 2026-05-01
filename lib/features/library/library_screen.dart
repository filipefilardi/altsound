import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../../data/local/connectivity_provider.dart';
import '../downloads/offline_library_view.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    if (isOffline) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Your Library'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: const OfflineLibraryView(),
      );
    }

    final likedSongsAsync = ref.watch(_likedSongsPlaylistProvider);
    final playlistsAsync = ref.watch(_playlistsProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final hasDownloads =
        downloads.tracks.isNotEmpty || downloads.playlists.isNotEmpty;
    final onlineLibraryChildren = playlistsAsync.when<List<Widget>>(
      loading: () => const [_LibraryLoadingRows()],
      error: (e, _) => [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load playlists: $e',
            style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ],
      data: (playlists) {
        final liked = likedSongsAsync.value;
        final rest = playlists
            .where(
              (p) =>
                  p.kind == MediaKind.playlist &&
                  p.id != liked?.id &&
                  p.name.toLowerCase().trim() != 'liked songs',
            )
            .toList();
        return [
          _SectionTile(
            icon: Icons.favorite_rounded,
            iconColor: AppColors.error,
            title: 'Liked Songs',
            subtitle: liked == null
                ? 'Songs you heart appear here automatically'
                : 'Open your liked songs playlist',
            onTap: () async {
              final playlist = await ref
                  .read(jellyfinRepositoryProvider)
                  .likedSongsPlaylist();
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
          _NewPlaylistTile(onTap: () => _createPlaylist(context, ref)),
          ...rest.map(
            (playlist) => _SectionTile(
              icon: Icons.queue_music_rounded,
              title: playlist.name,
              subtitle: playlist.childCount != null
                  ? 'Playlist · ${playlist.childCount} songs'
                  : 'Playlist',
              onTap: () => context.push('/playlist/${playlist.id}'),
            ),
          ),
        ];
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          if (hasDownloads) ...[
            const _SectionHeader(label: 'Downloaded'),
            const OfflineLibraryView(
              showEmptyState: false,
              scrollable: false,
              padding: EdgeInsets.zero,
            ),
            const _SectionHeader(label: 'Library'),
          ],
          ...onlineLibraryChildren,
        ],
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$playlistName" created')));
  }
}

final _likedSongsPlaylistProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).likedSongsPlaylist();
});

final _playlistsProvider = FutureProvider.autoDispose((ref) {
  return ref.read(jellyfinRepositoryProvider).playlists();
});

class _LibraryLoadingRows extends StatelessWidget {
  const _LibraryLoadingRows();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _NewPlaylistTile extends StatelessWidget {
  const _NewPlaylistTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.add_rounded,
          color: AppColors.primary,
          size: 24,
        ),
      ),
      title: Text(
        'New Playlist',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Create a new playlist',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColors.textPrimary,
  });

  final IconData icon;
  final Color iconColor;
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
          color: iconColor == AppColors.textPrimary
              ? AppColors.surfaceElevated
              : iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
