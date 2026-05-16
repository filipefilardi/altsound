import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/pinned_action_bar_delegate.dart';
import 'package:altsound/data/downloads/download_manager.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/now_playing_favorite.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/player/widgets/track_listing_widgets.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';
import 'package:altsound/features/playlist/widgets/playlist_action_row.dart';
import 'package:altsound/features/playlist/widgets/playlist_header.dart';
import 'package:altsound/features/playlist/widgets/playlist_loading.dart';
import 'package:altsound/features/playlist/widgets/playlist_order_editor.dart';
import 'package:altsound/features/playlist/widgets/playlist_track_tile.dart';
import 'package:altsound/features/playlist/widgets/rename_playlist_dialog.dart';
import 'package:altsound/features/playlist/widgets/selection_toolbar_button.dart';

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

  Future<void> _showSelectionActionsPopover(
    BuildContext anchorCtx, {
    required String playlistId,
  }) {
    if (_selectedTrackIds.isEmpty) return Future.value();
    final count = _selectedTrackIds.length;
    final ids = Set<String>.from(_selectedTrackIds);
    final outer = context;
    return showGlassPopover<void>(
      context: anchorCtx,
      width: 280,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPopoverItem(
            icon: PhosphorIconsRegular.heart,
            label: 'Add to liked songs',
            onTap: () =>
                _bulkAddToLikedSongs(outer, ids, onDone: _clearSelection),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.listPlus,
            label: 'Add to another playlist',
            onTap: () => _showBulkAddToPlaylistDialog(
              outer,
              currentPlaylistId: playlistId,
              trackIds: ids,
              onDone: _clearSelection,
            ),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.alignTop,
            label: 'Move to top',
            onTap: () => _moveSelectedTracks(
              outer,
              playlistId: playlistId,
              trackIds: ids,
              moveToTop: true,
              onDone: _clearSelection,
            ),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.alignBottom,
            label: 'Move to bottom',
            onTap: () => _moveSelectedTracks(
              outer,
              playlistId: playlistId,
              trackIds: ids,
              moveToTop: false,
              onDone: _clearSelection,
            ),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.minusCircle,
            label: 'Remove from this playlist',
            destructive: true,
            onTap: () => _confirmBulkRemove(
              outer,
              playlistId: playlistId,
              count: count,
              trackIds: ids,
              onDone: _clearSelection,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
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
                    const SizedBox(width: AppSpacing.xs),
                    SelectionToolbarButton(
                      tooltip: 'Clear selection',
                      icon: PhosphorIconsRegular.x,
                      onPressed: _clearSelection,
                    ),
                    SelectionToolbarButton(
                      tooltip: someVisibleSelected
                          ? 'Clear visible selection'
                          : 'Select visible songs',
                      icon: allVisibleSelected
                          ? PhosphorIconsRegular.checkSquare
                          : someVisibleSelected
                          ? PhosphorIconsRegular.minusSquare
                          : PhosphorIconsRegular.square,
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
                  Builder(
                    builder: (anchorCtx) => SelectionToolbarButton(
                      tooltip: 'More',
                      icon: PhosphorIconsRegular.dotsThree,
                      onPressed: _selectedTrackIds.isEmpty
                          ? null
                          : () => _showSelectionActionsPopover(
                              anchorCtx,
                              playlistId: playlistId,
                            ),
                    ),
                  ),
                ],
              )
            : AppBar(title: const Text('Playlist')),
        bottomNavigationBar: const MiniPlayerSlot(),
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
            return const PlaylistLoading();
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
            onSort: (anchorCtx) =>
                _showSortPlaylistPopover(anchorCtx, playlist),
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

  Future<void> _showSortPlaylistPopover(
    BuildContext anchorCtx,
    PlaylistDetail playlist,
  ) {
    if (playlist.tracks.isEmpty) return Future.value();
    return showGlassPopover<void>(
      context: anchorCtx,
      width: 280,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GlassPopoverHeader(label: 'SORT BY'),
          _sortItem(
            icon: PhosphorIconsRegular.listNumbers,
            label: 'Custom order',
            sort: _PlaylistSort.custom,
            directional: false,
          ),
          _sortItem(
            icon: PhosphorIconsRegular.textT,
            label: 'Title',
            sort: _PlaylistSort.title,
          ),
          _sortItem(
            icon: PhosphorIconsRegular.user,
            label: 'Artist',
            sort: _PlaylistSort.artist,
          ),
          _sortItem(
            icon: PhosphorIconsRegular.disc,
            label: 'Album',
            sort: _PlaylistSort.album,
          ),
          _sortItem(
            icon: PhosphorIconsRegular.calendarBlank,
            label: 'Date added',
            sort: _PlaylistSort.dateAdded,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _sortItem({
    required IconData icon,
    required String label,
    required _PlaylistSort sort,
    bool directional = true,
  }) {
    final selected = _activeSort == sort;
    final descending = selected && _sortDescending;
    return GlassPopoverItem(
      icon: icon,
      label: label,
      trailing: selected
          ? Icon(
              directional
                  ? (descending
                        ? PhosphorIconsRegular.caretDown
                        : PhosphorIconsRegular.caretUp)
                  : PhosphorIconsRegular.check,
              size: 18,
              color: AppColors.primary,
            )
          : null,
      onTap: () => _applySort(sort),
    );
  }

  void _applySort(_PlaylistSort sort) {
    if (!mounted) return;
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
        child: PlaylistOrderEditor(tracks: playlist.tracks),
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
      showAppSnackBar(
        context,
        'Could not reorder this playlist. Refresh and try again.',
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
      showAppSnackBar(context, successMessage);
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      showAppSnackBar(context, 'Could not update playlist order: $e');
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
      builder: (_) => RenamePlaylistDialog(initialName: playlist.name),
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
      showAppSnackBar(context, 'Renamed to "$playlistName"');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Could not rename playlist: $e');
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
        showAppSnackBar(
          context,
          trackIds.length == 1
              ? 'Added 1 song to liked songs'
              : 'Added ${trackIds.length} songs to liked songs',
        );
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Could not add to liked songs: $e');
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
            padding: EdgeInsets.all(AppSpacing.lg),
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
                    PhosphorIconsRegular.heart,
                    color: AppColors.like,
                  ),
                  title: const Text('Liked songs'),
                  onTap: () => Navigator.of(sheetContext).pop(liked),
                ),
              ...lists.map(
                (p) => ListTile(
                  leading: const Icon(
                    PhosphorIconsRegular.queue,
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
              const SizedBox(height: AppSpacing.md),
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
        showAppSnackBar(
          context,
          'Added $addedCount song${addedCount == 1 ? '' : 's'} to "${chosen.name}"$skippedText',
        );
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Could not add to playlist: $e');
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
        showAppSnackBar(
          context,
          count == 1 ? 'Removed 1 song' : 'Removed $count songs',
        );
        onDone();
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Could not remove: $e');
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
      showAppSnackBar(
        context,
        'Removed ${duplicates.length} duplicate${duplicates.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'Could not remove duplicates: $e');
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

class _PlaylistView extends ConsumerStatefulWidget {
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
  final ValueChanged<BuildContext>? onSort;
  final VoidCallback? onEdit;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends ConsumerState<_PlaylistView> {
  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final visibleTracks = widget.visibleTracks;
    final inSelection = widget.inSelection;
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(playlistProvider(playlist.id).future),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: PlaylistHeader(playlist: playlist),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: PinnedActionBarDelegate(
              child: PlaylistActionRow(
                playlist: playlist,
                visibleTracks: visibleTracks,
                selectionActive: inSelection,
                onSort: widget.onSort,
                onEdit: widget.onEdit,
                duplicateCount: widget.duplicateCount,
                onRemoveDuplicates: widget.onRemoveDuplicates,
                onRename: widget.onRename,
                onDelete: widget.onDelete,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            sliver: SliverList.list(
              children: [
                if (widget.filterController != null &&
                    playlist.tracks.isNotEmpty) ...[
                  TrackFilterBar(
                    controller: widget.filterController!,
                    filterQuery: widget.filterQuery,
                    visibleCount: visibleTracks.length,
                    totalCount: playlist.tracks.length,
                    hintText: 'Filter playlist',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (visibleTracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Text(
                      widget.filterQuery.isEmpty
                          ? 'No songs in this playlist yet.'
                          : 'No songs match your filter.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...visibleTracks.asMap().entries.map(
                    (entry) => PlaylistTrackTile(
                      track: entry.value,
                      index: entry.key,
                      allTracks: visibleTracks,
                      contextId: playlist.id,
                      inSelection: inSelection,
                      isSelected: widget.selectedTrackIds.contains(
                        entry.value.id,
                      ),
                      onLongPress: () => widget.onLongPress(entry.value.id),
                      onToggleSelected: () =>
                          widget.onToggleSelected(entry.value.id),
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
