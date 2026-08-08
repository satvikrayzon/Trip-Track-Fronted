import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/hive_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/network/session_token_refresher.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/utils/jwt_payload.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/users_remote_datasource.dart';
import '../../data/models/user_model.dart';
import '../bloc/auth_session_cubit.dart';

/// Authentication against the Nest HTTP API (JWT).
class AppAuthController {
  AppAuthController({
    required AuthRemoteDataSource authRemote,
    required UsersRemoteDataSource usersRemote,
    required TokenStore tokenStore,
    required SessionTokenRefresher tokenRefresher,
    AuthSessionCubit? authSessionCubit,
  })  : _authRemote = authRemote,
        _usersRemote = usersRemote,
        _tokens = tokenStore,
        _tokenRefresher = tokenRefresher,
        _authSessionCubit = authSessionCubit;

  final AuthRemoteDataSource _authRemote;
  final UsersRemoteDataSource _usersRemote;
  final TokenStore _tokens;
  final SessionTokenRefresher _tokenRefresher;
  final AuthSessionCubit? _authSessionCubit;
  final HiveDatabase _localDb = HiveDatabase.instance;

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String> errorMessage = ValueNotifier<String>('');
  final ValueNotifier<UserModel?> userNotifier = ValueNotifier<UserModel?>(null);

  Timer? _banPoll;
  Future<void>? _sessionReadyFuture;

  UserModel? get currentUserData => userNotifier.value;

  /// Mongo `id` or `uid` — matches travel-request `userId` from the API.
  String? get currentUserApiId {
    final user = userNotifier.value;
    if (user == null) return null;
    final id = user.apiId;
    return id.isNotEmpty ? id : null;
  }

  bool get isAuthenticated =>
      _tokens.accessToken != null &&
      _tokens.accessToken!.isNotEmpty &&
      userNotifier.value != null;

  bool get hasStoredSession =>
      _tokens.accessToken != null && _tokens.accessToken!.isNotEmpty;

  String? get userRole => userNotifier.value?.role;
  bool get isAdmin => userRole == AppConstants.adminRole;
  bool get isManager => userRole == AppConstants.managerRole;
  bool get isHodOrAdmin => isAdmin || isManager;

  void start() {
    unawaited(ensureSessionReady());
  }

  void dispose() {
    _banPoll?.cancel();
    isLoading.dispose();
    errorMessage.dispose();
    userNotifier.dispose();
  }

  AuthSessionCubit? get _cubit {
    if (_authSessionCubit != null) return _authSessionCubit;
    if (ServiceLocator.I.has<AuthSessionCubit>()) {
      return ServiceLocator.I.get<AuthSessionCubit>();
    }
    return null;
  }
  /// Call from [main] and splash so cold start waits for `/auth/me` (or Hive fallback).
  Future<void> ensureSessionReady() {
    _sessionReadyFuture ??= _bootstrapSession();
    return _sessionReadyFuture!;
  }

  Future<void> _bootstrapSession() async {
    _reloadTokensFromDisk();

    final access = _tokens.accessToken;
    if (access == null || access.isEmpty) {
      return;
    }

    // Restore cached profile first — enough to route without waiting on the network.
    await _hydrateUserFromOfflineCache();

    if (JwtPayload.isExpired(access)) {
      try {
        await _tryRefreshAccessToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    final hasCachedProfile =
        userNotifier.value != null && hasStoredSession;
    if (hasCachedProfile) {
      // Unblock splash / home immediately; sync profile when online.
      unawaited(_refreshProfileInBackground());
      return;
    }

    // No cached profile — short network attempt before routing.
    try {
      await _loadProfileFromApi().timeout(const Duration(seconds: 4));
    } catch (_) {}

    if (userNotifier.value == null) {
      await _hydrateUserFromOfflineCache();
    }
  }

  Future<void> _refreshProfileInBackground() async {
    try {
      await _loadProfileFromApi(silent: true);
    } catch (e) {
    }
  }

  void _reloadTokensFromDisk() {
    final store = _tokens;
    if (store is HiveTokenStore) {
      store.reloadFromDisk();
    }
  }

  Future<bool> _tryRefreshAccessToken() async {
    final ok = await _tokenRefresher.refreshAccessToken();
    if (ok) _cubit?.hydrate();
    return ok;
  }

  /// Call when a protected API returns 401 after [TokenRefreshInterceptor] retry.
  Future<void> onApiUnauthorized() async {
    final refreshed = await _tryRefreshAccessToken();
    final access = _tokens.accessToken;
    if (refreshed &&
        access != null &&
        access.isNotEmpty &&
        !JwtPayload.isExpired(access)) {
      return;
    }

    // Keep session when refresh token exists — likely offline or server down.
    final refresh = _tokens.refreshToken;
    if (refresh != null &&
        refresh.isNotEmpty &&
        userNotifier.value != null) {
      return;
    }

    showAppSnackBar(
      title: 'Session expired',
      message: 'Please sign in again.',
      backgroundColor: const Color(0xFFEF4444),
    );
    await signOut(silent: false);
  }

  Future<void> _hydrateUserFromOfflineCache() async {
    final token = _tokens.accessToken;
    if (token == null || token.isEmpty) return;
    final uid = JwtPayload.userId(token);
    if (uid == null || uid.isEmpty) return;
    try {
      final row = await _localDb.getUser(uid);
      if (row == null) return;
      final map = Map<String, dynamic>.from(row);
      final user = UserModel.fromLocalDb(map);
      if (user.uid.isEmpty) return;
      userNotifier.value = user;
      _syncSessionCubit();
      _ensureBanPoll();
    } catch (e) {
    }
  }

  Future<void> _loadProfileFromApi({
    bool isRetry = false,
    bool silent = false,
  }) async {
    final result = await _authRemote.fetchCurrentUser();
    if (result case ApiFailure(:final failure)) {
      if (failure.statusCode == 401) {
        await _handleUnauthorizedProfileLoad(allowRetry: !isRetry);
      } else if (!silent && !failure.isTransientNetworkError) {
        errorMessage.value = failure.message;
      } else 
      return;
    }
    if (result case ApiSuccess(:final data)) {
      await _applyRemoteUser(UserModel.fromApi(data));
    }
  }

  /// Keeps the session when tokens or offline profile can still be used.
  Future<void> _handleUnauthorizedProfileLoad({bool allowRetry = true}) async {
    if (userNotifier.value == null) {
      await _hydrateUserFromOfflineCache();
    }
    if (userNotifier.value == null && allowRetry) {
      final refreshed = await _tryRefreshAccessToken();
      if (refreshed) {
        await _loadProfileFromApi(isRetry: true);
        return;
      }
    }
    if (userNotifier.value != null && hasStoredSession) {
      return;
    }
    await signOut(silent: true);
  }

  Future<void> _applyRemoteUser(UserModel user) async {
    if (user.status == 'banned') {
      await _onBanned();
      return;
    }
    userNotifier.value = user;
    await _saveUserLocally(user);
    _syncSessionCubit();
    _ensureBanPoll();
  }

  void _syncSessionCubit() {
    _cubit?.hydrate();
  }

  Future<void> _saveUserLocally(UserModel user) async {
    try {
      await _localDb.saveUser(user.toMap());
    } catch (e) {
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';


      final result = await _authRemote.login(email: email, password: password);
      if (result case ApiFailure(:final failure)) {
        errorMessage.value = failure.message;
        return;
      }
      if (result case ApiSuccess(:final data)) {
        await _tokens.setTokens(
          accessToken: data.tokens.access,
          refreshToken: data.tokens.refresh,
        );
        _tokenRefresher.reset();
        final user = UserModel.fromApi(data.user);
        await _applyRemoteUser(user);

        if (userNotifier.value == null) {
          return;
        }

        await _cubit?.applyTokens(
          accessToken: data.tokens.access,
          refreshToken: data.tokens.refresh,
        );


        showAppSnackBar(
          title: 'Success',
          message: 'Welcome back!',
        );
        _getUserRoleAndNavigate(user.role);
      }
    } catch (e, st) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final result = await _authRemote.requestPasswordReset(email);
      if (result case ApiFailure(:final failure)) {
        errorMessage.value = failure.message;
        return;
      }
      showAppSnackBar(
        title: 'Email Sent',
        message:
            'If an account exists, password reset instructions were sent.',
      );
      AppNavigation.back();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required String employeeCode,
    required String role,
    required String mobile,
    String? sitingLocation,
    required String reportingManagerId,
  }) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      if (!isAdmin) {
        errorMessage.value =
            'Only admin accounts can create users (your role: ${userRole ?? 'unknown'}).';
        return;
      }

      final result = await _usersRemote.createUser(
        email: email,
        password: password,
        name: name,
        employeeCode: employeeCode,
        role: role,
        mobile: mobile,
        sitingLocation: sitingLocation,
        reportingManagerId: reportingManagerId,
      );

      if (result case ApiFailure(:final failure)) {
        errorMessage.value = failure.message;
        showAppSnackBar(
          title: 'Error',
          message: failure.message,
          backgroundColor: const Color(0xFFEF4444),
        );
        return;
      }

      if (result case ApiSuccess(:final data)) {
        showAppSnackBar(
          title: 'Success',
          message: 'User "${data.name}" created successfully.',
          backgroundColor: const Color(0xFF10B981),
        );
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signOut({bool silent = false}) async {
    try {
      final uid = userNotifier.value?.uid;

      _banPoll?.cancel();
      _banPoll = null;

      _tokenRefresher.invalidate();

      await _tokens.clear();
      await _localDb.clearActiveTripId();
      userNotifier.value = null;
      _sessionReadyFuture = null;

      if (uid != null && uid.isNotEmpty) {
        try {
          await _localDb.deleteUser(uid);
        } catch (_) {}
      }

      await _cubit?.signOut();

      if (!silent) {
        _navigateToLogin();
      }
    } catch (e) {
      errorMessage.value = 'Failed to sign out: $e';
    }
  }

  void _getUserRoleAndNavigate(String role) {
    switch (role) {
      case AppConstants.adminRole:
        AppNavigation.offAll(AppRoutes.adminDashboard);
        break;
      case AppConstants.managerRole:
        AppNavigation.offAll(AppRoutes.managerHome);
        break;
      case AppConstants.userRole:
        AppNavigation.offAll(AppRoutes.userHome);
        break;
      default:
        errorMessage.value = 'Invalid user role';
        break;
    }
  }

  void _navigateToLogin() {
    AppNavigation.offAll(AppRoutes.login);
  }

  void clearError() {
    errorMessage.value = '';
  }

  Future<void> checkUserBanStatus() async {
    await ensureSessionReady();
  }

  void _ensureBanPoll() {
    _banPoll ??= Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!isAuthenticated) return;
      await _loadProfileFromApi(silent: true);
    });
  }

  Future<void> _onBanned() async {
    errorMessage.value =
        'Your account has been banned. Please contact the administrator.';
    await signOut(silent: true);
    showAppSnackBar(
      title: 'Account Banned',
      message:
          'Your account has been banned. Please contact the administrator.',
      backgroundColor: const Color(0xFFEF4444),
      duration: const Duration(seconds: 5),
    );
    _navigateToLogin();
  }
}
