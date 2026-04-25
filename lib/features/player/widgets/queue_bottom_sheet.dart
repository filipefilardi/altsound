import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../player_providers.dart';

Future<void> showQueueBottomSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      return Consumer(
        builder: (context, r, _) {
          final queueAsync = r.watch(queueProvider);
          final stateAsync = r.watch(playbackStateProvider);
          final queue = queueAsync.value ?? const <MediaItem>[];
          final index = stateAsync.value?.queueIndex;
          return DraggableScrollableSheet(
            expand: false,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            initialChildSize: 0.5,
            builder: (c, scroll) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      'Up next',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
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
                        : ListView.builder(
                            controller: scroll,
                            itemCount: queue.length,
                            itemBuilder: (context, i) {
                              final m = queue[i];
                              final isCurrent = i == index;
                              return ListTile(
                                onTap: () {
                                  r.read(playerControllerProvider).skipToIndex(i);
                                  Navigator.of(context).pop();
                                },
                                leading: _SheetArt(art: m.artUri, small: isCurrent),
                                title: Text(
                                  m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                    fontWeight:
                                        isCurrent ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  m.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: isCurrent
                                    ? const Icon(
                                        Icons.equalizer,
                                        color: AppColors.primary,
                                        size: 20,
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

class _SheetArt extends StatelessWidget {
  const _SheetArt({this.art, this.small = false});
  final Uri? art;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final s = small ? 44.0 : 40.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: s,
        height: s,
        child: art == null
            ? const ColoredBox(
                color: AppColors.background,
                child: Icon(Icons.music_note, color: AppColors.textTertiary, size: 20),
              )
            : CachedNetworkImage(
                imageUrl: art.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(color: AppColors.background),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.background,
                  child: Icon(Icons.music_note, color: AppColors.textTertiary, size: 20),
                ),
              ),
      ),
    );
  }
}
