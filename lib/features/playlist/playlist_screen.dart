import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/downloads/widgets/playlist_download_button.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/now_playing_favorite.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/player/widgets/playing_track_leading.dart';
import 'package:altsound/features/player/widgets/track_listing_widgets.dart';
import 'package:altsound/features/player/widgets/track_more_menu_button.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';

enum _SelectionBulkAction {
  addToLiked,
  addToPlaylist,
  moveToTop,
  moveToBottom,
  removeFromPlaylist,
}

enum _PlaylistSort { custom, title, artist, album, dateAdded }

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final _filterController = TextEditingController();
  final Set<String> _selectedTrackIds = {};
  _PlaylistSort _activeSort = _PlaylistSort.custom;
  bool _sortDescending = false;
  bool _selectionMode = false;
  String _filterQuery = '';
  static const _emptySelection = <String>{};

  bool get _inSelection => _selectionMode;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() {
        _filterQuery = _filterController.text.trim();
        if (_selectedTrackIds.isNotEmpty) {
          final visibleIds = ref
              .read(playlistProvider(widget.playlistId))
              .maybeWhen(
                data: (playlist) => _visiblePlaylistTracks(
                  playlist.tracks,
                ).map((track) => track.id).toSet(),
                orElse: () => const <String>{},
              );
          _selectedTrackIds.removeWhere((id) => !visibleIds.contains(id));
        }
      });
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _clearSelection() {
    if (!_selectionMode && _selectedTrackIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  void _toggleTrackSelected(String id) {
    setState(() {
      _selectionMode = true;
      if (_selectedTrackIds.contains(id)) {
        _selectedTrackIds.remove(id);
      } else {
        _selectedTrackIds.add(id);
      }
    });
  }

  void _onLongPressStartSelection(String id) {
    setState(() {
      _selectionMode = true;
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
              leading: const Icon(Icons.vertical_align_top_rounded),
              title: const Text('Move to top'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_SelectionBulkAction.moveToTop),
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom_rounded),
              title: const Text('Move to bottom'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_SelectionBulkAction.moveToBottom),
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
      case _SelectionBulkAction.moveToTop:
        await _moveSelectedTracks(
          context,
          playlistId: playlistId,
          trackIds: ids,
          moveToTop: true,
          onDone: _clearSelection,
        );
      case _SelectionBulkAction.moveToBottom:
        await _moveSelectedTracks(
          context,
          playlistId: playlistId,
          trackIds: ids,
          moveToTop: false,
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
    final visibleForSelection = async.maybeWhen(
      data: (playlist) => _visiblePlaylistTracks(playlist.tracks),
      orElse: () => const <Track>[],
    );
    final visibleSelectedCount = visibleForSelection
        .where((track) => _selectedTrackIds.contains(track.id))
        .length;
    final allVisibleSelected =
        visibleForSelection.isNotEmpty &&
        visibleSelectedCount == visibleForSelection.length;
    final someVisibleSelected = visibleSelectedCount > 0;

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
                leadingWidth: 104,
                leading: Row(
                  children: [
                    const SizedBox(width: 4),
                    _SelectionToolbarButton(
                      tooltip: 'Clear selection',
                      icon: Icons.close_rounded,
                      onPressed: _clearSelection,
                    ),
                    _SelectionToolbarButton(
                      tooltip: someVisibleSelected
                          ? 'Clear visible selection'
                          : 'Select visible songs',
                      icon: allVisibleSelected
                          ? Icons.check_box_rounded
                          : someVisibleSelected
                          ? Icons.indeterminate_check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      onPressed: visibleForSelection.isEmpty
                          ? null
                          : () {
                              setState(() {
                                if (someVisibleSelected) {
                                  for (final track in visibleForSelection) {
                                    _selectedTrackIds.remove(track.id);
                                  }
                                } else {
                                  _selectedTrackIds.addAll(
                                    visibleForSelection.map(
                                      (track) => track.id,
                                    ),
                                  );
                                }
                              });
                            },
                    ),
                  ],
                ),
                title: Text('${_selectedTrackIds.length} selected'),
                actions: [
                  _SelectionToolbarButton(
                    tooltip: 'More',
                    icon: Icons.more_horiz_rounded,
                    onPressed: _selectedTrackIds.isEmpty
                        ? null
                        : () => _showSelectionActionsMenu(
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
                visibleTracks: _visiblePlaylistTracks(offlinePlaylist.tracks),
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
                visibleTracks: _visiblePlaylistTracks(offlinePlaylist.tracks),
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
            visibleTracks: _visiblePlaylistTracks(playlist.tracks),
            filterController: _filterController,
            filterQuery: _filterQuery,
            selectedTrackIds: _selectedTrackIds,
            inSelection: _inSelection,
            onLongPress: _onLongPressStartSelection,
            onToggleSelected: _toggleTrackSelected,
            onSort: () => _showSortPlaylistSheet(context, ref, playlist),
            onEdit: () => _editPlaylistOrder(context, ref, playlist),
            duplicateCount: _duplicatePlaylistEntries(playlist.tracks).length,
            onRemoveDuplicates: () =>
                _confirmRemoveDuplicates(context, ref, playlist),
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

  List<Track> _visiblePlaylistTracks(List<Track> tracks) {
    final sorted = _sortedPlaylistTracks(
      tracks,
      _activeSort,
      descending: _sortDescending,
    );
    if (_filterQuery.isEmpty) return sorted;
    return sorted
        .where(
          (track) => searchMatches(_filterQuery, [
            track.name,
            track.artistName,
            track.albumName,
          ]),
        )
        .toList();
  }

  Future<void> _showSortPlaylistSheet(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    if (playlist.tracks.isEmpty) return;
    final sort = await showModalBottomSheet<_PlaylistSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlaylistSortTile(
              icon: Icons.format_list_numbered_rounded,
              title: 'Custom order',
              subtitle: 'Playlist order',
              selected: _activeSort == _PlaylistSort.custom,
              directional: false,
              onTap: () => Navigator.of(sheetContext).pop(_PlaylistSort.custom),
            ),
            const Divider(height: 1),
            _PlaylistSortTile(
              icon: Icons.title_rounded,
              title: 'Title',
              selected: _activeSort == _PlaylistSort.title,
              descending: _activeSort == _PlaylistSort.title && _sortDescending,
              subtitle: _sortSubtitle(
                _PlaylistSort.title,
                selected: _activeSort == _PlaylistSort.title,
                descending: _sortDescending,
              ),
              onTap: () => Navigator.of(sheetContext).pop(_PlaylistSort.title),
            ),
            _PlaylistSortTile(
              icon: Icons.person_rounded,
              title: 'Artist',
              selected: _activeSort == _PlaylistSort.artist,
              descending:
                  _activeSort == _PlaylistSort.artist && _sortDescending,
              subtitle: _sortSubtitle(
                _PlaylistSort.artist,
                selected: _activeSort == _PlaylistSort.artist,
                descending: _sortDescending,
              ),
              onTap: () => Navigator.of(sheetContext).pop(_PlaylistSort.artist),
            ),
            _PlaylistSortTile(
              icon: Icons.album_rounded,
              title: 'Album',
              selected: _activeSort == _PlaylistSort.album,
              descending: _activeSort == _PlaylistSort.album && _sortDescending,
              subtitle: _sortSubtitle(
                _PlaylistSort.album,
                selected: _activeSort == _PlaylistSort.album,
                descending: _sortDescending,
              ),
              onTap: () => Navigator.of(sheetContext).pop(_PlaylistSort.album),
            ),
            _PlaylistSortTile(
              icon: Icons.calendar_today_rounded,
              title: 'Date added',
              selected: _activeSort == _PlaylistSort.dateAdded,
              descending:
                  _activeSort == _PlaylistSort.dateAdded && _sortDescending,
              subtitle: _sortSubtitle(
                _PlaylistSort.dateAdded,
                selected: _activeSort == _PlaylistSort.dateAdded,
                descending: _sortDescending,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_PlaylistSort.dateAdded),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (sort == null || !context.mounted) return;
    setState(() {
      if (sort == _PlaylistSort.custom) {
        _activeSort = _PlaylistSort.custom;
        _sortDescending = false;
        return;
      }
      _sortDescending = _activeSort == sort ? !_sortDescending : false;
      _activeSort = sort;
    });
  }

  Future<void> _editPlaylistOrder(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    if (playlist.tracks.isEmpty) return;
    final ordered = await showModalBottomSheet<List<Track>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _PlaylistOrderEditor(tracks: playlist.tracks),
      ),
    );
    if (ordered == null || !context.mounted) return;
    final updated = await _applyPlaylistOrder(
      context,
      ref,
      playlist: playlist,
      orderedTracks: ordered,
      successMessage: 'Playlist order updated',
    );
    if (updated && mounted) {
      setState(() {
        _activeSort = _PlaylistSort.custom;
        _sortDescending = false;
      });
    }
  }

  Future<bool> _applyPlaylistOrder(
    BuildContext context,
    WidgetRef ref, {
    required PlaylistDetail playlist,
    List<Track>? currentTracks,
    required List<Track> orderedTracks,
    required String successMessage,
  }) async {
    final currentIds = (currentTracks ?? playlist.tracks)
        .map((t) => t.playlistItemId)
        .toList();
    final orderedIds = orderedTracks.map((t) => t.playlistItemId).toList();
    if (currentIds.length != orderedIds.length ||
        orderedIds.any((id) => id == null || id.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reorder this playlist. Refresh and try again.',
          ),
        ),
      );
      return false;
    }
    if (_sameStringOrder(currentIds, orderedIds)) return true;

    final currentOrder = currentIds.cast<String>().toList();
    final targetOrder = orderedIds.cast<String>().toList();
    final repo = ref.read(jellyfinRepositoryProvider);
    try {
      for (var index = 0; index < targetOrder.length; index++) {
        final playlistItemId = targetOrder[index];
        final currentIndex = currentOrder.indexOf(playlistItemId);
        if (currentIndex == -1 || currentIndex == index) continue;
        await repo.movePlaylistItem(
          playlistId: playlist.id,
          playlistItemId: playlistItemId,
          newIndex: index,
        );
        currentOrder
          ..removeAt(currentIndex)
          ..insert(index, playlistItemId);
      }
      await ref
          .read(downloadManagerProvider.notifier)
          .reorderPlaylist(
            playlist.id,
            orderedTracks.map((t) => t.id).toList(),
          );
      ref.invalidate(playlistProvider(playlist.id));
      if (!context.mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update playlist order: $e')),
      );
      return false;
    }
  }

  Future<void> _moveSelectedTracks(
    BuildContext context, {
    required String playlistId,
    required Set<String> trackIds,
    required bool moveToTop,
    required VoidCallback onDone,
  }) async {
    if (trackIds.isEmpty) return;
    final playlist = ref
        .read(playlistProvider(playlistId))
        .maybeWhen(data: (playlist) => playlist, orElse: () => null);
    final detail =
        playlist ??
        await ref.read(jellyfinRepositoryProvider).playlist(playlistId);
    if (!mounted || !context.mounted) return;
    final selected = <Track>[];
    final others = <Track>[];
    for (final track in detail.tracks) {
      if (trackIds.contains(track.id)) {
        selected.add(track);
      } else {
        others.add(track);
      }
    }
    final ordered = moveToTop
        ? [...selected, ...others]
        : [...others, ...selected];
    final updated = await _applyPlaylistOrder(
      context,
      ref,
      playlist: detail,
      orderedTracks: ordered,
      successMessage: moveToTop
          ? 'Moved ${selected.length} song${selected.length == 1 ? '' : 's'} to top'
          : 'Moved ${selected.length} song${selected.length == 1 ? '' : 's'} to bottom',
    );
    if (updated && context.mounted) onDone();
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
      var addedCount = 0;
      var skippedCount = 0;
      for (final id in trackIds) {
        if (liked != null && targetId == liked.id) {
          await repo.setFavorite(id, favorite: true);
        }
        final added = await repo.addTrackToPlaylist(
          trackId: id,
          playlistId: targetId,
        );
        if (added) {
          addedCount++;
        } else {
          skippedCount++;
        }
      }
      ref.invalidate(playlistProvider(targetId));
      if (liked != null && targetId == liked.id) {
        ref.invalidate(currentTrackPlaylistPresenceProvider);
        ref.invalidate(nowPlayingFavoriteProvider);
      }
      if (context.mounted) {
        final skippedText = skippedCount == 0
            ? ''
            : ' · $skippedCount duplicate${skippedCount == 1 ? '' : 's'} skipped';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $addedCount song${addedCount == 1 ? '' : 's'} to "${chosen.name}"$skippedText',
            ),
          ),
        );
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

  Future<void> _confirmRemoveDuplicates(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail playlist,
  ) async {
    final duplicates = _duplicatePlaylistEntries(playlist.tracks);
    if (duplicates.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove duplicates?'),
        content: Text(
          'Remove ${duplicates.length} duplicate song${duplicates.length == 1 ? '' : 's'} from "${playlist.name}"? The first copy of each song stays.',
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
      for (final track in duplicates) {
        final entryId = track.playlistItemId;
        if (entryId == null || entryId.isEmpty) continue;
        await repo.removeTrackFromPlaylistByEntry(
          playlistId: playlist.id,
          playlistItemEntryId: entryId,
        );
      }
      ref.invalidate(playlistProvider(playlist.id));
      ref.invalidate(currentTrackPlaylistPresenceProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${duplicates.length} duplicate${duplicates.length == 1 ? '' : 's'}',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove duplicates: $e')),
      );
    }
  }
}

bool _isLikedSongsPlaylist(PlaylistDetail playlist) {
  return playlist.name.toLowerCase().trim() == 'liked songs';
}

List<Track> _duplicatePlaylistEntries(List<Track> tracks) {
  final seen = <String>{};
  final duplicates = <Track>[];
  for (final track in tracks) {
    if (seen.add(track.id)) continue;
    if (track.playlistItemId != null && track.playlistItemId!.isNotEmpty) {
      duplicates.add(track);
    }
  }
  return duplicates;
}

bool _sameStringOrder(List<String?> a, List<String?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<Track> _sortedPlaylistTracks(
  List<Track> tracks,
  _PlaylistSort sort, {
  required bool descending,
}) {
  final sorted = List<Track>.from(tracks);
  switch (sort) {
    case _PlaylistSort.custom:
      return sorted;
    case _PlaylistSort.title:
      sorted.sort(
        (a, b) => _compareStrings(
          a.name,
          b.name,
        ).ifEqual(_compareStrings(a.id, b.id)),
      );
    case _PlaylistSort.artist:
      sorted.sort(
        (a, b) => _compareStrings(a.artistName, b.artistName)
            .ifEqual(_compareStrings(a.name, b.name))
            .ifEqual(_compareStrings(a.id, b.id)),
      );
    case _PlaylistSort.album:
      sorted.sort(
        (a, b) => _compareStrings(a.albumName ?? '', b.albumName ?? '')
            .ifEqual(_compareNullableInts(a.discNumber, b.discNumber))
            .ifEqual(_compareNullableInts(a.trackNumber, b.trackNumber))
            .ifEqual(_compareStrings(a.name, b.name))
            .ifEqual(_compareStrings(a.id, b.id)),
      );
    case _PlaylistSort.dateAdded:
      sorted.sort(
        (a, b) => _compareNullableDates(a.dateAdded, b.dateAdded)
            .ifEqual(_compareStrings(a.name, b.name))
            .ifEqual(_compareStrings(a.id, b.id)),
      );
  }
  if (descending) {
    return sorted.reversed.toList();
  }
  return sorted;
}

String _sortSubtitle(
  _PlaylistSort sort, {
  required bool selected,
  required bool descending,
}) {
  switch (sort) {
    case _PlaylistSort.custom:
      return 'Playlist order';
    case _PlaylistSort.title:
    case _PlaylistSort.artist:
    case _PlaylistSort.album:
      if (!selected) return 'A-Z';
      return descending ? 'Z-A' : 'A-Z';
    case _PlaylistSort.dateAdded:
      if (!selected) return 'Oldest first';
      return descending ? 'Newest first' : 'Oldest first';
  }
}

int _compareStrings(String a, String b) {
  return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
}

int _compareNullableInts(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

extension _CompareChain on int {
  int ifEqual(int next) => this == 0 ? next : this;
}

class _PlaylistSortTile extends StatelessWidget {
  const _PlaylistSortTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.descending = false,
    this.directional = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool descending;
  final bool directional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(
              directional
                  ? (descending
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded)
                  : Icons.check_rounded,
              color: AppColors.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _PlaylistOrderEditor extends StatefulWidget {
  const _PlaylistOrderEditor({required this.tracks});

  final List<Track> tracks;

  @override
  State<_PlaylistOrderEditor> createState() => _PlaylistOrderEditorState();
}

class _PlaylistOrderEditorState extends State<_PlaylistOrderEditor> {
  late final List<Track> _tracks;

  @override
  void initState() {
    super.initState();
    _tracks = List<Track>.from(widget.tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit playlist',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_tracks),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _tracks.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final track = _tracks.removeAt(oldIndex);
                  _tracks.insert(newIndex, track);
                });
              },
              itemBuilder: (context, index) {
                final track = _tracks[index];
                return ListTile(
                  key: track.playlistItemId == null
                      ? ObjectKey(track)
                      : ValueKey(track.playlistItemId),
                  leading: Text(
                    '${index + 1}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  title: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.albumName == null || track.albumName!.isEmpty
                        ? track.artistName
                        : '${track.artistName} · ${track.albumName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
    required this.visibleTracks,
    this.filterController,
    this.filterQuery = '',
    required this.selectedTrackIds,
    required this.inSelection,
    required this.onLongPress,
    required this.onToggleSelected,
    this.duplicateCount = 0,
    this.onRemoveDuplicates,
    this.onSort,
    this.onEdit,
    this.onRename,
    this.onDelete,
  });

  final PlaylistDetail playlist;
  final List<Track> visibleTracks;
  final TextEditingController? filterController;
  final String filterQuery;
  final Set<String> selectedTrackIds;
  final bool inSelection;
  final void Function(String trackId) onLongPress;
  final void Function(String trackId) onToggleSelected;
  final int duplicateCount;
  final VoidCallback? onRemoveDuplicates;
  final VoidCallback? onSort;
  final VoidCallback? onEdit;
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
            visibleTracks: visibleTracks,
            selectionActive: inSelection,
            onSort: onSort,
            onEdit: onEdit,
            duplicateCount: duplicateCount,
            onRemoveDuplicates: onRemoveDuplicates,
            onRename: onRename,
            onDelete: onDelete,
          ),
          const SizedBox(height: 8),
          if (filterController != null && playlist.tracks.isNotEmpty) ...[
            TrackFilterBar(
              controller: filterController!,
              filterQuery: filterQuery,
              visibleCount: visibleTracks.length,
              totalCount: playlist.tracks.length,
              hintText: 'Filter playlist',
            ),
            const SizedBox(height: 8),
          ],
          if (visibleTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                filterQuery.isEmpty
                    ? 'No songs in this playlist yet.'
                    : 'No songs match your filter.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...visibleTracks.asMap().entries.map(
              (entry) => _PlaylistTrackTile(
                track: entry.value,
                index: entry.key,
                allTracks: visibleTracks,
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

class _SelectionToolbarButton extends StatelessWidget {
  const _SelectionToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled
              ? AppColors.surfaceElevated
              : AppColors.surfaceElevated.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                icon,
                size: 19,
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
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
    required this.visibleTracks,
    this.selectionActive = false,
    this.onSort,
    this.onEdit,
    this.duplicateCount = 0,
    this.onRemoveDuplicates,
    this.onRename,
    this.onDelete,
  });

  final PlaylistDetail playlist;
  final List<Track> visibleTracks;
  final bool selectionActive;
  final VoidCallback? onSort;
  final VoidCallback? onEdit;
  final int duplicateCount;
  final VoidCallback? onRemoveDuplicates;
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
    final hasTracks = visibleTracks.isNotEmpty;
    final enabled = hasTracks && !selectionActive;
    final canOpenMore =
        !selectionActive &&
        (hasTracks || onEdit != null || onRename != null || onDelete != null);

    return Opacity(
      opacity: selectionActive ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: selectionActive,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayPill(
                onTap: enabled
                    ? () {
                        if (isPlaylistPlaying) {
                          controller.togglePlay();
                          return;
                        }
                        controller.playTracks(
                          visibleTracks,
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
              IconButton(
                tooltip: 'Instant Mix',
                icon: const Icon(Icons.auto_awesome_rounded),
                onPressed: enabled
                    ? () => openInstantMixPage(
                        context,
                        ref,
                        itemId: playlist.id,
                        kind: InstantMixSeedKind.playlist,
                        title: playlist.name,
                      )
                    : null,
              ),
              IconButton(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_rounded),
                onPressed: enabled ? onSort : null,
              ),
              PlaylistDownloadButton(playlist: playlist),
              IconButton(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: canOpenMore
                    ? () async {
                        final action =
                            await showModalBottomSheet<
                              _PlaylistCollectionAction
                            >(
                              context: context,
                              showDragHandle: true,
                              builder: (sheetContext) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasTracks) ...[
                                      if (onEdit != null)
                                        ListTile(
                                          leading: const Icon(
                                            Icons.edit_note_rounded,
                                          ),
                                          title: const Text('Edit playlist'),
                                          onTap: () => Navigator.of(
                                            sheetContext,
                                          ).pop(_PlaylistCollectionAction.edit),
                                        ),
                                      if (duplicateCount > 0 &&
                                          onRemoveDuplicates != null)
                                        ListTile(
                                          leading: const Icon(
                                            Icons.content_copy_rounded,
                                          ),
                                          title: Text(
                                            'Remove $duplicateCount duplicate${duplicateCount == 1 ? '' : 's'}',
                                          ),
                                          onTap: () =>
                                              Navigator.of(sheetContext).pop(
                                                _PlaylistCollectionAction
                                                    .removeDuplicates,
                                              ),
                                        ),
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
                                    if (onRename != null ||
                                        onDelete != null) ...[
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
                              trackIds: visibleTracks.map((t) => t.id).toList(),
                            );
                          case _PlaylistCollectionAction.addToQueue:
                            final added = await controller.addTracksToQueue(
                              visibleTracks,
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
                          case _PlaylistCollectionAction.edit:
                            onEdit?.call();
                          case _PlaylistCollectionAction.removeDuplicates:
                            onRemoveDuplicates?.call();
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PlaylistCollectionAction {
  edit,
  removeDuplicates,
  addToPlaylist,
  addToQueue,
  rename,
  delete,
}

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
    final current = ref.watch(currentMediaItemProvider).value;
    final isCurrent =
        current != null && current.extras?['jellyfinId'] == track.id;
    final isDownloaded = ref
        .watch(downloadManagerProvider)
        .isDownloaded(track.id);
    return TrackListTile(
      track: track,
      index: index,
      isCurrent: isCurrent,
      isDownloaded: isDownloaded,
      inSelection: inSelection,
      isSelected: isSelected,
      onLongPress: onLongPress,
      onToggleSelected: onToggleSelected,
      onArtistTap: track.artistId == null || track.artistId!.isEmpty
          ? null
          : () => context.push('/artist/${track.artistId}'),
      onAlbumTap: track.albumId == null || track.albumId!.isEmpty
          ? null
          : () => context.push('/album/${track.albumId}'),
      showAlbumInTrailing: true,
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
          context.pushNowPlayingIfNeeded();
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
