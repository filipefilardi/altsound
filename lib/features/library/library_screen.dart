import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/adaptive_breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/header_action_buttons.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../playlist/playlist_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: LibraryContent());
  }
}

class LibraryContent extends ConsumerWidget {
  const LibraryContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likedSongsAsync = ref.watch(likedSongsPlaylistProvider);
    final playlistsAsync = ref.watch(playlistsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(likedSongsPlaylistProvider);
        ref.invalidate(playlistsProvider);
        await Future.wait([
          ref.read(likedSongsPlaylistProvider.future),
          ref.read(playlistsProvider.future),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            sliver: const SliverToBoxAdapter(child: _LibraryHeader()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            sliver: SliverToBoxAdapter(
              child: _LibraryCategories(
                onAlbums: () => context.push('/library/albums'),
                onArtists: () => context.push('/library/artists'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _PlaylistsHeader(
              onCreatePlaylist: () => _createPlaylist(context, ref),
            ),
          ),
          playlistsAsync.when<Widget>(
            loading: () =>
                const SliverToBoxAdapter(child: _LibraryLoadingRows()),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load playlists: $e',
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
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

              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 96),
                sliver: SliverList.list(
                  children: [
                    _SectionTile(
                      icon: Icons.favorite_rounded,
                      iconColor: AppColors.error,
                      title: 'Liked Songs',
                      subtitle: liked == null
                          ? 'Playlist'
                          : _playlistSubtitle(liked.childCount),
                      onTap: () => _openLikedSongs(context, ref),
                    ),
                    ...rest.map(
                      (playlist) => _SectionTile(
                        icon: Icons.queue_music_rounded,
                        title: playlist.name,
                        subtitle: _playlistSubtitle(playlist.childCount),
                        onTap: () => context.push('/playlist/${playlist.id}'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openLikedSongs(BuildContext context, WidgetRef ref) async {
    final playlist = await ref
        .read(jellyfinRepositoryProvider)
        .likedSongsPlaylist();
    if (playlist == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Like any song to create your Liked Songs playlist.'),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    context.push('/playlist/${playlist.id}');
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
    ref.invalidate(playlistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$playlistName" created')));
  }
}

String _playlistSubtitle(int? count) {
  if (count == null) return 'Playlist';
  if (count == 1) return 'Playlist · 1 song';
  return 'Playlist · $count songs';
}

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

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Your Library',
            style: Theme.of(context).textTheme.headlineMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isDesktopLayout(context)) const HeaderActionButtons(),
      ],
    );
  }
}

class _LibraryCategories extends StatelessWidget {
  const _LibraryCategories({required this.onAlbums, required this.onArtists});

  final VoidCallback onAlbums;
  final VoidCallback onArtists;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LibraryCategoryCard(
            icon: Icons.album_rounded,
            label: 'Albums',
            onTap: onAlbums,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LibraryCategoryCard(
            icon: Icons.person_rounded,
            label: 'Artists',
            onTap: onArtists,
          ),
        ),
      ],
    );
  }
}

class _LibraryCategoryCard extends StatelessWidget {
  const _LibraryCategoryCard({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const iconColor = AppColors.textPrimary;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistsHeader extends StatelessWidget {
  const _PlaylistsHeader({required this.onCreatePlaylist});

  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'PLAYLISTS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            onPressed: onCreatePlaylist,
            icon: const Icon(Icons.add_rounded, size: 20),
            color: AppColors.primary,
            visualDensity: VisualDensity.compact,
            tooltip: 'New playlist',
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
    this.iconColor = AppColors.textPrimary,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor == AppColors.textPrimary
                        ? AppColors.surfaceHighlight
                        : iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
