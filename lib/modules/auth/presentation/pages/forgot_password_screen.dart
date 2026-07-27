import 'package:flutter/material.dart';

import '../../../../core/app_messenger.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_input_field.dart';
import '../controllers/app_auth_controller.dart';

/// Forgot password screen with email input
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late final AppAuthController _authController;

  @override
  void initState() {
    super.initState();
    _initAuthController();
  }

  void _initAuthController() {
    _authController = ServiceLocator.I.get<AppAuthController>();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleForgotPassword() async {
    if (_formKey.currentState?.validate() ?? false) {
      await _authController.sendPasswordResetEmail(_emailController.text.trim());
      
      final error = _authController.errorMessage.value;
      if (error.isNotEmpty) {
        showAppSnackBar(
          title: 'Error',
          message: error,
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          textColor: Colors.white,
        );
      }
    }
  }

  void _goBack() {
    AppNavigation.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Header
              _buildHeader(),

              const SizedBox(height: 40),

              // Form
              _buildForm(),

              const Spacer(),

              // Back to login
              _buildBackToLogin(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_reset,
            size: 40,
            color: AppColors.primary,
          ),
        ),

        const SizedBox(height: 24),

        // Title
        const Text(
          'Forgot Password?',
          style: AppTextStyles.headlineLarge,
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        // Description
        Text(
          'No worries! Enter your email address and we\'ll send you instructions to reset your password.',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return AppCard(
      type: AppCardType.elevatedCard,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email field
            AppInputField(
              label: 'Email Address',
              hint: 'Enter your registered email',
              controller: _emailController,
              type: AppInputType.email,
              prefixIcon: Icons.email_outlined,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email address';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),

            const SizedBox(height: AppConstants.largePadding),

            // Send button
            ValueListenableBuilder<bool>(
              valueListenable: _authController.isLoading,
              builder: (context, isLoading, _) => AppButton(
                  text: 'Send Reset Instructions',
                  type: AppButtonType.primary,
                  size: AppButtonSize.large,
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _handleForgotPassword,
                  icon: Icons.send,
                )),

            const SizedBox(height: AppConstants.defaultPadding),

            ValueListenableBuilder<String>(
              valueListenable: _authController.errorMessage,
              builder: (context, errorMessage, _) {
              if (errorMessage.isNotEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage,
                          style: AppTextStyles.errorText,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBackToLogin() {
    return Column(
      children: [
        TextButton(
          onPressed: _goBack,
          child: Text(
            'Remember your password? Sign in',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: AppConstants.defaultPadding),

        // Support info
        Container(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(color: AppColors.info.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.help_outline,
                color: AppColors.info,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If you don\'t receive an email, check your spam folder or contact support.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
