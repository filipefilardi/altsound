import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/play_pill.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/download_preferences.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';
import '../downloads/widgets/playlist_download_button.dart';
import '../player/current_track_playlist_presence.dart';
import '../player/now_playing_favorite.dart';
import '../player/player_providers.dart';
import '../player/widgets/add_track_to_playlist_sheet.dart';
import '../player/widgets/mini_player_slot.dart';
import '../player/widgets/playing_track_leading.dart';
import '../player/widgets/track_more_menu_button.dart';
import 'playlist_providers.dart';

/// Album on each track row is shown when width is at or above this (phone vs tablet / landscape).
const double _kPlaylistShowAlbumWidthBreakpoint = 600;

enum _SelectionBulkAction { addToLiked, addToPlaylist, removeFromPlaylist }

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final Set<String> _selectedTrackIds = {};
  static const _emptySelection = <String>{};

  bool get _inSelection => _selectedTrackIds.isNotEmpty;

  void _clearSelection() {
    if (_selectedTrackIds.isEmpty) return;
    setState(() => _selectedTrackIds.clear());
  }

  void _toggleTrackSelected(String id) {
    setState(() {
      if (_selectedTrackIds.contains(id)) {
        _selectedTrackIds.remove(id);
      } else {
        _selectedTrackIds.add(id);
      }
    });
  }

  void _onLongPressStartSelection(String id) {
    setState(() {
      _selectedTrackIds.add(id);
    });
  }

  Future<void> _showSelectionActionsMenu(
    BuildContext context, {
    required String playlistId,
  }) async {
    if (_selectedTrackIds.isEmpty) return;
    final count = _selectedTrackIds.length;
    final action = await showModalBottomSheet<_SelectionBulkAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.favorite_rounded,
                color: AppColors.like,
              ),
              title: const Text('Add to liked songs'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_SelectionBulkAction.addToLiked),
            ),
            ListTile(
              leading: const Icon(
                Icons.playlist_add_rounded,
                color: AppColors.primary,
              ),
              title: const Text('Add to another playlist'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_SelectionBulkAction.addToPlaylist),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_rounded),
              title: const Text('Remove from this playlist'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_SelectionBulkAction.removeFromPlaylist),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final ids = Set<String>.from(_selectedTrackIds);
    switch (action) {
      case _SelectionBulkAction.addToLiked:
        await _bulkAddToLikedSongs(context, ids, onDone: _clearSelection);
      case _SelectionBulkAction.addToPlaylist:
        await _showBulkAddToPlaylistDialog(
          context,
          currentPlaylistId: playlistId,
          trackIds: ids,
          onDone: _clearSelection,
        );
      case _SelectionBulkAction.removeFromPlaylist:
        await _confirmBulkRemove(
          context,
          playlistId: playlistId,
          count: count,
          trackIds: ids,
          onDone: _clearSelection,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistId = widget.playlistId;
    final async = ref.watch(playlistProvider(playlistId));
    final downloads = ref.watch(downloadManagerProvider);

    ref.listen(playlistProvider(playlistId), (prev, next) {
      if (prev?.value == null && next.value != null) {
        final prefs = ref.read(downloadPreferencesProvider);
        if (prefs.autoDownload && prefs.isPlaylistSubscribed(next.value!.id)) {
          ref
              .read(downloadManagerProvider.notifier)
              .enqueuePlaylist(next.value!);
        }
      }
    });

    return PopScope(
      canPop: !_inSelection,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _clearSelection();
      },
      child: Scaffold(
        appBar: _inSelection
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSelection,
                ),
                title: Text('${_selectedTrackIds.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showSelectionActionsMenu(
                      context,
                      playlistId: playlistId,
                    ),
                  ),
                ],
              )
            : AppBar(title: const Text('Playlist')),
        bottomNavigationBar: const MiniPlayerSlot(
          withTopDivider: true,
          reserveSpaceWhenEmpty: true,
        ),
        body: async.when(
          loading: () {
            final offlinePlaylist = _buildOfflinePlaylist(
              playlistId,
              downloads,
            );
            if (offlinePlaylist != null) {
              return _PlaylistView(
                playlist: offlinePlaylist,
                selectedTrackIds: _emptySelection,
                inSelection: false,
                onLongPress: (_) {},
                onToggleSelected: (_) {},
              );
            }
            return const _PlaylistLoading();
          },
          error: (e, _) {
            final offlinePlaylist = _buildOfflinePlaylist(
              playlistId,
              downloads,
            );
            if (offlinePlaylist != null) {
              return _PlaylistView(
                playlist: offlinePlaylist,
                selectedTrackIds: _emptySelection,
                inSelection: false,
                onLongPress: (_) {},
                onToggleSelected: (_) {},
              );
            }
            return ErrorStateView(
              title: "Couldn't load this playlist",
              message: e.toString(),
              onRetry: () => ref.invalidate(playlistProvider(playlistId)),
            );
          },
          data: (playlist) => _PlaylistView(
            playlist: playlist,
            selectedTrackIds: _selectedTrackIds,
            inSelection: _inSelection,
            onLongPress: _onLongPressStartSelection,
            onToggleSelected: _toggleTrackSelected,
            onRename: _isLikedSongsPlaylist(playlist)
                ? null
                : () => _renamePlaylist(context, ref, playlist),
            onDelete: _isLikedSongsPlaylist(playlist)
                ? null
                : () => _confirmDelete(context, ref, playlist),
          ),
        ),
      ),
    );
  }

  static PlaylistDetail? _buildOfflinePlaylist(
    String playlistId,
    DownloadsState downloads,
  ) {
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

  Future<void> _renamePlaylist(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePlaylistDialog(initialName: playlist.name),
    );
    final playlistName = name?.trim() ?? '';
    if (playlistName.isEmpty || playlistName == playlist.name.trim()) return;

    try {
      await ref
          .read(jellyfinRepositoryProvider)
          .renamePlaylist(playlistId: playlist.id, name: playlistName);
      await ref
          .read(downloadManagerProvider.notifier)
          .renamePlaylist(playlist.id, playlistName);
      ref.invalidate(playlistProvider(playlist.id));
      ref.invalidate(playlistsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Renamed to "$playlistName"')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename playlist: $e')));
    }
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
    ref.invalidate(playlistsProvider);
    if (!context.mounted) return;
    context.pop();
  }

  Future<void> _bulkAddToLikedSongs(
    BuildContext context,
    Set<String> trackIds, {
    required VoidCallback onDone,
  }) async {
    if (trackIds.isEmpty) return;
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      for (final id in trackIds) {
        await repo.setFavorite(id, favorite: true);
        await repo.addTrackToLikedSongs(id);
      }
      final liked = await repo.likedSongsPlaylist();
      if (liked != null) {
        ref.invalidate(playlistProvider(liked.id));
      }
      ref.invalidate(currentTrackPlaylistPresenceProvider);
      ref.invalidate(nowPlayingFavoriteProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trackIds.length == 1
                  ? 'Added 1 song to liked songs'
                  : 'Added ${trackIds.length} songs to liked songs',
            ),
          ),
        );
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add to liked songs: $e')),
        );
      }
    }
  }

  Future<void> _showBulkAddToPlaylistDialog(
    BuildContext context, {
    required String currentPlaylistId,
    required Set<String> trackIds,
    required VoidCallback onDone,
  }) async {
    if (trackIds.isEmpty) return;
    final repo = ref.read(jellyfinRepositoryProvider);
    final liked = await repo.likedSongsPlaylist();
    var lists = await repo.playlists();
    lists = lists
        .where((p) => p.id != currentPlaylistId && p.id != (liked?.id))
        .toList();
    if (!context.mounted) return;

    final canPickLiked = liked != null && liked.id != currentPlaylistId;
    final chosen = await showModalBottomSheet<BrowseItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        if (lists.isEmpty && !canPickLiked) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No other playlists. Create one from the Library tab.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return SafeArea(
          child: ListView(
            children: [
              if (canPickLiked)
                ListTile(
                  leading: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.like,
                  ),
                  title: const Text('Liked songs'),
                  onTap: () => Navigator.of(sheetContext).pop(liked),
                ),
              ...lists.map(
                (p) => ListTile(
                  leading: const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(p),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (chosen == null || !context.mounted) return;
    final targetId = chosen.id;
    try {
      for (final id in trackIds) {
        if (liked != null && targetId == liked.id) {
          await repo.setFavorite(id, favorite: true);
        }
        await repo.addTrackToPlaylist(trackId: id, playlistId: targetId);
      }
      ref.invalidate(playlistProvider(targetId));
      if (liked != null && targetId == liked.id) {
        ref.invalidate(currentTrackPlaylistPresenceProvider);
        ref.invalidate(nowPlayingFavoriteProvider);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Added to "${chosen.name}"')));
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add to playlist: $e')),
        );
      }
    }
  }

  Future<void> _confirmBulkRemove(
    BuildContext context, {
    required String playlistId,
    required int count,
    required Set<String> trackIds,
    required VoidCallback onDone,
  }) async {
    if (count == 0) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from playlist?'),
        content: Text(
          count == 1
              ? 'Remove 1 song from this playlist?'
              : 'Remove $count songs from this playlist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      for (final id in trackIds) {
        final entry = await repo.playlistEntryIdForTrack(
          playlistId: playlistId,
          trackId: id,
        );
        if (entry != null) {
          await repo.removeTrackFromPlaylistByEntry(
            playlistId: playlistId,
            playlistItemEntryId: entry,
          );
        }
      }
      ref.invalidate(playlistProvider(playlistId));
      ref.invalidate(currentTrackPlaylistPresenceProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 1 ? 'Removed 1 song' : 'Removed $count songs',
            ),
          ),
        );
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }
}

bool _isLikedSongsPlaylist(PlaylistDetail playlist) {
  return playlist.name.toLowerCase().trim() == 'liked songs';
}

class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}

class _PlaylistView extends ConsumerWidget {
  const _PlaylistView({
    required this.playlist,
    required this.selectedTrackIds,
    required this.inSelection,
    required this.onLongPress,
    required this.onToggleSelected,
    this.onRename,
    this.onDelete,
  });

  final PlaylistDetail playlist;
  final Set<String> selectedTrackIds;
  final bool inSelection;
  final void Function(String trackId) onLongPress;
  final void Function(String trackId) onToggleSelected;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(playlistProvider(playlist.id).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _PlaylistHeader(playlist: playlist),
          const SizedBox(height: 16),
          _ActionRow(
            playlist: playlist,
            selectionActive: inSelection,
            onRename: onRename,
            onDelete: onDelete,
          ),
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
                contextId: playlist.id,
                inSelection: inSelection,
                isSelected: selectedTrackIds.contains(entry.value.id),
                onLongPress: () => onLongPress(entry.value.id),
                onToggleSelected: () => onToggleSelected(entry.value.id),
              ),
            ),
        ],
      ),
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
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
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
  const _ActionRow({
    required this.playlist,
    this.selectionActive = false,
    this.onRename,
    this.onDelete,
  });

  final PlaylistDetail playlist;
  final bool selectionActive;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    final playbackState = ref.watch(playbackStateProvider).value;
    final currentMediaItem = ref.watch(currentMediaItemProvider).value;
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final isPlaylistPlaying =
        playbackState?.playing == true &&
        (currentMediaItem?.extras?['contextId'] as String?) == playlist.id;
    final hasTracks = playlist.tracks.isNotEmpty;
    final enabled = hasTracks && !selectionActive;
    final canOpenMore =
        !selectionActive && (hasTracks || onRename != null || onDelete != null);

    return Opacity(
      opacity: selectionActive ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: selectionActive,
        child: Row(
          children: [
            PlayPill(
              onTap: enabled
                  ? () {
                      if (isPlaylistPlaying) {
                        controller.togglePlay();
                        return;
                      }
                      controller.playTracks(
                        playlist.tracks,
                        contextId: playlist.id,
                      );
                    }
                  : null,
              icon: isPlaylistPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              tooltip: isPlaylistPlaying ? 'Pause' : 'Play',
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Shuffle',
              icon: Icon(
                Icons.shuffle_rounded,
                color: shuffleEnabled
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              onPressed: enabled ? () => controller.toggleShuffle() : null,
            ),
            PlaylistDownloadButton(playlist: playlist),
            IconButton(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: canOpenMore
                  ? () async {
                      final action =
                          await showModalBottomSheet<_PlaylistCollectionAction>(
                            context: context,
                            showDragHandle: true,
                            builder: (sheetContext) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasTracks) ...[
                                    ListTile(
                                      leading: const Icon(
                                        Icons.playlist_add_rounded,
                                      ),
                                      title: const Text('Add to playlist'),
                                      onTap: () =>
                                          Navigator.of(sheetContext).pop(
                                            _PlaylistCollectionAction
                                                .addToPlaylist,
                                          ),
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.add_to_queue_rounded,
                                      ),
                                      title: const Text('Add to queue'),
                                      onTap: () =>
                                          Navigator.of(sheetContext).pop(
                                            _PlaylistCollectionAction
                                                .addToQueue,
                                          ),
                                    ),
                                  ],
                                  if (onRename != null || onDelete != null) ...[
                                    if (hasTracks) const Divider(height: 1),
                                  ],
                                  if (onRename != null) ...[
                                    ListTile(
                                      leading: const Icon(Icons.edit_rounded),
                                      title: const Text('Rename playlist'),
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(_PlaylistCollectionAction.rename),
                                    ),
                                  ],
                                  if (onDelete != null) ...[
                                    ListTile(
                                      leading: const Icon(
                                        Icons.delete_rounded,
                                        color: AppColors.error,
                                      ),
                                      title: const Text('Delete playlist'),
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(_PlaylistCollectionAction.delete),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                      if (action == null || !context.mounted) return;
                      switch (action) {
                        case _PlaylistCollectionAction.addToPlaylist:
                          await openAddTracksToPlaylistFlow(
                            context,
                            ref,
                            trackIds: playlist.tracks.map((t) => t.id).toList(),
                          );
                        case _PlaylistCollectionAction.addToQueue:
                          final added = await controller.addTracksToQueue(
                            playlist.tracks,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added $added song${added == 1 ? '' : 's'} to queue',
                              ),
                            ),
                          );
                        case _PlaylistCollectionAction.delete:
                          onDelete?.call();
                        case _PlaylistCollectionAction.rename:
                          onRename?.call();
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistCollectionAction { addToPlaylist, addToQueue, rename, delete }

class _ArtFallback extends StatelessWidget {
  const _ArtFallback();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: AppColors.textTertiary,
          size: 40,
        ),
      ),
    );
  }
}

class _PlaylistTrackTile extends ConsumerWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.index,
    required this.allTracks,
    required this.contextId,
    required this.inSelection,
    required this.isSelected,
    required this.onLongPress,
    required this.onToggleSelected,
  });

  final Track track;
  final int index;
  final List<Track> allTracks;
  final String contextId;
  final bool inSelection;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showAlbumLine =
        MediaQuery.sizeOf(context).width >= _kPlaylistShowAlbumWidthBreakpoint;
    final hasAlbum =
        showAlbumLine && track.albumName != null && track.albumName!.isNotEmpty;
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      isThreeLine: inSelection || hasAlbum,
      onLongPress: onLongPress,
      onTap: () {
        if (inSelection) {
          onToggleSelected();
          return;
        }
        final isCurrentInContext =
            current != null &&
            current.extras?['jellyfinId'] == track.id &&
            current.extras?['contextId'] == contextId;
        if (isCurrentInContext) {
          context.push('/now-playing');
          return;
        }
        ref
            .read(playerControllerProvider)
            .playTracks(
              allTracks,
              startIndex: index,
              contextId: contextId,
              selectedTrack: true,
            );
      },
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      leading: inSelection
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelected(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            )
          : PlayingTrackLeading(
              jellyfinTrackId: track.id,
              indexLabel: '${index + 1}',
            ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent && !inSelection
              ? AppColors.primary
              : AppColors.textPrimary,
          fontWeight: isCurrent && !inSelection
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: inSelection
                ? null
                : (track.artistId == null || track.artistId!.isEmpty
                      ? null
                      : () => context.push('/artist/${track.artistId}')),
            child: Text(
              track.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: inSelection
                    ? AppColors.textSecondary
                    : (track.artistId == null || track.artistId!.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.primary),
                fontSize: 12,
              ),
            ),
          ),
          if (hasAlbum) ...[
            const SizedBox(height: 2),
            InkWell(
              onTap: inSelection
                  ? null
                  : (track.albumId == null || track.albumId!.isEmpty
                        ? null
                        : () => context.push('/album/${track.albumId}')),
              child: Text(
                track.albumName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: inSelection
                      ? AppColors.textTertiary
                      : (track.albumId == null || track.albumId!.isEmpty
                            ? AppColors.textSecondary
                            : AppColors.primary),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: inSelection
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloaded)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.download_for_offline_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
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
