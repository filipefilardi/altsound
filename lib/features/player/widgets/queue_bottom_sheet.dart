import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../player_providers.dart';

const double _kQueueRowHeight = 64;

Future<void> showQueueBottomSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  final _scrollController = ScrollController();
  bool _autoScrolled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int? currentIndex, int total) {
    if (_autoScrolled || currentIndex == null || total == 0) return;
    _autoScrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      final headroom = viewport * 0.3;
      final target =
          (currentIndex * _kQueueRowHeight - headroom).clamp(0.0, double.infinity);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(queueProvider);
    final stateAsync = ref.watch(playbackStateProvider);
    final queue = queueAsync.value ?? const <MediaItem>[];
    final index = stateAsync.value?.queueIndex;

    _maybeAutoScroll(index, queue.length);

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      initialChildSize: 0.6,
      builder: (c, outerScroll) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              currentIndex: index,
              total: queue.length,
            ),
            Expanded(
              child: queue.isEmpty
                  ? const Center(
                      child: Text(
                        'No tracks in queue',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: queue.length,
                      itemExtent: _kQueueRowHeight,
                      onReorder: (oldIndex, newIndex) {
                        ref
                            .read(playerControllerProvider)
                            .reorderQueue(oldIndex, newIndex);
                      },
                      itemBuilder: (context, i) {
                        final m = queue[i];
                        final isCurrent = i == index;
                        return _QueueRow(
                          key: ValueKey(m.id + i.toString()),
                          item: m,
                          index: i,
                          isCurrent: isCurrent,
                          onTap: () {
                            ref
                                .read(playerControllerProvider)
                                .skipToIndex(i);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.currentIndex, required this.total});
  final int? currentIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    final position =
        currentIndex == null || total == 0 ? '' : '${currentIndex! + 1} of $total';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Up next',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: 10),
          if (position.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                position,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.0,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _RowArt(art: item.artUri),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.equalizer,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Icon(
                  Icons.drag_indicator,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowArt extends StatelessWidget {
  const _RowArt({this.art});
  final Uri? art;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: art == null
            ? const ColoredBox(
                color: AppColors.background,
                child: Icon(Icons.music_note,
                    color: AppColors.textTertiary, size: 20),
              )
            : CachedNetworkImage(
                imageUrl: art.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppColors.background),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.background,
                  child: Icon(Icons.music_note,
                      color: AppColors.textTertiary, size: 20),
                ),
              ),
      ),
    );
  }
}
