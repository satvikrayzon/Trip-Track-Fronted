import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';
import '../controllers/admin_user_list_controller.dart';

/// Admin User List Screen - Modern Design
class AdminUserListScreen extends StatefulWidget {
  const AdminUserListScreen({super.key});

  @override
  State<AdminUserListScreen> createState() => _AdminUserListScreenState();
}

class _AdminUserListScreenState extends State<AdminUserListScreen> {
  late final AdminUserListController _controller;
  late final AppAuthController _auth;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AdminUserListController();
    _controller.start();
    _auth = ServiceLocator.I.get<AppAuthController>();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HeaderWidget(
      headerChild: CustomAppBar(
        title: 'Manage Users',
        showBackButton: true,
        action: [
          if (_auth.isAdmin)
            GestureDetector(
              onTap: () async {
                final created = await AppNavigation.to<bool>(
                  AppRoutes.adminCreateUser,
                );
                if (created == true) {
                  await _controller.refresh();
                }
              },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.scp(context), vertical: 8.scp(context)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20.scp(context)),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_add_rounded,
                    color: Colors.white,
                    size: 16.scp(context),
                  ),
                  SizedBox(width: 6.scp(context)),
                  Text(
                    'Add User',
                    style: FontUtilities.style(
                      fontSize: 12.scp(context),
                      fontColor: Colors.white,
                      fontWeight: FWT.semiBold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search and filter bar
          Container(
            padding: EdgeInsets.all(16.scp(context)),
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  style: FontUtilities.style(
                    fontSize: 14.scp(context),
                    fontColor: const Color(0xFF1F2937),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or employee code...',
                    hintStyle: FontUtilities.style(
                      fontSize: 14.scp(context),
                      fontColor: const Color(0xFF9CA3AF),
                      fontWeight: FWT.regular,
                    ),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF6B7280)),
                            onPressed: () {
                              _searchController.clear();
                              _controller.searchUsers('');
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.scp(context), vertical: 12.scp(context)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.scp(context)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    _controller.searchUsers(value);
                    setState(() {});
                  },
                ),

                SizedBox(height: 12.scp(context)),

                // Filter chips
                ValueListenableBuilder<String>(
                  valueListenable: _controller.filterRole,
                  builder: (context, _, __) => ValueListenableBuilder<String>(
                    valueListenable: _controller.filterStatus,
                    builder: (context, ___, ____) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all', 'role'),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Users', 'user', 'role'),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Admins', 'admin', 'role'),
                          SizedBox(width: 16.scp(context)),
                          Container(
                            width: 1,
                            height: 24.scp(context),
                            color: const Color(0xFFE5E7EB),
                          ),
                          SizedBox(width: 16.scp(context)),
                          _buildFilterChip('Active', 'active', 'status'),
                          SizedBox(width: 8.scp(context)),
                          _buildFilterChip('Banned', 'banned', 'status'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // User count
          ValueListenableBuilder<List<UserModel>>(
            valueListenable: _controller.users,
            builder: (context, users, _) => Container(
                padding: EdgeInsets.symmetric(horizontal: 16.scp(context), vertical: 12.scp(context)),
                color: const Color(0xFFF9FAFB),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, size: 18.scp(context), color: const Color(0xFF6B7280)),
                    SizedBox(width: 8.scp(context)),
                    Text(
                      '${users.length} ${users.length == 1 ? 'user' : 'users'} found',
                      style: FontUtilities.style(
                        fontSize: 13.scp(context),
                        fontColor: const Color(0xFF6B7280),
                        fontWeight: FWT.medium,
                      ),
                    ),
                  ],
                ),
              )),

          // User list
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _controller.isLoading,
                _controller.users,
              ]),
              builder: (context, _) {
              if (_controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = _controller.users.value;
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64.scp(context),
                        color: const Color(0xFF9CA3AF),
                      ),
                      SizedBox(height: 16.scp(context)),
                      Text(
                        'No users found',
                        style: FontUtilities.style(
                          fontSize: 18.scp(context),
                          fontColor: const Color(0xFF4B5563),
                          fontWeight: FWT.semiBold,
                        ),
                      ),
                      SizedBox(height: 8.scp(context)),
                      Text(
                        _searchController.text.isNotEmpty ? 'Try adjusting your search' : 'Create your first user',
                        style: FontUtilities.style(
                          fontSize: 14.scp(context),
                          fontColor: const Color(0xFF9CA3AF),
                          fontWeight: FWT.regular,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _controller.refresh,
                child: ListView.builder(
                  padding: EdgeInsets.all(16.scp(context)),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _buildUserCard(user, context);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String type) {
    final isSelected = type == 'role'
        ? _controller.filterRole.value == value
        : _controller.filterStatus.value == value;

    return GestureDetector(
      onTap: () {
        if (type == 'role') {
          _controller.filterByRole(value);
        } else {
          _controller.filterByStatus(value);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.scp(context), vertical: 8.scp(context)),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4B8E97) : Colors.white,
          borderRadius: BorderRadius.circular(20.scp(context)),
          border: Border.all(
            color: isSelected ? const Color(0xFF4B8E97) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: FontUtilities.style(
            fontSize: 13.scp(context),
            fontColor: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: isSelected ? FWT.semiBold : FWT.medium,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(UserModel user, BuildContext context) {
    final isBanned = user.status == 'banned';

    return Container(
      margin: EdgeInsets.only(bottom: 12.scp(context)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.scp(context)),
        border: Border.all(
          color: isBanned ? const Color(0xFFEF4444).withOpacity(0.3) : const Color(0xFFE5E7EB),
          width: isBanned ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.scp(context)),
          onTap: () => _showUserDetailsDialog(user, context),
          child: Padding(
            padding: EdgeInsets.all(16.scp(context)),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56.scp(context),
                  height: 56.scp(context),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isBanned
                          ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                          : user.role == 'admin'
                              ? [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)]
                              : [const Color(0xFF4B8E97), const Color(0xFF095763)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isBanned ? const Color(0xFFEF4444) : const Color(0xFF4B8E97)).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                      style: FontUtilities.style(
                        fontSize: 24.scp(context),
                        fontColor: Colors.white,
                        fontWeight: FWT.bold,
                      ),
                    ),
                  ),
                ),

                SizedBox(width: 16.scp(context)),

                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.name,
                              style: FontUtilities.style(
                                fontSize: 16.scp(context),
                                fontColor: const Color(0xFF1F2937),
                                fontWeight: FWT.semiBold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8.scp(context)),
                          // Role badge
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.scp(context), vertical: 4.scp(context)),
                            decoration: BoxDecoration(
                              color: user.role == 'admin'
                                  ? const Color(0xFF8B5CF6).withOpacity(0.1)
                                  : const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6.scp(context)),
                            ),
                            child: Text(
                              user.role.toUpperCase(),
                              style: FontUtilities.style(
                                fontSize: 10.scp(context),
                                fontColor: user.role == 'admin' ? const Color(0xFF8B5CF6) : const Color(0xFF10B981),
                                fontWeight: FWT.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.scp(context)),
                      Text(
                        user.email,
                        style: FontUtilities.style(
                          fontSize: 13.scp(context),
                          fontColor: const Color(0xFF6B7280),
                          fontWeight: FWT.regular,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.scp(context)),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 12.scp(context), color: const Color(0xFF9CA3AF)),
                          SizedBox(width: 4.scp(context)),
                          Text(
                            user.employeeCode,
                            style: FontUtilities.style(
                              fontSize: 12.scp(context),
                              fontColor: const Color(0xFF9CA3AF),
                              fontWeight: FWT.regular,
                            ),
                          ),
                          if (isBanned) ...[
                            SizedBox(width: 12.scp(context)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.scp(context), vertical: 2.scp(context)),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(4.scp(context)),
                              ),
                              child: Text(
                                'BANNED',
                                style: FontUtilities.style(
                                  fontSize: 10.scp(context),
                                  fontColor: Colors.white,
                                  fontWeight: FWT.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 8.scp(context)),

                // Action button
                Icon(
                  Icons.more_vert,
                  size: 20.scp(context),
                  color: const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUserDetailsDialog(UserModel user, BuildContext context) {
    final isBanned = user.status == 'banned';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.scp(context)),
        ),
        child: Container(
          constraints: BoxConstraints(maxWidth: 400.scp(context)),
          padding: EdgeInsets.all(24.scp(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with avatar
              Container(
                width: 80.scp(context),
                height: 80.scp(context),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isBanned
                        ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                        : user.role == 'admin'
                            ? [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)]
                            : [const Color(0xFF4B8E97), const Color(0xFF095763)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isBanned ? const Color(0xFFEF4444) : const Color(0xFF4B8E97)).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: FontUtilities.style(
                      fontSize: 36.scp(context),
                      fontColor: Colors.white,
                      fontWeight: FWT.bold,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16.scp(context)),

              // Name
              Text(
                user.name,
                style: FontUtilities.style(
                  fontSize: 22.scp(context),
                  fontColor: const Color(0xFF1F2937),
                  fontWeight: FWT.bold,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 8.scp(context)),

              // Role and status badges
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.scp(context), vertical: 6.scp(context)),
                    decoration: BoxDecoration(
                      color: user.role == 'admin'
                          ? const Color(0xFF8B5CF6).withOpacity(0.1)
                          : const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.scp(context)),
                    ),
                    child: Text(
                      user.role.toUpperCase(),
                      style: FontUtilities.style(
                        fontSize: 12.scp(context),
                        fontColor: user.role == 'admin' ? const Color(0xFF8B5CF6) : const Color(0xFF10B981),
                        fontWeight: FWT.bold,
                      ),
                    ),
                  ),
                  if (isBanned) ...[
                    SizedBox(width: 8.scp(context)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.scp(context), vertical: 6.scp(context)),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(8.scp(context)),
                      ),
                      child: Text(
                        'BANNED',
                        style: FontUtilities.style(
                          fontSize: 12.scp(context),
                          fontColor: Colors.white,
                          fontWeight: FWT.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              SizedBox(height: 24.scp(context)),

              // Divider
              Container(
                height: 1,
                color: const Color(0xFFE5E7EB),
              ),

              SizedBox(height: 24.scp(context)),

              // User details
              _buildDetailRow(Icons.email_outlined, 'Email', user.email, context),
              SizedBox(height: 16.scp(context)),
              _buildDetailRow(Icons.badge_outlined, 'Employee Code', user.employeeCode, context),
              SizedBox(height: 16.scp(context)),
              if (user.mobile.isNotEmpty)
                _buildDetailRow(Icons.phone_android_outlined, 'Mobile', user.mobile, context),
              if (user.mobile.isNotEmpty) SizedBox(height: 16.scp(context)),
              if (user.sitingLocation.isNotEmpty)
                _buildDetailRow(Icons.location_city_outlined, 'Siting Location', user.sitingLocation, context),
              if (user.sitingLocation.isNotEmpty) SizedBox(height: 16.scp(context)),
              if (user.reportingManagerName != null && user.reportingManagerName!.isNotEmpty)
                _buildDetailRow(Icons.supervisor_account_outlined, 'Reporting Manager', user.reportingManagerName!, context),
              if (user.reportingManagerName != null && user.reportingManagerName!.isNotEmpty)
                SizedBox(height: 16.scp(context)),
              _buildDetailRow(Icons.fingerprint, 'User ID', user.uid, context),

              SizedBox(height: 24.scp(context)),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.scp(context)),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.scp(context)),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: FontUtilities.style(
                          fontSize: 14.scp(context),
                          fontColor: const Color(0xFF6B7280),
                          fontWeight: FWT.semiBold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.scp(context)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        final updated = await AppNavigation.to<bool>(
                          AppRoutes.adminCreateUser,
                          arguments: user,
                        );
                        if (updated == true && mounted) {
                          await _controller.refresh();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4B8E97),
                        padding: EdgeInsets.symmetric(vertical: 14.scp(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.scp(context)),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Edit User',
                        style: FontUtilities.style(
                          fontSize: 14.scp(context),
                          fontColor: Colors.white,
                          fontWeight: FWT.semiBold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.scp(context)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    if (isBanned) {
                      _confirmUnbanUser(user, context);
                    } else {
                      _confirmBanUser(user, context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    padding: EdgeInsets.symmetric(vertical: 14.scp(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.scp(context)),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isBanned ? 'Unban User' : 'Ban User',
                    style: FontUtilities.style(
                      fontSize: 14.scp(context),
                      fontColor: Colors.white,
                      fontWeight: FWT.semiBold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.scp(context)),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8.scp(context)),
          ),
          child: Icon(icon, size: 18.scp(context), color: const Color(0xFF6B7280)),
        ),
        SizedBox(width: 12.scp(context)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: FontUtilities.style(
                  fontSize: 12.scp(context),
                  fontColor: const Color(0xFF9CA3AF),
                  fontWeight: FWT.medium,
                ),
              ),
              SizedBox(height: 2.scp(context)),
              Text(
                value,
                style: FontUtilities.style(
                  fontSize: 14.scp(context),
                  fontColor: const Color(0xFF1F2937),
                  fontWeight: FWT.medium,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmBanUser(UserModel user, BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.scp(context)),
        ),
        title: Text(
          'Ban User?',
          style: FontUtilities.style(
            fontSize: 18.scp(context),
            fontColor: const Color(0xFF1F2937),
            fontWeight: FWT.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to ban ${user.name}? They will not be able to log in until unbanned.',
          style: FontUtilities.style(
            fontSize: 14.scp(context),
            fontColor: const Color(0xFF6B7280),
            fontWeight: FWT.regular,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: FontUtilities.style(
                fontSize: 14.scp(context),
                fontColor: const Color(0xFF6B7280),
                fontWeight: FWT.semiBold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _controller.banUser(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.scp(context)),
              ),
              elevation: 0,
            ),
            child: Text(
              'Ban User',
              style: FontUtilities.style(
                fontSize: 14.scp(context),
                fontColor: Colors.white,
                fontWeight: FWT.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmUnbanUser(UserModel user, BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.scp(context)),
        ),
        title: Text(
          'Unban User?',
          style: FontUtilities.style(
            fontSize: 18.scp(context),
            fontColor: const Color(0xFF1F2937),
            fontWeight: FWT.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to unban ${user.name}? They will be able to log in again.',
          style: FontUtilities.style(
            fontSize: 14.scp(context),
            fontColor: const Color(0xFF6B7280),
            fontWeight: FWT.regular,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: FontUtilities.style(
                fontSize: 14.scp(context),
                fontColor: const Color(0xFF6B7280),
                fontWeight: FWT.semiBold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _controller.unbanUser(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.scp(context)),
              ),
              elevation: 0,
            ),
            child: Text(
              'Unban User',
              style: FontUtilities.style(
                fontSize: 14.scp(context),
                fontColor: Colors.white,
                fontWeight: FWT.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
