import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';

/// Top bar of the lyrics screen: dismiss arrow on the left, centered status
/// label + album link in the middle. Mirrors the shape of the now-playing
/// top bar so transitions stay seamless.
class LyricsTopBar extends StatelessWidget {
  const LyricsTopBar({
    required this.label,
    required this.album,
    required this.albumId,
    required this.castConnected,
    super.key,
  });

  final String label;
  final String album;
  final String? albumId;
  final bool castConnected;

  @override
  Widget build(BuildContext context) {
    // Single icon on the left (~48 px). Reserve same on the right so the
    // centered text stays centered.
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
                        label,
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
                            : () {
                                context.pop();
                                context.push('/album/$albumId');
                              },
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
