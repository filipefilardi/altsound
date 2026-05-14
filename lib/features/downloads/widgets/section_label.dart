import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';

/// ALL-CAPS section label used on the downloads settings screen between
/// rows. Mirrors the visual weight of [Theme.labelLarge].
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
