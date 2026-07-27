import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/router/routes.dart';
import '../../core/constants/app_constants.dart';

/// GoRouter navigation helpers.
class AppNavigator {
  static BuildContext? get _rootContext => rootNavigatorKey.currentContext;

  static void go(String path, {BuildContext? context}) {
    final ctx = context ?? _rootContext;
    if (ctx != null && ctx.mounted) {
      ctx.go(path);
    }
  }

  static void push(String path, {Object? extra, BuildContext? context}) {
    final ctx = context ?? _rootContext;
    if (ctx != null && ctx.mounted) {
      ctx.push(path, extra: extra);
    }
  }

  static void goAfterSplash({
    required BuildContext context,
    required bool isAuthenticated,
    String? role,
  }) {
    if (!context.mounted) return;

    if (!isAuthenticated) {
      context.go(AppPaths.login);
      return;
    }

    switch (role) {
      case AppConstants.adminRole:
        context.go(AppPaths.adminDashboard);
      case AppConstants.managerRole:
        context.go(AppPaths.managerHome);
      default:
        context.go(AppPaths.userHome);
    }
  }
}
