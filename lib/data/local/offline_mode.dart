import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage.dart';

const _offlineModeKey = 'offline_mode_enabled_v1';

final offlineModeProvider =
    NotifierProvider<OfflineModeController, bool>(OfflineModeController.new);

/// User-controlled "force offline" toggle. When enabled, the app should treat
/// itself as offline regardless of the OS connectivity signal — useful when
/// the device is on Wi-Fi but the Jellyfin server is unreachable, or when the
/// user simply wants to avoid server requests.
class OfflineModeController extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_offlineModeKey);
    if (raw == 'true') state = true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final storage = ref.read(secureStorageProvider);
    if (enabled) {
      await storage.write(_offlineModeKey, 'true');
    } else {
      await storage.delete(_offlineModeKey);
    }
  }

  Future<void> toggle() => set(!state);
}
