import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/utils/format.dart';
import 'package:altsound/core/widgets/app_snackbar.dart';
import 'package:altsound/core/widgets/settings_group.dart';

final _imageCacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/libCachedImageData');
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          /* skip unreadable */
        }
      }
    }
    return total;
  } catch (_) {
    return 0;
  }
});

class StorageGroup extends ConsumerWidget {
  const StorageGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(_imageCacheSizeProvider);
    return SettingsGroup(
      label: 'Storage',
      children: [
        ListTile(
          leading: const Icon(PhosphorIconsRegular.image),
          title: const Text('Clear image cache'),
          subtitle: Text(
            size.when(
              data: (b) => b == 0 ? 'Empty' : formatBytes(b),
              loading: () => '…',
              error: (_, _) => '—',
            ),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          enabled: size.maybeWhen(data: (b) => b > 0, orElse: () => false),
          onTap: () async {
            await DefaultCacheManager().emptyCache();
            ref.invalidate(_imageCacheSizeProvider);
            if (!context.mounted) return;
            showAppSnackBar(context, 'Image cache cleared');
          },
        ),
      ],
    );
  }
}
