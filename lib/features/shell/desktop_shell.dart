import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/adaptive_breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../data/local/connectivity_provider.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../player/widgets/mini_player_slot.dart';

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

class _DesktopTopNavBar extends StatelessWidget {
  const _DesktopTopNavBar();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    void goIfNeeded(String target) {
      if (location != target) context.go(target);
    }

    bool selected(String prefix) =>
        location == prefix || location.startsWith('$prefix/');

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'AltSound',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TopNavButton(
                  label: 'Home',
                  isSelected: selected('/'),
                  onTap: () => goIfNeeded('/'),
                ),
                const SizedBox(width: 12),
                _TopNavButton(
                  label: 'Search',
                  isSelected: selected('/search'),
                  onTap: () => goIfNeeded('/search'),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _TopNavButton(
              label: 'Settings',
              isSelected: selected('/settings'),
              onTap: () => goIfNeeded('/settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNavButton extends StatelessWidget {
  const _TopNavButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: isSelected
            ? AppColors.primary
            : AppColors.textSecondary,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 13,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 6),
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
