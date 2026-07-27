import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme/app_colors.dart';

/// Root [ScaffoldMessenger] key wired in [MaterialApp.router].
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppSnackBar({
  required String title,
  required String message,
  Color backgroundColor = AppColors.primary,
  Color textColor = AppColors.white,
  Duration duration = const Duration(seconds: 3),
}) {
  final snackBar = SnackBar(
    content: Text(
      title.isEmpty ? message : '$title\n$message',
      style: TextStyle(color: textColor),
    ),
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    duration: duration,
  );

  final rootState = rootScaffoldMessengerKey.currentState;
  if (rootState != null) {
    rootState
      ..clearSnackBars()
      ..showSnackBar(snackBar);
    return;
  }

}
