import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/layout/responsive_web_layout.dart';
import '../../core/layout/adaptive_layout.dart';

import '../../modules/user/presentation/pages/user_home_screen.dart';
import '../../features/live_map/presentation/pages/live_tracking_map_page.dart';
import '../../features/trip_detail/presentation/pages/enterprise_trip_detail_page.dart';
import '../../modules/admin/presentation/pages/admin_dashboard_screen.dart';
import '../../modules/admin/presentation/pages/admin_create_user_screen.dart';
import '../../modules/admin/presentation/pages/admin_fuel_rates_screen.dart';
import '../../modules/admin/presentation/pages/admin_travel_requests_screen.dart';
import '../../modules/admin/presentation/pages/admin_user_list_screen.dart';
import '../../modules/auth/presentation/pages/forgot_password_screen.dart';
import '../../modules/auth/presentation/pages/login_screen.dart';
import '../../modules/auth/presentation/pages/splash_screen.dart';
import '../../modules/camera/presentation/pages/camera_capture_screen.dart';
import '../../modules/profile/presentation/pages/profile_screen.dart';
import '../../modules/settings/presentation/pages/settings_screen.dart';
import '../../modules/user/presentation/pages/user_create_request_screen.dart';
import '../../modules/user/presentation/pages/user_request_list_screen.dart';
import '../../modules/user/presentation/pages/user_request_details_screen.dart';
import '../../modules/auth/presentation/controllers/app_auth_controller.dart';
import '../../modules/auth/data/models/user_model.dart';
import '../../shared/widgets/page_transitions.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppPaths.splash,
    routes: [
      GoRoute(
        path: AppPaths.splash,
        pageBuilder: (_, state) => fadeSlidePage(
          key: state.pageKey,
          child: const AdaptiveAppFrame(child: SplashScreen()),
        ),
      ),
      GoRoute(
        path: AppPaths.login,
        pageBuilder: (_, state) => fadeSlidePage(
          key: state.pageKey,
          child: const AdaptiveAppFrame(child: LoginScreen()),
        ),
      ),
      GoRoute(
        path: AppPaths.forgotPassword,
        pageBuilder: (_, state) => fadeSlidePage(
          key: state.pageKey,
          child: const AdaptiveAppFrame(child: ForgotPasswordScreen()),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ResponsiveWebLayout(child: child);
        },
        routes: [
          GoRoute(
            path: AppPaths.home,
            redirect: (_, __) => AppPaths.userHome,
          ),
          GoRoute(
            path: AppPaths.userHome,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const UserHomeScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.legacyTripDetail,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const UserRequestDetailsScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.managerHome,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const UserHomeScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.adminDashboard,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const AdminDashboardScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.adminUserList,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const AdminUserListScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.adminCreateUser,
            redirect: (_, __) {
              if (!ServiceLocator.I.has<AppAuthController>()) {
                return AppPaths.login;
              }
              if (!ServiceLocator.I.get<AppAuthController>().isAdmin) {
                return AppPaths.adminDashboard;
              }
              return null;
            },
            pageBuilder: (_, state) {
              final user = state.extra as UserModel?;
              return fadeSlidePage(
                key: state.pageKey,
                child: AdminCreateUserScreen(userToEdit: user),
              );
            },
          ),
          GoRoute(
            path: AppPaths.adminTravelRequests,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const AdminTravelRequestsScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.adminFuelRates,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const AdminFuelRatesScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.liveMap,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const LiveTrackingMapPage(),
            ),
          ),
          GoRoute(
            path: AppPaths.tripDetail,
            pageBuilder: (_, state) {
              final id = state.pathParameters['id']!;
              return fadeSlidePage(
                key: state.pageKey,
                child: EnterpriseTripDetailPage(tripId: id),
              );
            },
          ),
          GoRoute(
            path: AppPaths.createTrip,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: UserCreateRequestScreen(initialArgs: state.extra),
            ),
          ),
          GoRoute(
            path: AppPaths.tripList,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const UserRequestListScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.camera,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const CameraCaptureScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.settings,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: AppPaths.profile,
            pageBuilder: (_, state) => fadeSlidePage(
              key: state.pageKey,
              child: const ProfileScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}
