import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
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
    final isOffline = ref.watch(isOfflineProvider);
    final downloads = ref.watch(downloadManagerProvider);

    if (isOffline) {
      final offlinePlaylists =
          downloads.playlists.values
              .where(
                (playlist) => playlist.trackIds.any(downloads.isDownloaded),
              )
              .toList()
            ..sort(
              (a, b) => a.name.trim().toLowerCase().compareTo(
                b.name.trim().toLowerCase(),
              ),
            );

      return RefreshIndicator(
        onRefresh: () async {},
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
                onCreatePlaylist: () => showAppSnackBar(
                  context,
                  'Connect to the internet to create playlists.',
                ),
              ),
            ),
            if (offlinePlaylists.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Text(
                    'No downloaded playlist songs yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                sliver: SliverList.list(
                  children: offlinePlaylists.map((playlist) {
                    final downloadedCount = playlist.trackIds
                        .where(downloads.isDownloaded)
                        .length;
                    final totalCount = playlist.trackIds.length;
                    return SectionTile(
                      icon: PiconsRegular.queue,
                      title: playlist.name,
                      subtitle: _offlinePlaylistSubtitle(
                        downloadedCount,
                        totalCount,
                      ),
                      onTap: () => context.push('/playlist/${playlist.id}'),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      );
    }

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
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
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
    final likedFromProvider = ref.read(likedSongsPlaylistProvider).value;
    if (likedFromProvider != null) {
      if (!context.mounted) return;
      context.push('/playlist/${likedFromProvider.id}');
      return;
    }

    final downloads = ref.read(downloadManagerProvider);
    String? cachedLikedId;
    for (final playlist in downloads.playlists.values) {
      if (playlist.name.toLowerCase().trim() != 'liked songs') continue;
      if (playlist.trackIds.any(downloads.isDownloaded)) {
        cachedLikedId = playlist.id;
        break;
      }
    }
    if (cachedLikedId != null) {
      if (!context.mounted) return;
      context.push('/playlist/$cachedLikedId');
      return;
    }

    try {
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
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Could not open Liked Songs right now. If you downloaded songs from it, try again offline.',
      );
    }
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

String _offlinePlaylistSubtitle(int downloadedCount, int totalCount) {
  final downloadedText = downloadedCount == 1
      ? '1 song downloaded'
      : '$downloadedCount songs downloaded';
  if (totalCount <= downloadedCount) return 'Playlist · $downloadedText';
  return 'Playlist · $downloadedText of $totalCount';
}
