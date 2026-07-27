import 'package:flutter/material.dart';

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
import '../../../offline_sync/presentation/controllers/sync_controller.dart';

/// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = ServiceLocator.I.get<AppAuthController>();
    final syncController = ServiceLocator.I.get<SyncController>();

    return HeaderWidget(
      headerChild: CustomAppBar(
        title: 'Settings',
        showBackButton: true,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppConstants.defaultPadding.scp(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account section
            const Text(
              'Account',
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            AppCard(
              onTap: () {},
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      authController.currentUserData?.name.isNotEmpty ?? false
                          ? authController.currentUserData!.name[0].toUpperCase()
                          : 'U',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authController.currentUserData?.name ?? 'User',
                          style: AppTextStyles.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          authController.currentUserData?.email ?? '',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: authController.isAdmin
                          ? AppColors.error.withOpacity(0.1)
                          : AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      authController.userRole?.toUpperCase() ?? 'USER',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: authController.isAdmin ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.largePadding),

            // Sync section
            const Text(
              'Data & Sync',
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            AppCard(
              child: Column(
                children: [
                  _buildSettingRow(
                    Icons.sync,
                    'Sync Status',
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        syncController.isSyncing,
                        syncController.pendingItems,
                      ]),
                      builder: (context, _) => Text(
                          syncController.syncStatusText,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ),
                  ),
                  const Divider(),
                  _buildSettingRow(
                    Icons.pending_actions,
                    'Pending Items',
                    ValueListenableBuilder<int>(
                      valueListenable: syncController.pendingItems,
                      builder: (context, pending, _) => Text(
                          pending.toString(),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.refresh, color: AppColors.primary),
                    title: const Text('Force Sync Now'),
                    trailing: ValueListenableBuilder<bool>(
                      valueListenable: syncController.isSyncing,
                      builder: (context, isSyncing, _) => isSyncing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                    onTap: () => syncController.forceSync(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.largePadding),

            // App section
            const Text(
              'App Information',
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppConstants.defaultPadding),

            AppCard(
              child: Column(
                children: [
                  _buildSettingRow(
                    Icons.info_outline,
                    'Version',
                    const Text(AppConstants.appVersion, style: AppTextStyles.bodyMedium),
                  ),
                  const Divider(),
                  _buildSettingRow(
                    Icons.business,
                    'Company',
                    const Text('Rayzon Solar', style: AppTextStyles.bodyMedium),
                  )
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

  Widget _buildSettingRow(IconData icon, String title, Widget trailing) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
    );
  }
}
