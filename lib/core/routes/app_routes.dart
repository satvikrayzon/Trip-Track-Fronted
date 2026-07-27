import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/router/routes.dart';

/// Application route names (legacy string constants for [AppNavigation]).
class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String adminDashboard = '/admin/dashboard';
  static const String managerHome = '/manager/home';
  static const String adminCreateUser = '/admin/create-user';
  static const String adminUserList = '/admin/user-list';
  static const String adminTravelRequests = '/admin/travel-requests';
  static const String adminFuelRates = '/admin/fuel-rates';
  static const String userHome = '/user/home';
  static const String userCreateRequest = '/user/create-request';
  static const String userRequestList = '/user/request-list';
  static const String userRequestDetails = '/user/request-details';
  static const String cameraCapture = '/camera/capture';
  static const String settings = '/settings';
  static const String profile = '/profile';
}

/// Holds navigation extras for GoRouter screens.
class NavigationExtras {
  static dynamic pending;
}

/// Navigation helper — GoRouter only.
class AppNavigation {
  static BuildContext? get _ctx => rootNavigatorKey.currentContext;

  static String? _mapPath(String routeName) {
    return switch (routeName) {
      AppRoutes.splash => AppPaths.splash,
      AppRoutes.login => AppPaths.login,
      AppRoutes.forgotPassword => AppPaths.forgotPassword,
      AppRoutes.adminDashboard => AppPaths.adminDashboard,
      AppRoutes.managerHome => AppPaths.managerHome,
      AppRoutes.adminCreateUser => AppPaths.adminCreateUser,
      AppRoutes.adminUserList => AppPaths.adminUserList,
      AppRoutes.adminTravelRequests => AppPaths.adminTravelRequests,
      AppRoutes.adminFuelRates => AppPaths.adminFuelRates,
      AppRoutes.userHome => AppPaths.userHome,
      AppRoutes.userCreateRequest => AppPaths.createTrip,
      AppRoutes.userRequestList => AppPaths.tripList,
      AppRoutes.userRequestDetails => AppPaths.legacyTripDetail,
      AppRoutes.cameraCapture => AppPaths.camera,
      AppRoutes.settings => AppPaths.settings,
      AppRoutes.profile => AppPaths.profile,
      _ => routeName.startsWith('/') ? routeName : null,
    };
  }

  static Future<T?> to<T>(String routeName, {dynamic arguments}) {
    final path = _mapPath(routeName);
    final ctx = _ctx;
    if (path == null || ctx == null) return Future.value(null);
    NavigationExtras.pending = arguments;
    return ctx.push<T>(path, extra: arguments);
  }

  static Future<T?> offAll<T>(String routeName, {dynamic arguments}) {
    final path = _mapPath(routeName);
    final ctx = rootNavigatorKey.currentContext ?? _ctx;
    if (path == null || ctx == null) return Future.value(null);
    GoRouter.of(ctx).go(path);
    return Future.value(null);
  }

  static Future<T?> off<T>(String routeName, {dynamic arguments}) {
    final path = _mapPath(routeName);
    final ctx = _ctx;
    if (path == null || ctx == null) return Future.value(null);
    NavigationExtras.pending = arguments;
    ctx.pushReplacement(path, extra: arguments);
    return Future.value(null);
  }

  static void back<T>({T? result}) {
    final ctx = _ctx;
    if (ctx != null && ctx.canPop()) {
      ctx.pop<T>(result);
    }
  }

  static void backUntil(String routeName) {
    final path = _mapPath(routeName);
    final ctx = _ctx;
    if (path != null && ctx != null) {
      ctx.go(path);
    }
  }

  static bool get canPop {
    final ctx = _ctx;
    return ctx != null && ctx.canPop();
  }

  static String? get currentRoute {
    final ctx = _ctx;
    if (ctx == null) return null;
    return GoRouter.of(ctx).routeInformationProvider.value.uri.path;
  }

  static dynamic get arguments => NavigationExtras.pending;
}
