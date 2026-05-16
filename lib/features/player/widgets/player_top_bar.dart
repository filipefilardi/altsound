import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';

/// Top bar of the now-playing screen: dismiss arrow + centered (album / cast
/// status) label.
class PlayerTopBar extends ConsumerWidget {
  const PlayerTopBar({required this.album, required this.albumId, super.key});

  final String album;
  final String? albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteId = ref.watch(activeRemoteSessionIdProvider);
    final remoteSession = remoteId == null
        ? null
        : ref.watch(activeRemoteSessionProvider).value;
    final syncGroup = ref.watch(syncPlayControllerProvider).activeGroup;
    final castConnected = remoteId != null;
    final castLabel = castConnected
        ? 'PLAYING ON ${remoteSession?.deviceName.toUpperCase() ?? 'REMOTE'}'
        : syncGroup != null
        ? 'SYNCPLAY: ${syncGroup.name.toUpperCase()}'
        : 'PLAYING FROM ALBUM';
    // Reserve symmetric space on both sides so the centered text is not
    // pushed off-center by edge icons (left icon + mirrored right reserve).
    const sideReserve = 48.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: sideReserve),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        castLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          letterSpacing: 1.6,
                          color: castConnected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      InkWell(
                        onTap:
                            albumId == null || albumId!.isEmpty || album.isEmpty
                            ? null
                            : () => context.push('/album/$albumId'),
                        child: Text(
                          album,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                albumId == null ||
                                    albumId!.isEmpty ||
                                    album.isEmpty
                                ? AppColors.textPrimary
                                : AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(PhosphorIconsRegular.caretDown, size: 30),
                onPressed: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
