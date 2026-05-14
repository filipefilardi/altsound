import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/auth/auth_controller.dart';
import 'package:altsound/features/settings/widgets/account_card.dart';
import 'package:altsound/features/settings/widgets/library_group.dart';
import 'package:altsound/features/settings/widgets/playback_group.dart';
import 'package:altsound/features/settings/widgets/sign_out_tile.dart';
import 'package:altsound/features/settings/widgets/storage_group.dart';
import 'package:altsound/features/settings/widgets/version_footer.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = auth is AuthAuthenticated ? auth.session : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.miniPlayerInset,
        ),
        children: [
          if (session != null) ...[
            AccountCard(session: session),
            const SizedBox(height: AppSpacing.lg),
          ],
          const PlaybackGroup(),
          const SizedBox(height: AppSpacing.lg),
          const LibraryGroup(),
          const SizedBox(height: AppSpacing.lg),
          const StorageGroup(),
          const SizedBox(height: AppSpacing.lg),
          const SignOutTile(),
          const SizedBox(height: AppSpacing.lg),
          const VersionFooter(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Sign out / version
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------
