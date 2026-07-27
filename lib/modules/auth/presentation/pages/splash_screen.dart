import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/navigation_helper.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../controllers/app_auth_controller.dart';

/// Splash screen with app branding and loading animation
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    unawaited(_runStartupSequence());
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Initialize animations
  void _initAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _animationController.forward();
  }

  /// Waits for [AppAuthController.ensureSessionReady] (usually already done in
  /// [main]) then routes to login or the role home screen.
  Future<void> _runStartupSequence() async {
    final auth = ServiceLocator.I.has<AppAuthController>()
        ? ServiceLocator.I.get<AppAuthController>()
        : null;

    // No saved session — skip network and open login on first frame.
    if (auth == null || !auth.hasStoredSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(AppPaths.login);
      });
      return;
    }

    await _ensureAuthReady();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateAfterSplash(context);
    });
  }

  Future<void> _ensureAuthReady() async {
    try {
      await ServiceLocator.I
          .get<AppAuthController>()
          .ensureSessionReady()
          .timeout(const Duration(seconds: 6));
    } catch (e) {
    }
  }

  void _navigateAfterSplash(BuildContext context) {
    try {
      if (ServiceLocator.I.has<AppAuthController>()) {
        final authController = ServiceLocator.I.get<AppAuthController>();
        AppNavigator.goAfterSplash(
          context: context,
          isAuthenticated: authController.isAuthenticated,
          role: authController.userRole,
        );
      } else {
        context.go(AppPaths.login);
      }
    } catch (e) {
      context.go(AppPaths.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.solar_power,
                                size: 60,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              AppConstants.appName,
                              style: AppTextStyles.brandName.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Employee Travel & Kilometer Log',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 80),
                            const SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Initializing...',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppConstants.largePadding),
                    child: Column(
                      children: [
                        Text(
                          'Version ${AppConstants.appVersion}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textDisabled,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '© 2024 Rayzon Solar',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
