import 'package:flutter/material.dart';

/// Global navigator key for showing dialogs from background tasks
class AppNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static BuildContext? get context => key.currentContext;

  static bool get mounted => key.currentState?.mounted ?? false;
}
