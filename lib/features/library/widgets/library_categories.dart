import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';

/// Two-up "Albums / Artists" entry cards at the top of the library screen.
class LibraryCategories extends StatelessWidget {
  const LibraryCategories({
    required this.onAlbums,
    required this.onArtists,
    super.key,
  });

  final VoidCallback onAlbums;
  final VoidCallback onArtists;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LibraryCategoryCard(
            icon: PhosphorIconsRegular.disc,
            label: 'Albums',
            onTap: onAlbums,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _LibraryCategoryCard(
            icon: PhosphorIconsRegular.user,
            label: 'Artists',
            onTap: onArtists,
          ),
        ),
      ],
    );
  }
}

class _LibraryCategoryCard extends StatelessWidget {
  const _LibraryCategoryCard({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const iconColor = AppColors.textPrimary;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
