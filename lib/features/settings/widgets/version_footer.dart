import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:altsound/core/theme/app_colors.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class VersionFooter extends ConsumerWidget {
  const VersionFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkg = ref.watch(_packageInfoProvider);
    return Center(
      child: Text(
        pkg.when(
          data: (p) => 'AltSound ${p.version}',
          loading: () => 'AltSound',
          error: (_, _) => 'AltSound',
        ),
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
      ),
    );
  }
}
