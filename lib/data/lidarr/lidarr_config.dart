import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/secure_storage.dart';

const _key = 'lidarr_config_v1';

class LidarrConfig {
  const LidarrConfig({required this.url, required this.apiKey});
  final String url;
  final String apiKey;

  Map<String, dynamic> toJson() => {'url': url, 'apiKey': apiKey};

  factory LidarrConfig.fromJson(Map<String, dynamic> json) =>
      LidarrConfig(url: json['url'] as String, apiKey: json['apiKey'] as String);
}

final lidarrConfigProvider =
    NotifierProvider<LidarrConfigNotifier, LidarrConfig?>(
        LidarrConfigNotifier.new);

class LidarrConfigNotifier extends Notifier<LidarrConfig?> {
  @override
  LidarrConfig? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_key);
    if (raw == null) return;
    try {
      state = LidarrConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // ignore corrupt config
    }
  }

  Future<void> save(LidarrConfig config) async {
    await ref
        .read(secureStorageProvider)
        .write(_key, jsonEncode(config.toJson()));
    state = config;
  }

  Future<void> clear() async {
    await ref.read(secureStorageProvider).delete(_key);
    state = null;
  }
}
