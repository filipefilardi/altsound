import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` when the device has any network access, `false` when none.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final initial = await Connectivity().checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  await for (final result in Connectivity().onConnectivityChanged) {
    yield result.any((r) => r != ConnectivityResult.none);
  }
});

/// Synchronous convenience — `true` when offline.
/// Defaults to `false` (assume online) during the brief async init.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).maybeWhen(
    data: (isOnline) => !isOnline,
    orElse: () => false,
  );
});
