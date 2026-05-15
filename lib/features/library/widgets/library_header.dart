import 'package:flutter/material.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/widgets/header_action_buttons.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Library',
            style: Theme.of(context).textTheme.headlineMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isDesktopLayout(context)) const HeaderActionButtons(),
      ],
    );
  }
}
