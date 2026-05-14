import 'package:flutter/material.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/widgets/header_action_buttons.dart';

/// Top "hello, $username" row on the home screen, paired with the global
/// header action buttons on phone-width layouts.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({required this.username, super.key});
  final String username;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: Theme.of(context).textTheme.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (!isDesktopLayout(context)) const HeaderActionButtons(),
      ],
    );
  }
}
