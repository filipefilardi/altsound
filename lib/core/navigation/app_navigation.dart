import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension AppNavigation on BuildContext {
  void pushNowPlayingIfNeeded() {
    final state = GoRouterState.of(this);
    if (state.matchedLocation == '/now-playing') return;
    push('/now-playing');
  }
}
