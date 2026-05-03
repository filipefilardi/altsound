import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/connectivity_provider.dart';
import 'player_providers.dart';

Future<void> startInstantMix(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (ref.read(isOfflineProvider)) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Instant Mix needs the server.')),
    );
    return;
  }

  try {
    final count = await ref
        .read(playerControllerProvider)
        .playInstantMix(itemId);
    if (!context.mounted) return;
    if (count == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Instant Mix found no songs.')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Could not start Instant Mix: $e')),
    );
  }
}
