import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
import 'package:altsound/features/home/home_screen.dart';
import 'package:altsound/features/library/library_screen.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/remote/remote_sessions_sheet.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';
import 'package:altsound/features/syncplay/syncplay_sheet.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return _DesktopRightPane(shell: navigationShell);
  }
}

class DesktopRouteFrame extends ConsumerWidget {
  const DesktopRouteFrame({required this.child, super.key});

  final Widget child;

  static const _libraryPaneWidth = 360.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopLayout(context)) return child;
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: isOffline
                  ? const _DesktopOfflineBanner()
                  : const SizedBox.shrink(),
            ),
            const _DesktopTopNavBar(),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _libraryPaneWidth,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: AppColors.divider,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: const LibraryContent(),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayerSlot(
        withTopDivider: true,
        reserveSpaceWhenEmpty: true,
        applyBottomSafeArea: false,
        showOnDesktop: true,
        edgeToEdgeOnDesktop: true,
      ),
    );
  }
}

class _DesktopRightPane extends StatelessWidget {
  const _DesktopRightPane({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    if (shell.currentIndex == 1) {
      return shell;
    }
    return const HomeContent();
  }
}

class _DesktopTopNavBar extends ConsumerWidget {
  const _DesktopTopNavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final syncPlayActive =
        ref.watch(syncPlayControllerProvider).activeGroup != null;
    final castConnected = ref.watch(activeRemoteSessionIdProvider) != null;
    void goIfNeeded(String target) {
      if (location != target) context.go(target);
    }

    bool selected(String prefix) =>
        location == prefix || location.startsWith('$prefix/');

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'AltSound',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopNavPill(
                icon: PiconsRegular.house,
                label: 'Home',
                isSelected: selected('/'),
                onTap: () => goIfNeeded('/'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TopNavPill(
                icon: PiconsRegular.magnifyingGlass,
                label: 'Search',
                isSelected: selected('/search'),
                onTap: () => goIfNeeded('/search'),
              ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TopNavIconButton(
                    icon: PiconsRegular.usersThree,
                    tooltip: 'SyncPlay',
                    isSelected: syncPlayActive,
                    onPressed: (anchor) => showSyncPlayPopover(anchor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _TopNavIconButton(
                    icon: PiconsRegular.screencast,
                    tooltip: 'Play on…',
                    isSelected: castConnected,
                    onPressed: (anchor) => showRemoteSessionsPopover(anchor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _TopNavIconButton(
                    icon: PiconsRegular.downloadSimple,
                    tooltip: 'Downloads',
                    isSelected: selected('/downloads'),
                    onPressed: (_) => context.push('/downloads'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _TopNavIconButton(
                    icon: PiconsRegular.gear,
                    tooltip: 'Settings',
                    isSelected: selected('/settings'),
                    onPressed: (_) => goIfNeeded('/settings'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNavPill extends StatelessWidget {
  const _TopNavPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? AppColors.primary : AppColors.textSecondary;
    final bg = isSelected
        ? AppColors.primary.withValues(alpha: 0.16)
        : Colors.transparent;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopNavIconButton extends StatelessWidget {
  const _TopNavIconButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: () => onPressed(context),
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: isSelected
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.surface,
        foregroundColor: isSelected ? AppColors.primary : AppColors.textPrimary,
        minimumSize: const Size.square(40),
        fixedSize: const Size.square(40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _DesktopOfflineBanner extends StatelessWidget {
  const _DesktopOfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surfaceHighlight,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PiconsRegular.wifiSlash,
            size: 13,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            'Offline · playing from downloads',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
