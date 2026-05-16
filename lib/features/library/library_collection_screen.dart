import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/utils/search_normalization.dart';
import 'package:altsound/core/widgets/empty_state.dart';
import 'package:altsound/core/widgets/header_action_buttons.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/library/widgets/collection_loading_rows.dart';
import 'package:altsound/features/library/widgets/collection_tile.dart';

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
        actions: isDesktopLayout(context)
            ? null
            : const [
                Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: HeaderActionButtons(),
                ),
              ],
      ),
      body: items.when(
        loading: () => const CollectionLoadingRows(),
        error: (e, _) => EmptyState(
          icon: PhosphorIconsRegular.warningCircle,
          title: 'Could not load $title',
          message: '$e',
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: widget.kind == LibraryCollectionKind.albums
                  ? PhosphorIconsRegular.disc
                  : PhosphorIconsRegular.user,
              title: 'No $title found',
              message: 'Nothing from your Jellyfin library showed up here.',
            );
          }

          final filtered = _filteredItems(items);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: TextField(
                  controller: _ctrl,
                  onChanged: (value) => setState(() => _term = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search ${title.toLowerCase()}',
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                    ),
                    suffixIcon: _ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(PhosphorIconsRegular.x),
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
                        icon: PhosphorIconsRegular.magnifyingGlassMinus,
                        title: 'No matches',
                        message: 'Nothing matched "$_term".',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.miniPlayerInset,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return CollectionTile(
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
