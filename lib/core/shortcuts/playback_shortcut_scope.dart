import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';

const _keyboardSeekStep = Duration(seconds: 10);
const _keyboardVolumeStep = 0.05;

/// Global desktop playback shortcuts.
///
/// Keeps keyboard mapping separate from app bootstrap so shortcut behavior
/// can evolve independently from top-level app initialization.
class PlaybackShortcutScope extends ConsumerWidget {
  const PlaybackShortcutScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = Theme.of(context).platform;
    if (!_isDesktopPlatform(platform)) return child;

    return Focus(
      autofocus: true,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _handlePlaybackKeyboardEvent(ref, event),
      child: child,
    );
  }

  KeyEventResult _handlePlaybackKeyboardEvent(WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_hasTextInputFocus()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    final keyboard = HardwareKeyboard.instance;
    final hasModifiers =
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
    if (hasModifiers &&
        key != LogicalKeyboardKey.mediaPlay &&
        key != LogicalKeyboardKey.mediaPause &&
        key != LogicalKeyboardKey.mediaPlayPause &&
        key != LogicalKeyboardKey.mediaTrackNext &&
        key != LogicalKeyboardKey.mediaTrackPrevious) {
      return KeyEventResult.ignored;
    }
    if (isRepeat && _isNonRepeatableShortcut(key)) {
      return KeyEventResult.handled;
    }

    final hasTrack = ref.read(effectiveMediaItemProvider) != null;
    final controller = ref.read(playerControllerProvider);
    final isPlaying = ref.read(effectivePlayingProvider);

    if (key == LogicalKeyboardKey.mediaPlay) {
      if (!isPlaying) unawaited(controller.togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      if (isPlaying) unawaited(controller.togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (hasTrack) unawaited(controller.togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (hasTrack) unawaited(controller.next());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (hasTrack) unawaited(controller.previous());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (hasTrack) unawaited(controller.togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      if (hasTrack) unawaited(controller.toggleMute());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (hasTrack) {
        unawaited(_seekRelativeFromKeyboard(ref, -_keyboardSeekStep));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (hasTrack) {
        unawaited(_seekRelativeFromKeyboard(ref, _keyboardSeekStep));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (hasTrack) unawaited(_adjustKeyboardVolume(ref, _keyboardVolumeStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (hasTrack) {
        unawaited(_adjustKeyboardVolume(ref, -_keyboardVolumeStep));
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _seekRelativeFromKeyboard(WidgetRef ref, Duration delta) async {
    final controller = ref.read(playerControllerProvider);
    final current = ref.read(effectivePositionProvider);
    final duration = ref.read(effectiveDurationProvider);
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    await controller.seek(target);
  }

  Future<void> _adjustKeyboardVolume(WidgetRef ref, double delta) async {
    final controller = ref.read(playerControllerProvider);
    final current = _currentVolumeForShortcuts(ref);
    final next = (current + delta).clamp(0.0, 1.0);
    await controller.setVolume(next);
  }

  double _currentVolumeForShortcuts(WidgetRef ref) {
    final remote = ref.read(activeRemoteSessionProvider).value;
    if (remote != null) {
      if (remote.isMuted) return 0.0;
      final remoteLevel = remote.volumeLevel;
      if (remoteLevel != null) {
        return (remoteLevel.clamp(0, 100) / 100.0).toDouble();
      }
    }
    return (ref.read(playerVolumeProvider).value ?? 1.0).clamp(0.0, 1.0);
  }

  bool _isDesktopPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  bool _isNonRepeatableShortcut(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.keyM;
  }

  bool _hasTextInputFocus() {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusedContext = focusNode?.context;
    if (focusedContext == null) return false;
    if (focusedContext.widget is EditableText) return true;

    // Keep this resilient to Flutter focus-attachment changes by checking both
    // widget and state ancestry from the focused context.
    if (focusedContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }
    if (focusedContext.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }

    final label = focusNode?.debugLabel;
    if (label != null && label.contains('EditableText')) return true;
    return false;
  }
}
