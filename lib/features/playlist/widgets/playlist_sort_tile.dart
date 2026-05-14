import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';

class PlaylistSortTile extends StatelessWidget {
  const PlaylistSortTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.descending = false,
    this.directional = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool descending;
  final bool directional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(
              directional
                  ? (descending
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded)
                  : Icons.check_rounded,
              color: AppColors.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}
