/// A Jellyfin client session that can be remote-controlled.
class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.client,
    required this.userName,
    required this.supportsRemoteControl,
    required this.supportedCommands,
    this.nowPlayingItemId,
    this.nowPlayingTitle,
    this.nowPlayingArtist,
    this.positionTicks,
    this.runTimeTicks,
    this.isPaused = false,
    this.isMuted = false,
    this.volumeLevel,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String client;
  final String userName;
  final bool supportsRemoteControl;
  final Set<String> supportedCommands;

  final String? nowPlayingItemId;
  final String? nowPlayingTitle;
  final String? nowPlayingArtist;
  final int? positionTicks;
  final int? runTimeTicks;
  final bool isPaused;
  final bool isMuted;
  final int? volumeLevel;

  bool get hasNowPlaying => nowPlayingItemId != null;

  Duration? get position => positionTicks == null
      ? null
      : Duration(microseconds: positionTicks! ~/ 10);

  Duration? get duration => runTimeTicks == null
      ? null
      : Duration(microseconds: runTimeTicks! ~/ 10);

  factory RemoteSession.fromJson(Map<String, dynamic> json) {
    final nowPlaying = json['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = json['PlayState'] as Map<String, dynamic>?;
    final commands = (json['SupportedCommands'] as List?)
            ?.cast<String>()
            .toSet() ??
        const <String>{};
    return RemoteSession(
      id: json['Id'] as String,
      deviceId: json['DeviceId'] as String? ?? '',
      deviceName: json['DeviceName'] as String? ?? 'Unknown device',
      client: json['Client'] as String? ?? '',
      userName: json['UserName'] as String? ?? '',
      supportsRemoteControl:
          (json['SupportsRemoteControl'] as bool?) ?? false,
      supportedCommands: commands,
      nowPlayingItemId: nowPlaying?['Id'] as String?,
      nowPlayingTitle: nowPlaying?['Name'] as String?,
      nowPlayingArtist: (nowPlaying?['Artists'] as List?)?.cast<String>().firstOrNull,
      runTimeTicks: nowPlaying?['RunTimeTicks'] as int?,
      positionTicks: playState?['PositionTicks'] as int?,
      isPaused: (playState?['IsPaused'] as bool?) ?? false,
      isMuted: (playState?['IsMuted'] as bool?) ?? false,
      volumeLevel: playState?['VolumeLevel'] as int?,
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
