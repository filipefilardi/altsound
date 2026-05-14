import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/features/auth/auth_controller.dart';

class SignOutTile extends ConsumerWidget {
  const SignOutTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.logout_rounded, color: AppColors.error),
        title: const Text('Sign out', style: TextStyle(color: AppColors.error)),
        onTap: () async {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.pop();
        },
      ),
    );
  }
}
