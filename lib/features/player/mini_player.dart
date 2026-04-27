import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import 'current_track_playlist_presence.dart';
import 'player_providers.dart';
import 'widgets/add_track_to_playlist_sheet.dart';
import 'widgets/player_hero_art.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (mediaItem == null) return const SizedBox.shrink();

    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = mediaItem.duration ?? Duration.zero;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final controller = ref.read(playerControllerProvider);
    final artistId = mediaItem.extras?['artistId'] as String?;
    final presenceAsync = ref.watch(currentTrackPlaylistPresenceProvider);
    final saved = switch (presenceAsync) {
      AsyncData(:final value) => value.isSaved,
      _ => false,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surfaceHighlight.withValues(alpha: 0.62),
              border: Border.all(
                color: AppColors.textPrimary.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -250) {
                  HapticFeedback.selectionClick();
                  controller.next();
                } else if (v > 250) {
                  HapticFeedback.selectionClick();
                  controller.previous();
                }
              },
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push('/now-playing'),
                  borderRadius: BorderRadius.circular(20),
                  splashColor: AppColors.primary.withValues(alpha: 0.08),
                  highlightColor: AppColors.primary.withValues(alpha: 0.04),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            PlayerHeroArt(
                              size: 48,
                              mediaItem: mediaItem,
                              hero: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    mediaItem.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (mediaItem.artist != null)
                                    InkWell(
                                      onTap: artistId == null || artistId.isEmpty
                                          ? null
                                          : () => context.push('/artist/$artistId'),
                                      child: Text(
                                        mediaItem.artist!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: artistId == null || artistId.isEmpty
                                              ? AppColors.textSecondary
                                              : AppColors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _RoundIcon(
                              icon: saved
                                  ? Icons.playlist_add_check
                                  : Icons.playlist_add,
                              iconColor: saved ? AppColors.primary : null,
                              onTap: () => unawaited(
                                _onMiniPlayerPlaylistTap(
                                  context,
                                  ref,
                                  trackId: mediaItem.id,
                                  saved: saved,
                                ),
                              ),
                            ),
                            _RoundIcon(
                              icon: playing ? Icons.pause : Icons.play_arrow,
                              onTap: controller.togglePlay,
                            ),
                          ],
                        ),
                      ),
                      _GradientProgressBar(progress: progress),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _onMiniPlayerPlaylistTap(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required bool saved,
}) async {
  await openManageTrackPlaylistsSheet(context, ref, trackId: trackId);
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: iconColor ?? AppColors.textPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  const _GradientProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final fillWidth = constraints.maxWidth * progress.clamp(0.0, 1.0);
        return SizedBox(
          height: 2,
          width: constraints.maxWidth,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.divider.withValues(alpha: 0.35),
                ),
              ),
              if (fillWidth > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fillWidth,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.accentHorizontal,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
