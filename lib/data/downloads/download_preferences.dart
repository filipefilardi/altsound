import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/data/local/secure_storage.dart';

const _key = 'download_preferences_v1';

class DownloadPreferences {
  const DownloadPreferences({
    this.autoDownload = false,
    this.wifiOnly = false,
    this.subscribedAlbumIds = const {},
    this.subscribedPlaylistIds = const {},
  });

  final bool autoDownload;
  final bool wifiOnly;
  final Set<String> subscribedAlbumIds;
  final Set<String> subscribedPlaylistIds;

  bool isAlbumSubscribed(String id) => subscribedAlbumIds.contains(id);
  bool isPlaylistSubscribed(String id) => subscribedPlaylistIds.contains(id);

  DownloadPreferences copyWith({
    bool? autoDownload,
    bool? wifiOnly,
    Set<String>? subscribedAlbumIds,
    Set<String>? subscribedPlaylistIds,
  }) => DownloadPreferences(
    autoDownload: autoDownload ?? this.autoDownload,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    subscribedAlbumIds: subscribedAlbumIds ?? this.subscribedAlbumIds,
    subscribedPlaylistIds: subscribedPlaylistIds ?? this.subscribedPlaylistIds,
  );

  Map<String, dynamic> toJson() => {
    'autoDownload': autoDownload,
    'wifiOnly': wifiOnly,
    'subscribedAlbumIds': subscribedAlbumIds.toList(),
    'subscribedPlaylistIds': subscribedPlaylistIds.toList(),
  };

  factory DownloadPreferences.fromJson(Map<String, dynamic> json) =>
      DownloadPreferences(
        autoDownload: json['autoDownload'] as bool? ?? false,
        wifiOnly: json['wifiOnly'] as bool? ?? false,
        subscribedAlbumIds: Set<String>.from(
          (json['subscribedAlbumIds'] as List?)?.cast<String>() ?? [],
        ),
        subscribedPlaylistIds: Set<String>.from(
          (json['subscribedPlaylistIds'] as List?)?.cast<String>() ?? [],
        ),
      );
}

final downloadPreferencesProvider =
    NotifierProvider<DownloadPreferencesNotifier, DownloadPreferences>(
      DownloadPreferencesNotifier.new,
    );

class DownloadPreferencesNotifier extends Notifier<DownloadPreferences> {
  @override
  DownloadPreferences build() {
    _restore();
    return const DownloadPreferences();
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_key);
    if (raw == null) return;
    try {
      state = DownloadPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {}
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_key, jsonEncode(state.toJson()));
  }

  Future<void> setAutoDownload(bool value) async {
    state = state.copyWith(autoDownload: value);
    await _persist();
  }

  Future<void> setWifiOnly(bool value) async {
    state = state.copyWith(wifiOnly: value);
    await _persist();
  }

  Future<void> subscribeAlbum(String albumId) async {
    state = state.copyWith(
      subscribedAlbumIds: {...state.subscribedAlbumIds, albumId},
    );
    await _persist();
  }

  Future<void> unsubscribeAlbum(String albumId) async {
    state = state.copyWith(
      subscribedAlbumIds: {...state.subscribedAlbumIds}..remove(albumId),
    );
    await _persist();
  }

  Future<void> subscribePlaylist(String playlistId) async {
    state = state.copyWith(
      subscribedPlaylistIds: {...state.subscribedPlaylistIds, playlistId},
    );
    await _persist();
  }

  Future<void> unsubscribePlaylist(String playlistId) async {
    state = state.copyWith(
      subscribedPlaylistIds: {...state.subscribedPlaylistIds}
        ..remove(playlistId),
    );
    await _persist();
  }

  Future<bool> canDownloadNow() async {
    if (!state.wifiOnly) return true;
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }
}
