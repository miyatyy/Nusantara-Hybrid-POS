import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/localization_service.dart';
import '../services/email_auth_service.dart';
import '../theme/app_theme.dart';
import '../main.dart';

/// Unified Left Navigation Sidebar (Drawer) for Nusantara Hybrid POS
/// Allows instant switching between all 5 Operational Roles and Store Management screens
/// inside a single APK without requiring an external browser.
class AppNavigationDrawer extends StatelessWidget {
  final AppRole currentRole;
  final ValueChanged<AppRole> onSelectRole;
  final int currentTab;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenSettings;
  final String storeName;
  final String cashierName;
  final String shiftLabel;
  final bool isOnline;
  final int activeTransactionsCount;
  final int lowStockCount;

  const AppNavigationDrawer({
    super.key,
    required this.currentRole,
    required this.onSelectRole,
    required this.currentTab,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.storeName,
    this.cashierName = 'Nurmiyaty',
    this.shiftLabel = 'Morning Shift',
    this.isOnline = true,
    this.activeTransactionsCount = 0,
    this.lowStockCount = 0,
  });

  String _getRoleLabel(AppRole role) {
    switch (role) {
      case AppRole.cashier:
        return 'POS Cashier (Master)';
      case AppRole.queueDisplay:
        return 'Queue Display (TV)';
      case AppRole.kitchenDisplay:
        return 'Kitchen Kanban (KDS)';
      case AppRole.customer:
        return 'Customer (Self-Order)';
      case AppRole.printerStation:
        return 'Auto-Print & Hub';
    }
  }

  IconData _getRoleIcon(AppRole role) {
    switch (role) {
      case AppRole.cashier:
        return Icons.point_of_sale_rounded;
      case AppRole.queueDisplay:
        return Icons.desktop_windows_rounded;
      case AppRole.kitchenDisplay:
        return Icons.soup_kitchen_rounded;
      case AppRole.customer:
        return Icons.phone_iphone_rounded;
      case AppRole.printerStation:
        return Icons.print_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // 1. Sidebar Header with Royal Blue Gradient
          _buildHeader(context),

          // 2. Navigation Content List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // SECTION 1: 5 OPERATIONAL ROLES
                _buildSectionTitle('5 CORE ROLES (ECOSYSTEM)'),

                _buildRoleTile(
                  context,
                  role: AppRole.cashier,
                  title: '1. Cashier (POS Master)',
                  subtitle: 'Full POS terminal, AI Order & LAN server',
                  badge: activeTransactionsCount > 0 ? '$activeTransactionsCount' : null,
                  badgeColor: AppTheme.royalBlue,
                ),

                _buildRoleTile(
                  context,
                  role: AppRole.queueDisplay,
                  title: '2. Queue Display (TV)',
                  subtitle: 'Live Preparing & Ready for Pickup board',
                  badgeColor: const Color(0xFF10B981),
                ),

                _buildRoleTile(
                  context,
                  role: AppRole.kitchenDisplay,
                  title: '3. Kitchen Kanban (Auto-Print)',
                  subtitle: 'Auto-print KOT tickets & cooking stages',
                  badgeColor: const Color(0xFFD97706),
                ),

                _buildRoleTile(
                  context,
                  role: AppRole.customer,
                  title: '4. Customer (Order Tracker)',
                  subtitle: 'Live GoFood-style order tracking & loyalty',
                  badgeColor: const Color(0xFF2563EB),
                ),

                _buildRoleTile(
                  context,
                  role: AppRole.printerStation,
                  title: '5. Auto-Print & Hardware Hub',
                  subtitle: 'Bluetooth, Wi-Fi 9100 status & auto-scan',
                  badgeColor: const Color(0xFF64748B),
                ),

                const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),

                // SECTION 2: STORE OPERATIONS
                _buildSectionTitle('STORE OPERATIONS'),

                _buildOperationTile(
                  context,
                  title: tr('nav_menu'),
                  subtitle: 'Food, beverages & combo bundles catalog',
                  icon: Icons.restaurant_menu_rounded,
                  tabIndex: 2,
                ),

                _buildOperationTile(
                  context,
                  title: tr('nav_inventory'),
                  subtitle: 'Raw materials stock (BOM) & restock',
                  icon: Icons.inventory_2_rounded,
                  tabIndex: 3,
                  badge: lowStockCount > 0 ? '$lowStockCount Low' : null,
                  badgeColor: AppTheme.roseRed,
                ),

                _buildOperationTile(
                  context,
                  title: tr('nav_analytics'),
                  subtitle: 'Net profit, Z-Report & AI WhatsApp Promo',
                  icon: Icons.insights_rounded,
                  tabIndex: 4,
                ),

                _buildSettingsTile(context),

                if (EmailAuthService().isLoggedIn) ...[
                  const Divider(height: 16, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.logout_rounded, color: AppTheme.roseRed, size: 20),
                    title: const Text(
                      'Sign Out Email Account',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.roseRed),
                    ),
                    subtitle: Text(
                      EmailAuthService().loggedInEmail,
                      style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await EmailAuthService().logout();
                    },
                  ),
                ],
              ],
            ),
          ),

          // 3. Footer Branding
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 16, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF), Color(0xFF172554)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.brightYellow.withAlpha(180)),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppTheme.brightYellow,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName.isNotEmpty ? storeName : 'Nusantara POS Café',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$cashierName • $shiftLabel',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withAlpha(210),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live Sync Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline
                      ? 'Online • Firebase Cloud Sync'
                      : 'Offline • Local LAN Server :8765',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Current Active Role Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.goldenAmber,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getRoleIcon(currentRole), size: 13, color: AppTheme.darkNavy),
                const SizedBox(width: 5),
                Text(
                  'Aktif: ${_getRoleLabel(currentRole)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkNavy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: Colors.grey.shade600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildRoleTile(
    BuildContext context, {
    required AppRole role,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
  }) {
    final isSelected = currentRole == role;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.lightBlueTint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.royalBlue : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.royalBlue : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getRoleIcon(role),
            color: isSelected ? AppTheme.brightYellow : AppTheme.royalBlue,
            size: 18,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
            color: isSelected ? AppTheme.royalBlue : AppTheme.darkNavy,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppTheme.royalBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            : (isSelected
                ? const Icon(Icons.check_circle_rounded, color: AppTheme.royalBlue, size: 18)
                : const Icon(Icons.chevron_right_rounded, color: AppTheme.slateLight, size: 18)),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context); // close drawer
          onSelectRole(role);
        },
      ),
    );
  }

  Widget _buildOperationTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required int tabIndex,
    String? badge,
    Color? badgeColor,
  }) {
    final isSelected = currentRole == AppRole.cashier && currentTab == tabIndex;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.lightBlueTint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.royalBlue : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.royalBlue : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isSelected ? AppTheme.brightYellow : AppTheme.royalBlue,
            size: 18,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
            color: isSelected ? AppTheme.royalBlue : AppTheme.darkNavy,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppTheme.roseRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            : const Icon(Icons.chevron_right_rounded, color: AppTheme.slateLight, size: 18),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context); // close drawer
          onSelectRole(AppRole.cashier);
          onSelectTab(tabIndex);
        },
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.settings_rounded,
            color: AppTheme.royalBlue,
            size: 18,
          ),
        ),
        title: Text(
          tr('settings_title'),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.darkNavy,
          ),
        ),
        subtitle: const Text(
          'Store profile, tax, printers, WA gateway & Midtrans',
          style: TextStyle(fontSize: 10, color: AppTheme.slateMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.slateLight, size: 18),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context); // close drawer
          onOpenSettings();
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Nusantara Hybrid POS v1.0.0',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
              ),
              Text(
                '#BuildHybridAI • Offline & Online Ecosystem',
                style: TextStyle(fontSize: 9.5, color: AppTheme.slateMuted),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppTheme.lightBlueTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.royalBlue),
          ),
        ],
      ),
    );
  }
}
