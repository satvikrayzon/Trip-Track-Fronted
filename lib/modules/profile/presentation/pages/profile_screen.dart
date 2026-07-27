import 'package:flutter/material.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';

/// Profile Screen
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = ServiceLocator.I.get<AppAuthController>();
    final user = authController.currentUserData;

    return HeaderWidget(
      headerChild: CustomAppBar(
        title: 'My Profile',
        showBackButton: true,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppConstants.defaultPadding.scp(context)),
        child: Column(
          children: [
            const SizedBox(height: AppConstants.defaultPadding),

            // Profile header
            AppCard(
              type: AppCardType.elevatedCard,
              child: Column(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      user?.name.isNotEmpty ?? false ? user!.name[0].toUpperCase() : 'U',
                      style: AppTextStyles.displayLarge.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    user?.name ?? 'User',
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: authController.isAdmin
                          ? AppColors.error.withOpacity(0.1)
                          : AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: authController.isAdmin
                            ? AppColors.error.withOpacity(0.3)
                            : AppColors.success.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      user?.role.toUpperCase() ?? 'USER',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: authController.isAdmin ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.largePadding),

            // Personal information
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Personal Information',
                style: AppTextStyles.titleLarge,
              ),
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            AppCard(
              type: AppCardType.elevatedCard,
              child: Column(
                children: [
                  _buildInfoRow(
                    Icons.email,
                    'Email',
                    user?.email ?? '',
                  ),
                  const Divider(),
                  _buildInfoRow(
                    Icons.badge,
                    'Employee Code',
                    user?.employeeCode ?? '',
                  ),
                  const Divider(),
                  _buildInfoRow(
                    Icons.fingerprint,
                    'User ID',
                    user?.uid ?? '',
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.largePadding),

            // Account actions
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account Actions',
                style: AppTextStyles.titleLarge,
              ),
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            AppCard(
              type: AppCardType.elevatedCard,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_reset, color: AppColors.warning),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      showAppSnackBar(
                        title: 'Info',
                        message:
                            'Password change feature coming soon. Use forgot password for now.',
                        backgroundColor: AppColors.info,
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: AppColors.error),
                    title: const Text('Delete Account'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showDeleteAccountDialog(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.largePadding),

            // Logout button
            AppButton(
              text: 'Logout',
              type: AppButtonType.outline,
              size: AppButtonSize.large,
              icon: Icons.logout,
              onPressed: () => authController.signOut(),
              customColor: AppColors.error,
            ),

            const SizedBox(height: AppConstants.largePadding),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete Account?',
                style: AppTextStyles.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone. All your data will be permanently deleted.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        showAppSnackBar(
                          title: 'Info',
                          message:
                              'Account deletion is disabled for safety. Contact admin.',
                          backgroundColor: AppColors.info,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
