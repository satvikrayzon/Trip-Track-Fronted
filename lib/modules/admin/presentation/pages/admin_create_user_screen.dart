import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/device_utils.dart';
import '../../../../core/utils/font_utils.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../../auth/data/datasources/users_remote_datasource.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/controllers/app_auth_controller.dart';

/// Admin-only create user — matches admin dashboard / user list UI.
class AdminCreateUserScreen extends StatefulWidget {
  final UserModel? userToEdit;

  const AdminCreateUserScreen({super.key, this.userToEdit});

  @override
  State<AdminCreateUserScreen> createState() => _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends State<AdminCreateUserScreen> {
  static const _roleOptions = <(String, String)>[
    (AppConstants.userRole, 'Field Employee'),
    (AppConstants.managerRole, 'Manager'),
    (AppConstants.adminRole, 'Admin'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _employeeCodeController = TextEditingController();
  final _mobileController = TextEditingController();
  final _sitingLocationController = TextEditingController();

  String _selectedRole = AppConstants.userRole;
  String? _selectedReportingManagerId;
  List<UserModel> _reportingManagers = [];
  bool _loadingManagers = true;
  bool _isSubmitting = false;
  String? _submitError;
  String? _managersLoadError;

  late final AppAuthController _auth;
  late final UsersRemoteDataSource _usersApi;

  @override
  void initState() {
    super.initState();
    _auth = ServiceLocator.I.get<AppAuthController>();
    _usersApi = ServiceLocator.I.get<UsersRemoteDataSource>();
    _loadReportingManagers();

    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _nameController.text = user.name;
      _emailController.text = user.email;
      _employeeCodeController.text = user.employeeCode;
      _mobileController.text = user.mobile;
      _sitingLocationController.text = user.sitingLocation;
      _selectedRole = user.role;
      _selectedReportingManagerId = user.reportingManagerId;
    }
  }

  Future<void> _loadReportingManagers() async {
    setState(() {
      _loadingManagers = true;
      _managersLoadError = null;
    });

    final managersResult = await _usersApi.fetchReportingManagers();
    final usersResult = await _usersApi.listUsers(limit: 100);
    if (!mounted) return;

    final merged = <UserModel>[];

    void addEligible(UserModel user) {
      if (user.status == 'banned') return;
      if (user.role != AppConstants.adminRole &&
          user.role != AppConstants.managerRole) {
        return;
      }
      if (widget.userToEdit != null && _isSameUser(user, widget.userToEdit!)) return;
      if (merged.any((u) => _isSameUser(u, user))) return;
      merged.add(user);
    }

    if (managersResult case ApiSuccess(:final data)) {
      for (final user in data) {
        addEligible(user);
      }
    }

    // Reporting-managers API may return only managers — always merge admins too.
    if (usersResult case ApiSuccess(:final data)) {
      for (final user in data) {
        addEligible(user);
      }
    }

    final eligible = _mergeCurrentUserAsReportingManager(merged)
      ..sort((a, b) => a.name.compareTo(b.name));

    final bothFailed =
        managersResult is ApiFailure && usersResult is ApiFailure;

    setState(() {
      _loadingManagers = false;
      _reportingManagers = eligible;
      _managersLoadError = eligible.isEmpty && bothFailed
          ? (managersResult as ApiFailure).failure.message
          : null;
      if (widget.userToEdit == null) {
        _selectedReportingManagerId = _defaultReportingManagerId(eligible);
      }
    });
  }

  bool _isSameUser(UserModel a, UserModel b) {
    if (a.apiId.isNotEmpty && a.apiId == b.apiId) return true;
    if (a.uid.isNotEmpty && a.uid == b.uid) return true;
    return false;
  }

  /// Prefer the signed-in admin as default reporting manager (bootstrap case).
  String? _defaultReportingManagerId(List<UserModel> eligible) {
    if (eligible.isEmpty) return null;

    final current = _auth.currentUserData;
    if (current != null) {
      for (final user in eligible) {
        if (_isSameUser(user, current)) return user.apiId;
      }
    }

    if (_selectedReportingManagerId != null &&
        eligible.any((u) => u.apiId == _selectedReportingManagerId)) {
      return _selectedReportingManagerId;
    }

    return eligible.first.apiId;
  }

  /// API lists often omit the signed-in admin — include them so the first
  /// manager/employee can be created without a chicken-and-egg deadlock.
  List<UserModel> _mergeCurrentUserAsReportingManager(List<UserModel> eligible) {
    final current = _auth.currentUserData;
    if (current == null || current.status == 'banned') return eligible;
    if (current.role != AppConstants.adminRole &&
        current.role != AppConstants.managerRole) {
      return eligible;
    }
    if (eligible.any((u) => _isSameUser(u, current))) return eligible;
    return [current, ...eligible];
  }

  String _reportingManagerLabel(UserModel user) {
    final roleLabel = switch (user.role) {
      AppConstants.adminRole => 'Admin',
      AppConstants.managerRole => 'Manager',
      _ => user.role,
    };
    return '${user.name} (${user.employeeCode}) — $roleLabel';
  }

  bool get _requiresReportingManager => _reportingManagers.isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _employeeCodeController.dispose();
    _mobileController.dispose();
    _sitingLocationController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateUser() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_requiresReportingManager &&
        (_selectedReportingManagerId == null ||
            _selectedReportingManagerId!.isEmpty)) {
      setState(() {
        _submitError = 'Please select a reporting manager.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final siting = _sitingLocationController.text.trim();
    final isEdit = widget.userToEdit != null;

    final ApiResult<dynamic> result;
    if (isEdit) {
      result = await _usersApi.updateUser(widget.userToEdit!.uid, {
        'email': _emailController.text.trim(),
        'name': _nameController.text.trim(),
        'employeeCode': _employeeCodeController.text.trim(),
        'role': _selectedRole,
        'mobile': _mobileController.text.trim(),
        'sitingLocation': siting.isNotEmpty ? siting : '',
        'reportingManagerId': _selectedReportingManagerId ?? '',
      });
    } else {
      result = await _usersApi.createUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        employeeCode: _employeeCodeController.text.trim(),
        role: _selectedRole,
        mobile: _mobileController.text.trim(),
        sitingLocation: siting.isEmpty ? null : siting,
        reportingManagerId: _selectedReportingManagerId,
      );
    }

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    switch (result) {
      case ApiFailure(:final failure):
        final msg = failure.statusCode == 403
            ? 'Insufficient role — sign in with an admin account (${failure.message}).'
            : failure.message;
        setState(() => _submitError = msg);
        showAppSnackBar(
          title: isEdit ? 'Could not update user' : 'Could not create user',
          message: msg,
          backgroundColor: AppColors.error,
        );
      case ApiSuccess():
        showAppSnackBar(
          title: 'Success',
          message: isEdit
              ? 'User details updated successfully.'
              : 'User "${_nameController.text.trim()}" created successfully.',
          backgroundColor: const Color(0xFF10B981),
        );
        if (mounted) context.pop(true);
    }
  }

  String? _validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter mobile number';
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      return 'Enter exactly 10 digits';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isAdmin) {
      return HeaderWidget(
        headerChild: CustomAppBar(
          title: 'Create New User',
          showBackButton: true,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.scp(context)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Color(0xFFEF4444)),
                SizedBox(height: 16.scp(context)),
                Text(
                  'Only admin accounts can create users.',
                  style: FontUtilities.style(
                    fontSize: 16.scp(context),
                    fontColor: const Color(0xFF1F2937),
                    fontWeight: FWT.medium,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.scp(context)),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B8E97),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return HeaderWidget(
      headerChild: CustomAppBar(
        title: widget.userToEdit != null ? 'Edit User Details' : 'Create New User',
        showBackButton: true,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16.scp(context)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(14.scp(context)),
                decoration: BoxDecoration(
                  color: const Color(0xFF4B8E97).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12.scp(context)),
                  border: Border.all(
                    color: const Color(0xFF4B8E97).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  'Assign a reporting manager for every new user. '
                  'Admins and managers can both be selected — use your admin '
                  'account when creating the first manager.',
                  style: FontUtilities.style(
                    fontSize: 13.scp(context),
                    fontColor: const Color(0xFF4B8E97),
                    fontWeight: FWT.medium,
                  ),
                ),
              ),
              SizedBox(height: 16.scp(context)),
              _buildField(
                context,
                label: 'Email',
                controller: _emailController,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter email address';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              if (widget.userToEdit == null) ...[
                SizedBox(height: 12.scp(context)),
                _buildField(
                  context,
                  label: 'Password',
                  controller: _passwordController,
                  icon: Icons.lock_outline,
                  obscure: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter password';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 12.scp(context)),
              _buildField(
                context,
                label: 'Full Name',
                controller: _nameController,
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter full name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12.scp(context)),
              _buildField(
                context,
                label: 'Employee Code',
                controller: _employeeCodeController,
                icon: Icons.badge_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter employee code';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12.scp(context)),
              _buildField(
                context,
                label: 'Mobile Number',
                controller: _mobileController,
                icon: Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: _validateMobile,
              ),
              SizedBox(height: 12.scp(context)),
              _buildField(
                context,
                label: 'Employee Sitting Location (optional)',
                controller: _sitingLocationController,
                icon: Icons.location_city_outlined,
              ),
              SizedBox(height: 16.scp(context)),
              _buildRoleField(context),
              SizedBox(height: 16.scp(context)),
              _buildReportingManagerField(context),
              SizedBox(height: 24.scp(context)),
              SizedBox(
                height: 50.scp(context),
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleCreateUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B8E97),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.scp(context)),
                    ),
                    elevation: 0,
                  ),
                  icon: _isSubmitting
                      ? SizedBox(
                          width: 20.scp(context),
                          height: 20.scp(context),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(Icons.person_add, size: 20.scp(context)),
                  label: Text(
                    widget.userToEdit != null ? 'Save Changes' : 'Create User',
                    style: FontUtilities.style(
                      fontSize: 16.scp(context),
                      fontColor: Colors.white,
                      fontWeight: FWT.semiBold,
                    ),
                  ),
                ),
              ),
              if (_submitError != null) ...[
                SizedBox(height: 12.scp(context)),
                Container(
                  padding: EdgeInsets.all(12.scp(context)),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12.scp(context)),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _submitError!,
                    style: FontUtilities.style(
                      fontSize: 13.scp(context),
                      fontColor: const Color(0xFFEF4444),
                      fontWeight: FWT.medium,
                    ),
                  ),
                ),
              ],
              SizedBox(height: 24.scp(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FontUtilities.style(
            fontSize: 13.scp(context),
            fontColor: const Color(0xFF6B7280),
            fontWeight: FWT.semiBold,
          ),
        ),
        SizedBox(height: 6.scp(context)),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          validator: validator,
          style: FontUtilities.style(
            fontSize: 14.scp(context),
            fontColor: const Color(0xFF1F2937),
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF6B7280)),
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.scp(context)),
              borderSide: BorderSide(color: const Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.scp(context)),
              borderSide: BorderSide(color: const Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.scp(context)),
              borderSide: const BorderSide(color: Color(0xFF4B8E97), width: 1.5),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16.scp(context),
              vertical: 14.scp(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role',
          style: FontUtilities.style(
            fontSize: 13.scp(context),
            fontColor: const Color(0xFF6B7280),
            fontWeight: FWT.semiBold,
          ),
        ),
        SizedBox(height: 8.scp(context)),
        ..._roleOptions.map((option) {
          final isSelected = _selectedRole == option.$1;
          return Padding(
            padding: EdgeInsets.only(bottom: 8.scp(context)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedRole = option.$1),
                borderRadius: BorderRadius.circular(12.scp(context)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.scp(context),
                    vertical: 14.scp(context),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4B8E97)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12.scp(context)),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4B8E97)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        switch (option.$1) {
                          AppConstants.adminRole => Icons.admin_panel_settings,
                          AppConstants.managerRole => Icons.supervisor_account,
                          _ => Icons.person,
                        },
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF6B7280),
                      ),
                      SizedBox(width: 12.scp(context)),
                      Expanded(
                        child: Text(
                          option.$2,
                          style: FontUtilities.style(
                            fontSize: 14.scp(context),
                            fontColor: isSelected
                                ? Colors.white
                                : const Color(0xFF374151),
                            fontWeight:
                                isSelected ? FWT.semiBold : FWT.medium,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildReportingManagerField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reporting Manager',
          style: FontUtilities.style(
            fontSize: 13.scp(context),
            fontColor: const Color(0xFF6B7280),
            fontWeight: FWT.semiBold,
          ),
        ),
        SizedBox(height: 8.scp(context)),
        if (_loadingManagers)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_managersLoadError != null)
          _infoBox(
            context,
            _managersLoadError!,
            const Color(0xFFEF4444),
          )
        else if (_reportingManagers.isEmpty)
          _infoBox(
            context,
            'No admin or manager available to assign as reporting manager.',
            const Color(0xFF4B8E97),
          )
        else
          DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            value: _reportingManagers
                    .any((u) => u.apiId == _selectedReportingManagerId)
                ? _selectedReportingManagerId
                : null,
            style: FontUtilities.style(
              fontSize: 14.scp(context),
              fontColor: const Color(0xFF1F2937),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.supervisor_account_outlined, color: Color(0xFF6B7280)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.scp(context)),
                borderSide: BorderSide(color: const Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.scp(context)),
                borderSide: BorderSide(color: const Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.scp(context)),
                borderSide: const BorderSide(color: Color(0xFF4B8E97), width: 1.5),
              ),
            ),
            hint: Text(
              'Select reporting manager',
              style: FontUtilities.style(
                fontSize: 14.scp(context),
                fontColor: const Color(0xFF9CA3AF),
              ),
            ),
            items: _reportingManagers
                .map(
                  (user) => DropdownMenuItem<String>(
                    value: user.apiId,
                    child: Text(
                      _reportingManagerLabel(user),
                      overflow: TextOverflow.ellipsis,
                      style: FontUtilities.style(
                        fontSize: 14.scp(context),
                        fontColor: const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedReportingManagerId = value);
            },
            validator: (_) {
              if (!_requiresReportingManager) return null;
              if (_selectedReportingManagerId == null ||
                  _selectedReportingManagerId!.isEmpty) {
                return 'Please select a reporting manager';
              }
              return null;
            },
          ),
      ],
    );
  }

  Widget _infoBox(BuildContext context, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.scp(context)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.scp(context)),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: FontUtilities.style(
          fontSize: 13.scp(context),
          fontColor: color,
          fontWeight: FWT.medium,
        ),
      ),
    );
  }
}
