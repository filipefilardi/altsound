import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';

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

  Future<bool> _confirmClearQueue(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear queue?'),
          content: const Text(
            'This will remove all upcoming tracks and keep only the current song.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

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
    final syncPlayActive =
        ref.watch(syncPlayControllerProvider).activeGroup != null;
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
            if (syncPlayActive && queue.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final confirmed = await _confirmClearQueue(context);
                      if (!confirmed) return;
                      await ref
                          .read(playerControllerProvider)
                          .clearQueueAfterCurrent();
                    },
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('Clear queue'),
                  ),
                ),
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
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      itemCount: queue.length,
                      itemExtent: _kQueueRowHeight,
                      onReorder: (displayOld, displayNew) {
                        if (syncPlayActive) return;
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
                          canReorder: !syncPlayActive,
                          showRemove: syncPlayActive && !isCurrent,
                          onRemove: syncPlayActive && !isCurrent
                              ? () => ref
                                    .read(playerControllerProvider)
                                    .removeQueueItemAt(i + offset)
                              : null,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Up next', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
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
    required this.canReorder,
    required this.showRemove,
    required this.onRemove,
    required this.onTap,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final bool isUserQueued;
  final LoopMode loopMode;
  final bool canReorder;
  final bool showRemove;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            _RowArt(art: item.artUri),
            const SizedBox(width: AppSpacing.md),
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
                  const SizedBox(height: AppSpacing.xs),
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
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.repeat_one_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              )
            else if (!isCurrent && isUserQueued)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.textTertiary,
                  size: 16,
                ),
              ),
            if (showRemove)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Remove from queue',
                visualDensity: VisualDensity.compact,
              ),
            if (canReorder)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.md,
                  ),
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
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
