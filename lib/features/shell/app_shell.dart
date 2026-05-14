import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/local/connectivity_provider.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';
import 'package:altsound/features/shell/desktop_shell.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  ProviderSubscription<AsyncValue>? _errorSub;

  @override
  void initState() {
    super.initState();
    _errorSub = ref.listenManual(playerErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(err.title),
            action: SnackBarAction(
              label: 'Skip',
              onPressed: () => ref.read(playerControllerProvider).next(),
            ),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _errorSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = ref.watch(isOfflineProvider);
    if (isDesktopLayout(context)) {
      return DesktopShell(navigationShell: widget.navigationShell);
    }

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: isOffline
                  ? const _OfflineBanner()
                  : const SizedBox.shrink(),
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerSlot(applyBottomSafeArea: false),
          ColoredBox(
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: NavigationBar(
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                selectedIndex: widget.navigationShell.currentIndex,
                onDestinationSelected: (i) => widget.navigationShell.goBranch(
                  i,
                  initialLocation: i == widget.navigationShell.currentIndex,
                ),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(PhosphorIconsRegular.house),
                    selectedIcon: Icon(PhosphorIconsRegular.house),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(PhosphorIconsRegular.magnifyingGlass),
                    selectedIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: Icon(PhosphorIconsRegular.musicNotes),
                    selectedIcon: Icon(PhosphorIconsRegular.musicNotes),
                    label: 'Library',
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

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
            PhosphorIconsRegular.wifiSlash,
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
