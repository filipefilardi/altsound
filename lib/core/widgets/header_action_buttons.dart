import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/remote/remote_sessions_sheet.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';
import 'package:altsound/features/syncplay/syncplay_sheet.dart';

class HeaderActionButtons extends ConsumerWidget {
  const HeaderActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncPlayActive =
        ref.watch(syncPlayControllerProvider).activeGroup != null;
    final castConnected = ref.watch(activeRemoteSessionIdProvider) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderActionButton(
          icon: PiconsRegular.usersThree,
          tooltip: 'SyncPlay',
          active: syncPlayActive,
          onPressed: (anchor) => showSyncPlayPopover(anchor),
        ),
        const SizedBox(width: AppSpacing.sm),
        _HeaderActionButton(
          icon: castConnected
              ? PiconsRegular.screencast
              : PiconsRegular.screencast,
          tooltip: 'Play on…',
          active: castConnected,
          onPressed: (anchor) => showRemoteSessionsPopover(anchor),
        ),
        const SizedBox(width: AppSpacing.sm),
        _HeaderActionButton(
          icon: PiconsRegular.downloadSimple,
          tooltip: 'Downloads',
          onPressed: (_) => context.push('/downloads'),
        ),
        const SizedBox(width: AppSpacing.sm),
        _HeaderActionButton(
          icon: PiconsRegular.gear,
          tooltip: 'Settings',
          onPressed: (_) => context.push('/settings'),
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final ValueChanged<BuildContext> onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: () => onPressed(context),
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: active
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.surface,
        foregroundColor: active ? AppColors.primary : AppColors.textPrimary,
        minimumSize: const Size.square(40),
        fixedSize: const Size.square(40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltip: tooltip,
    );
  }
}
