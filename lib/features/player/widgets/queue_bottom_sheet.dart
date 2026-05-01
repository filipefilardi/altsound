import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_colors.dart';
import '../player_providers.dart';

const double _kQueueRowHeight = 64;

Future<void> showQueueBottomSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(queueProvider);
    final stateAsync = ref.watch(playbackStateProvider);
    final userQueuedIds =
        ref.watch(userQueuedIdsProvider).value ?? const <String>{};
    final loopMode = ref.watch(playerLoopModeProvider).value ?? LoopMode.off;
    final fullQueue = queueAsync.value ?? const <MediaItem>[];
    final absoluteIndex = stateAsync.value?.queueIndex;

    // Only show the current song and everything after it.
    final offset = absoluteIndex ?? 0;
    final queue = fullQueue.isEmpty ? fullQueue : fullQueue.sublist(offset);

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      initialChildSize: 0.6,
      builder: (c, outerScroll) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(total: queue.length, loopMode: loopMode),
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
                      onReorder: (displayOld, displayNew) {
                        ref
                            .read(playerControllerProvider)
                            .reorderQueue(
                              displayOld + offset,
                              displayNew + offset,
                            );
                      },
                      itemBuilder: (context, i) {
                        final m = queue[i];
                        final isCurrent = i == 0;
                        final isUserQueued = userQueuedIds.contains(
                          m.extras?['jellyfinId'] as String?,
                        );
                        return _QueueRow(
                          key: ValueKey(m.id + i.toString()),
                          item: m,
                          index: i,
                          isCurrent: isCurrent,
                          isUserQueued: isUserQueued,
                          loopMode: loopMode,
                          onTap: () {
                            ref
                                .read(playerControllerProvider)
                                .skipToIndex(i + offset);
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
  const _Header({required this.total, required this.loopMode});
  final int total;
  final LoopMode loopMode;

  @override
  Widget build(BuildContext context) {
    final label = total == 0 ? '' : '$total ${total == 1 ? 'track' : 'tracks'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Up next', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 10),
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          const Spacer(),
          if (loopMode != LoopMode.off)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _RepeatBadge(loopMode: loopMode),
            ),
        ],
      ),
    );
  }
}

class _RepeatBadge extends StatelessWidget {
  const _RepeatBadge({required this.loopMode});
  final LoopMode loopMode;

  @override
  Widget build(BuildContext context) {
    final isOne = loopMode == LoopMode.one;
    final label = isOne ? 'Repeat track' : 'Repeat queue';
    final icon = isOne ? Icons.repeat_one_rounded : Icons.repeat_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.primary,
              letterSpacing: 0.6,
              fontSize: 11,
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
    required this.isUserQueued,
    required this.loopMode,
    required this.onTap,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final bool isUserQueued;
  final LoopMode loopMode;
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
            if (isCurrent && loopMode == LoopMode.one)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.repeat_one_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              )
            else if (!isCurrent && isUserQueued)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.textTertiary,
                  size: 16,
                ),
              ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Icon(
                  Icons.drag_indicator_rounded,
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
                child: Icon(
                  Icons.music_note_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              )
            : CachedNetworkImage(
                imageUrl: art.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppColors.background),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.background,
                  child: Icon(
                    Icons.music_note_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ),
      ),
    );
  }
}
