import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/desktop_mini_player.dart';
import 'package:altsound/features/player/mini_player.dart';
import 'package:altsound/features/player/player_providers.dart';

class MiniPlayerSlot extends ConsumerWidget {
  const MiniPlayerSlot({
    super.key,
    this.withTopDivider = false,
    this.reserveSpaceWhenEmpty = false,
    this.applyBottomSafeArea = true,
    this.showOnDesktop = false,
    this.edgeToEdgeOnDesktop = false,
  });

  final bool withTopDivider;
  final bool reserveSpaceWhenEmpty;
  final bool applyBottomSafeArea;
  final bool showOnDesktop;
  final bool edgeToEdgeOnDesktop;

  static const _emptyBottomPadding = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = isDesktopLayout(context);
    if (desktop && !showOnDesktop) return const SizedBox.shrink();
    final hasMedia = ref.watch(effectiveMediaItemProvider) != null;
    final decoration = withTopDivider
        ? const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          )
        : const BoxDecoration();

    if (!hasMedia) {
      if (!reserveSpaceWhenEmpty) return const SizedBox.shrink();
      return DecoratedBox(
        decoration: decoration,
        child: SafeArea(
          top: false,
          bottom: applyBottomSafeArea,
          minimum: const EdgeInsets.only(bottom: _emptyBottomPadding),
          child: const SizedBox.shrink(),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: SafeArea(
        top: false,
        bottom: applyBottomSafeArea,
        minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: desktop
            ? DesktopMiniPlayer(edgeToEdge: edgeToEdgeOnDesktop)
            : const MiniPlayer(),
      ),
    );
  }
}
