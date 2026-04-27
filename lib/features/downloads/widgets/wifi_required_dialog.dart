import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown when the user attempts to download while WiFi-only is enabled and
/// the device is not on WiFi. Offers a shortcut to the download settings
/// screen so they can flip the toggle off.
Future<void> showWifiRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('WiFi required'),
      content: const Text(
        'WiFi-only downloads is enabled and you\'re not on WiFi. '
        'Connect to WiFi or turn off this setting to download.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.push('/settings/downloads');
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
}
