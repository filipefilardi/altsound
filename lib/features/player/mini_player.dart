import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/navigation/app_navigation.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_gradients.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';
import 'package:altsound/features/player/widgets/player_hero_art.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({this.edgeToEdge = false, super.key});

  final bool edgeToEdge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(effectiveMediaItemProvider);
    if (mediaItem == null) return const SizedBox.shrink();

    final playing = ref.watch(effectivePlayingProvider);
    final position = ref.watch(effectivePositionProvider);
    final duration = ref.watch(effectiveDurationProvider);
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

    final borderRadius = edgeToEdge
        ? BorderRadius.zero
        : BorderRadius.circular(AppRadius.md);
    final horizontalPadding = edgeToEdge ? 0.0 : 10.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: AppColors.surfaceElevated.withValues(alpha: 0.62),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.5,
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
                  onTap: context.pushNowPlayingIfNeeded,
                  borderRadius: borderRadius,
                  splashColor: AppColors.primary.withValues(alpha: 0.08),
                  highlightColor: AppColors.primary.withValues(alpha: 0.04),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            PlayerHeroArt(
                              size: 48,
                              mediaItem: mediaItem,
                              hero: true,
                            ),
                            const SizedBox(width: AppSpacing.md),
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
                                      onTap:
                                          artistId == null || artistId.isEmpty
                                          ? null
                                          : () => context.push(
                                              '/artist/$artistId',
                                            ),
                                      child: Text(
                                        mediaItem.artist!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _RoundIcon(
                              icon: PhosphorIconsRegular.listPlus,
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
                              icon: playing
                                  ? PhosphorIconsFill.pause
                                  : PhosphorIconsFill.play,
                              onTap: controller.togglePlay,
                              emphasized: true,
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
    this.emphasized = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: emphasized
          ? AppColors.textPrimary.withValues(alpha: 0.08)
          : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: disabled
                ? AppColors.textSecondary.withValues(alpha: 0.4)
                : (iconColor ?? AppColors.textPrimary.withValues(alpha: 0.96)),
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
