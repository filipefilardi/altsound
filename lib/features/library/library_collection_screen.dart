import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/search_normalization.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/header_action_buttons.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/media_item.dart';

enum LibraryCollectionKind { albums, artists }

class LibraryCollectionScreen extends ConsumerStatefulWidget {
  const LibraryCollectionScreen({required this.kind, super.key});

  final LibraryCollectionKind kind;

  @override
  ConsumerState<LibraryCollectionScreen> createState() =>
      _LibraryCollectionScreenState();
}

class _LibraryCollectionScreenState
    extends ConsumerState<LibraryCollectionScreen> {
  final _ctrl = TextEditingController();
  String _term = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(_libraryCollectionProvider(widget.kind));
    final title = switch (widget.kind) {
      LibraryCollectionKind.albums => 'Albums',
      LibraryCollectionKind.artists => 'Artists',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: HeaderActionButtons(),
          ),
        ],
      ),
      body: items.when(
        loading: () => const _CollectionLoadingRows(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load $title',
          message: '$e',
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: widget.kind == LibraryCollectionKind.albums
                  ? Icons.album_rounded
                  : Icons.person_rounded,
              title: 'No $title found',
              message: 'Nothing from your Jellyfin library showed up here.',
            );
          }

          final filtered = _filteredItems(items);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _ctrl,
                  onChanged: (value) => setState(() => _term = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search ${title.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _term = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matches',
                        message: 'Nothing matched "$_term".',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _CollectionTile(
                            item: item,
                            isArtist:
                                widget.kind == LibraryCollectionKind.artists,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<BrowseItem> _filteredItems(List<BrowseItem> items) {
    if (_term.isEmpty) return items;
    return items
        .where((item) => searchMatches(_term, [item.name, item.subtitle]))
        .toList();
  }
}

final _libraryCollectionProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, LibraryCollectionKind>((ref, kind) {
      final repo = ref.read(jellyfinRepositoryProvider);
      return switch (kind) {
        LibraryCollectionKind.albums => repo.albums(),
        LibraryCollectionKind.artists => repo.artists(),
      };
    });

class _CollectionLoadingRows extends StatelessWidget {
  const _CollectionLoadingRows();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        itemCount: 10,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Skeleton.box(width: 52, height: 52, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180, height: 14),
                    const SizedBox(height: 6),
                    Skeleton.line(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.item, required this.isArtist});

  final BrowseItem item;
  final bool isArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = item.imageTag == null
        ? null
        : repo.imageUrl(item.id, imageTag: item.imageTag, size: 200);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(isArtist ? 28 : 6),
        child: SizedBox(
          width: 52,
          height: 52,
          child: LocalOrNetworkImage(
            source: imageUrl,
            placeholderBuilder: (_) =>
                const ColoredBox(color: AppColors.surfaceElevated),
            errorBuilder: (_) => ColoredBox(
              color: AppColors.surfaceElevated,
              child: Icon(
                isArtist ? Icons.person_rounded : Icons.album_rounded,
                color: AppColors.textTertiary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        item.subtitle ?? (isArtist ? 'Artist' : 'Album'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      onTap: () =>
          context.push(isArtist ? '/artist/${item.id}' : '/album/${item.id}'),
    );
  }
}
