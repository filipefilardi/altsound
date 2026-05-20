import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/library/widgets/library_categories.dart';
import 'package:altsound/features/library/widgets/library_header.dart';
import 'package:altsound/features/library/widgets/library_loading_rows.dart';
import 'package:altsound/features/library/widgets/playlists_header.dart';
import 'package:altsound/features/library/widgets/section_tile.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            sliver: const SliverToBoxAdapter(child: LibraryHeader()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: LibraryCategories(
                onAlbums: () => context.push('/library/albums'),
                onArtists: () => context.push('/library/artists'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: PlaylistsHeader(
              onCreatePlaylist: () => _createPlaylist(context, ref),
            ),
          ),
          playlistsAsync.when<Widget>(
            loading: () =>
                const SliverToBoxAdapter(child: LibraryLoadingRows()),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
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
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.lg,
                ),
                sliver: SliverList.list(
                  children: [
                    SectionTile(
                      icon: PiconsRegular.heart,
                      iconColor: AppColors.error,
                      title: 'Liked Songs',
                      subtitle: liked == null
                          ? 'Playlist'
                          : _playlistSubtitle(liked.childCount),
                      onTap: () => _openLikedSongs(context, ref),
                    ),
                    ...rest.map(
                      (playlist) => SectionTile(
                        icon: PiconsRegular.queue,
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
      showAppSnackBar(
        context,
        'Like any song to create your Liked Songs playlist.',
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
    showAppSnackBar(context, '"$playlistName" created');
  }
}

String _playlistSubtitle(int? count) {
  if (count == null) return 'Playlist';
  if (count == 1) return 'Playlist · 1 song';
  return 'Playlist · $count songs';
}
