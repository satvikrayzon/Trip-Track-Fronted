import 'package:flutter/foundation.dart';



import '../../../../core/app_messenger.dart';

import '../../../../core/routes/app_routes.dart';

import '../../data/models/user_model.dart';



/// Mock authentication controller for development/testing

class MockAuthController {

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<String> errorMessage = ValueNotifier<String>('');

  final ValueNotifier<UserModel?> currentUser =

      ValueNotifier<UserModel?>(null);



  UserModel? get currentUserData => currentUser.value;

  bool get isAuthenticated => currentUser.value != null;

  String? get userRole => currentUser.value?.role;

  bool get isAdmin => userRole == 'admin';



  void dispose() {

    isLoading.dispose();

    errorMessage.dispose();

    currentUser.dispose();

  }



  /// Sign in with email and password (mock implementation)

  Future<void> signIn(String email, String password) async {

    try {

      isLoading.value = true;

      errorMessage.value = '';



      await Future.delayed(const Duration(seconds: 1));



      if (email.isEmpty || password.isEmpty) {

        errorMessage.value = 'Please enter both email and password';

        return;

      }



      if (!email.contains('@')) {

        errorMessage.value = 'Please enter a valid email address';

        return;

      }



      if (password.length < 6) {

        errorMessage.value = 'Password must be at least 6 characters';

        return;

      }



      final mockUser = UserModel(

          uid: 'mock_user_${DateTime.now().millisecondsSinceEpoch}',

          email: email,

          name: 'Test User',

          employeeCode: 'EMP001',

          role: email.contains('admin') ? 'admin' : 'user');



      currentUser.value = mockUser;



      showAppSnackBar(title: 'Success', message: 'Welcome back!');



      _navigateBasedOnRole(mockUser.role);

    } catch (e) {

      errorMessage.value = 'An unexpected error occurred: $e';

    } finally {

      isLoading.value = false;

    }

  }



  /// Send password reset email (mock implementation)

  Future<void> sendPasswordResetEmail(String email) async {

    try {

      isLoading.value = true;

      errorMessage.value = '';



      await Future.delayed(const Duration(seconds: 1));



      if (email.isEmpty) {

        errorMessage.value = 'Please enter your email address';

        return;

      }

      if (!email.contains('@')) {

        errorMessage.value = 'Please enter a valid email address';

        return;

      }

      showAppSnackBar(

        title: 'Email Sent',

        message: 'Password reset instructions have been sent to your email.',

      );

      AppNavigation.back();

    } catch (e) {

      errorMessage.value = 'Failed to send reset email: $e';

    } finally {

      isLoading.value = false;

    }

  }



  /// Create new user (admin only) - mock implementation

  Future<void> createUser({

    required String email,

    required String password,

    required String name,

    required String employeeCode,

    required String role,

    required String mobile,

    required String sitingLocation,

    String? reportingManagerId,

  }) async {

    try {

      isLoading.value = true;

      errorMessage.value = '';



      await Future.delayed(const Duration(seconds: 1));



      if (email.isEmpty || password.isEmpty || name.isEmpty || employeeCode.isEmpty) {

        errorMessage.value = 'Please fill in all required fields';

        return;

      }



      if (!email.contains('@')) {

        errorMessage.value = 'Please enter a valid email address';

        return;

      }



      if (password.length < 6) {

        errorMessage.value = 'Password must be at least 6 characters';

        return;

      }



      showAppSnackBar(

        title: 'Success',

        message: 'User created successfully',

      );

    } catch (e) {

      errorMessage.value = 'Failed to create user: $e';

    } finally {

      isLoading.value = false;

    }

  }



  /// Sign out

  Future<void> signOut() async {

    try {

      currentUser.value = null;

      _navigateToLogin();

    } catch (e) {

      errorMessage.value = 'Failed to sign out: $e';

    }

  }



  /// Navigate based on user role

  void _navigateBasedOnRole(String role) {

    switch (role) {

      case 'admin':

        AppNavigation.offAll(AppRoutes.adminDashboard);

        break;

      case 'user':

        AppNavigation.offAll(AppRoutes.userHome);

        break;

      default:

        errorMessage.value = 'Invalid user role';

        break;

    }

  }



  /// Navigate to login

  void _navigateToLogin() {

    AppNavigation.offAll(AppRoutes.login);

  }



  /// Clear error message

  void clearError() {

    errorMessage.value = '';

  }

}


