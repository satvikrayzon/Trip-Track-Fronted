import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_track/app/router/routes.dart';
import 'package:trip_track/core/app_dialog.dart';
import 'package:trip_track/core/di/service_locator.dart';
import 'package:trip_track/core/layout/adaptive_layout.dart';
import 'package:trip_track/core/routes/app_routes.dart';
import 'package:trip_track/core/utils/asset_utils.dart';
import 'package:trip_track/core/utils/device_utils.dart';
import 'package:trip_track/core/utils/font_utils.dart';
import 'package:trip_track/core/widgets/hover_widget.dart';
import 'package:trip_track/modules/auth/presentation/controllers/app_auth_controller.dart';

/// Wraps pages with a responsive website-style layout on desktop.
class ResponsiveWebLayout extends StatefulWidget {
  final Widget child;

  const ResponsiveWebLayout({super.key, required this.child});

  @override
  State<ResponsiveWebLayout> createState() => _ResponsiveWebLayoutState();
}

class _ResponsiveWebLayoutState extends State<ResponsiveWebLayout> {
  late final AppAuthController _auth;

  @override
  void initState() {
    super.initState();
    _auth = ServiceLocator.I.get<AppAuthController>();
  }

  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final isCompact = AdaptiveLayout.isCompact(context);

    return ValueListenableBuilder(
      valueListenable: _auth.userNotifier,
      builder: (context, user, _) {
        final isAuthenticated = _auth.isAuthenticated && user != null;

        if (isCompact || !isAuthenticated) {
          return widget.child;
        }

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          body: Row(
            children: [
              _SidebarWidget(
                auth: _auth,
                currentRoute: _getCurrentPath(context),
                isCollapsed: _isCollapsed,
                onToggleCollapse: () => setState(() => _isCollapsed = !_isCollapsed),
              ),
              Expanded(
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }

  String _getCurrentPath(BuildContext context) {
    try {
      return GoRouterState.of(context).matchedLocation;
    } catch (_) {
      return '';
    }
  }
}

class _SidebarWidget extends StatelessWidget {
  final AppAuthController auth;
  final String currentRoute;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  const _SidebarWidget({
    required this.auth,
    required this.currentRoute,
    required this.isCollapsed,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final menuItems = _getMenuItems(auth.userRole ?? '');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: isCollapsed ? 74 : 260,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D6E7C),
            Color(0xFF053941),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo header with Collapse button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: isCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  if (!isCollapsed)
                    Expanded(
                      child: Image.asset(
                        AssetUtilities.whiteLogo,
                        height: 38,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          'RAYZON',
                          style: FontUtilities.style(
                            fontSize: 16,
                            fontWeight: FWT.bold,
                            fontColor: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      isCollapsed
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: isCollapsed ? 'Expand Menu' : 'Collapse Menu',
                    onPressed: onToggleCollapse,
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: Colors.white24, height: 1),
            ),

            const SizedBox(height: 16),

            // Navigation Items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final isItemActive = _isPathActive(item.path, currentRoute);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: _SidebarMenuButton(
                      item: item,
                      isActive: isItemActive,
                      isCollapsed: isCollapsed,
                      onTap: () => context.push(item.path),
                    ),
                  );
                },
              ),
            ),

            // Bottom Profile and Logout Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: Colors.white24, height: 1),
            ),

            _buildProfileSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final user = auth.currentUserData;
    final name = user?.name ?? 'User';
    final email = user?.email ?? '';
    final role = user?.role?.toUpperCase() ?? '';

    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Column(
            children: [
              Tooltip(
                message: '$name\n$email\n($role)',
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white24,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: FontUtilities.style(
                      fontSize: 16,
                      fontWeight: FWT.bold,
                      fontColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
                tooltip: 'Sign Out',
                onPressed: () => _handleLogout(context),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar with hover animation
              HoverWidget(
                scale: 1.05,
                translateUp: 0,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white24,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: FontUtilities.style(
                      fontSize: 16,
                      fontWeight: FWT.bold,
                      fontColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: FontUtilities.style(
                        fontSize: 14,
                        fontWeight: FWT.semiBold,
                        fontColor: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: FontUtilities.style(
                        fontSize: 11,
                        fontWeight: FWT.regular,
                        fontColor: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Role & Logout actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  role,
                  style: FontUtilities.style(
                    fontSize: 9,
                    fontWeight: FWT.bold,
                    fontColor: Colors.tealAccent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
                tooltip: 'Sign Out',
                onPressed: () => _handleLogout(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      destructive: true,
    );
    if (confirmed) {
      await auth.signOut();
      if (context.mounted) {
        context.go(AppPaths.login);
      }
    }
  }

  bool _isPathActive(String itemPath, String activePath) {
    if (itemPath == activePath) return true;

    // Sub-path highlights
    if (itemPath == AppPaths.adminUserList && activePath == AppPaths.adminCreateUser) {
      return true;
    }
    if (itemPath == AppPaths.tripList && activePath == AppPaths.legacyTripDetail) {
      return true;
    }
    if (itemPath == AppPaths.tripList && activePath.startsWith('/trip/')) {
      return true;
    }
    if (itemPath == AppPaths.adminTravelRequests && activePath.startsWith('/trip/')) {
      return true;
    }

    return false;
  }

  List<_SidebarItem> _getMenuItems(String role) {
    if (role == 'admin') {
      return [
        const _SidebarItem(title: 'Dashboard', path: AppPaths.adminDashboard, icon: Icons.dashboard_rounded),
        const _SidebarItem(title: 'Manage Users', path: AppPaths.adminUserList, icon: Icons.people_rounded),
        const _SidebarItem(title: 'Travel Requests', path: AppPaths.adminTravelRequests, icon: Icons.assignment_rounded),
        const _SidebarItem(title: 'Fuel Rates', path: AppPaths.adminFuelRates, icon: Icons.local_gas_station_rounded),
        const _SidebarItem(title: 'Live Tracking Map', path: AppPaths.liveMap, icon: Icons.map_rounded),
        const _SidebarItem(title: 'My Profile', path: AppPaths.profile, icon: Icons.person_rounded),
        const _SidebarItem(title: 'Settings', path: AppPaths.settings, icon: Icons.settings_rounded),
      ];
    } else if (role == 'manager') {
      return [
        const _SidebarItem(title: 'Dashboard', path: AppPaths.managerHome, icon: Icons.dashboard_rounded),
        const _SidebarItem(title: 'Team Requests', path: AppPaths.adminTravelRequests, icon: Icons.assignment_rounded),
        const _SidebarItem(title: 'Live Map', path: AppPaths.liveMap, icon: Icons.map_rounded),
        const _SidebarItem(title: 'My Profile', path: AppPaths.profile, icon: Icons.person_rounded),
        const _SidebarItem(title: 'Settings', path: AppPaths.settings, icon: Icons.settings_rounded),
      ];
    } else {
      return [
        const _SidebarItem(title: 'Home', path: AppPaths.userHome, icon: Icons.home_rounded),
        const _SidebarItem(title: 'New Travel Request', path: AppPaths.createTrip, icon: Icons.add_circle_rounded),
        const _SidebarItem(title: 'My Requests', path: AppPaths.tripList, icon: Icons.list_alt_rounded),
        const _SidebarItem(title: 'My Profile', path: AppPaths.profile, icon: Icons.person_rounded),
        const _SidebarItem(title: 'Settings', path: AppPaths.settings, icon: Icons.settings_rounded),
      ];
    }
  }
}

class _SidebarItem {
  final String title;
  final String path;
  final IconData icon;

  const _SidebarItem({
    required this.title,
    required this.path,
    required this.icon,
  });
}

class _SidebarMenuButton extends StatefulWidget {
  final _SidebarItem item;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarMenuButton({
    required this.item,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  State<_SidebarMenuButton> createState() => _SidebarMenuButtonState();
}

class _SidebarMenuButtonState extends State<_SidebarMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final buttonContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? Colors.white.withOpacity(0.16)
                : _isHovered
                    ? Colors.white.withOpacity(0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: widget.isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (!widget.isCollapsed) ...[
                // Active Indicator line
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 4,
                  height: widget.isActive ? 18 : 0,
                  decoration: BoxDecoration(
                    color: Colors.tealAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: widget.isActive ? 12 : 0),
              ],
              Icon(
                widget.item.icon,
                color: widget.isActive
                    ? Colors.tealAccent
                    : _isHovered
                        ? Colors.white
                        : Colors.white70,
                size: 20,
              ),
              if (!widget.isCollapsed) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: FontUtilities.style(
                      fontSize: 13,
                      fontWeight: widget.isActive ? FWT.semiBold : FWT.medium,
                      fontColor: widget.isActive
                          ? Colors.tealAccent
                          : _isHovered
                              ? Colors.white
                              : Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.item.title,
        child: buttonContent,
      );
    }
    return buttonContent;
  }
}
