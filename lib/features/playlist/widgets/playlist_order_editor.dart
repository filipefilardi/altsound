import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';

/// Full-screen modal for reordering playlist tracks. Pops with the new list
/// of [Track] on Save, or `null` on Cancel.
class PlaylistOrderEditor extends StatefulWidget {
  const PlaylistOrderEditor({required this.tracks, super.key});

  final List<Track> tracks;

  @override
  State<PlaylistOrderEditor> createState() => _PlaylistOrderEditorState();
}

class _PlaylistOrderEditorState extends State<PlaylistOrderEditor> {
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
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
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
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
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Icon(
                        PiconsRegular.dotsSixVertical,
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
