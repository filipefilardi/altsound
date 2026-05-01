import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../mini_player.dart';
import '../player_providers.dart';

class MiniPlayerSlot extends ConsumerWidget {
  const MiniPlayerSlot({
    super.key,
    this.withTopDivider = false,
    this.reserveSpaceWhenEmpty = false,
  });

  final bool withTopDivider;
  final bool reserveSpaceWhenEmpty;

  static const _emptyBottomPadding = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMedia = ref.watch(currentMediaItemProvider).value != null;
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
        child: const SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: _emptyBottomPadding),
          child: SizedBox.shrink(),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: const SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 6),
        child: MiniPlayer(),
      ),
    );
  }
}
