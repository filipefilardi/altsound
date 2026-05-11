import 'package:flutter/material.dart';

import '../../../core/layout/adaptive_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/jellyfin/models/media_item.dart';
import 'playing_track_leading.dart';

class TrackFilterBar extends StatelessWidget {
  const TrackFilterBar({
    required this.controller,
    required this.filterQuery,
    required this.visibleCount,
    required this.totalCount,
    this.hintText = 'Filter songs',
    super.key,
  });

  final TextEditingController controller;
  final String filterQuery;
  final int visibleCount;
  final int totalCount;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hintText,
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                suffixIcon: filterQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear filter',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: controller.clear,
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ),
          ),
        ),
        if (filterQuery.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(
            '$visibleCount/$totalCount',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isDownloaded,
    required this.onTap,
    required this.trailing,
    this.onLongPress,
    this.inSelection = false,
    this.isSelected = false,
    this.onToggleSelected,
    this.onArtistTap,
    this.onAlbumTap,
    this.showAlbumInTrailing = false,
    super.key,
  });

  final Track track;
  final int index;
  final bool isCurrent;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool inSelection;
  final bool isSelected;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onArtistTap;
  final VoidCallback? onAlbumTap;
  final bool showAlbumInTrailing;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final showAlbum =
        showAlbumInTrailing &&
        isDesktopLayout(context) &&
        track.albumName != null &&
        track.albumName!.isNotEmpty;

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      isThreeLine: inSelection,
      onLongPress: onLongPress,
      onTap: onTap,
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      leading: inSelection
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelected?.call(),
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
      subtitle: InkWell(
        onTap: inSelection ? null : onArtistTap,
        child: Text(
          track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      trailing: inSelection
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAlbum) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: InkWell(
                      onTap: onAlbumTap,
                      child: Text(
                        track.albumName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                if (isDownloaded)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.download_for_offline_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                trailing,
              ],
            ),
    );
  }
}
