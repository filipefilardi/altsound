import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/search/widgets/search_result_tile.dart';

/// Renders search results sectioned by [MediaKind] (Artists, Songs, Albums,
/// Playlists). Empty sections are omitted.
class GroupedSearchResults extends StatelessWidget {
  const GroupedSearchResults({required this.results, super.key});
  final List<BrowseItem> results;

  @override
  Widget build(BuildContext context) {
    final tracks = results.where((r) => r.kind == MediaKind.track).toList();
    final albums = results.where((r) => r.kind == MediaKind.album).toList();
    final artists = results.where((r) => r.kind == MediaKind.artist).toList();
    final playlists = results
        .where((r) => r.kind == MediaKind.playlist)
        .toList();

    final sections = <(String, List<BrowseItem>)>[
      if (artists.isNotEmpty) ('Artists', artists),
      if (tracks.isNotEmpty) ('Songs', tracks),
      if (albums.isNotEmpty) ('Albums', albums),
      if (playlists.isNotEmpty) ('Playlists', playlists),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      itemCount: sections.fold<int>(
        0,
        (count, section) => count + 1 + section.$2.length,
      ),
      itemBuilder: (context, index) {
        int cursor = 0;
        for (final (label, items) in sections) {
          if (index == cursor) {
            return _SectionHeader(label: label);
          }
          cursor++;
          final itemIndex = index - cursor;
          if (itemIndex < items.length) {
            final item = items[itemIndex];
            final isLast = itemIndex == items.length - 1;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchResultTile(item: item),
                if (!isLast) const Divider(height: 1, indent: 80),
              ],
            );
          }
          cursor += items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
