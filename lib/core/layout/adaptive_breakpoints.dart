import 'package:flutter/widgets.dart';

const double desktopWidthBreakpoint = 1024;

bool isDesktopLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= desktopWidthBreakpoint;
