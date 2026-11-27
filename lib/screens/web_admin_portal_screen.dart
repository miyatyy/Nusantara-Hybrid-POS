import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/email_auth_service.dart';
import '../theme/app_theme.dart';

/// Web-Only SaaS Admin Portal (`https://nusantara-hybrid-pos.web.app/?admin=true`)
/// Manages all store/tenant accounts using Nusantara Hybrid POS,
/// allowing Super Admin (`mnurmiyaty2@gmail.com`) to create, monitor, upgrade,
/// suspend/activate, and inspect isolated databases per email account.
class WebAdminPortalScreen extends StatefulWidget {
  const WebAdminPortalScreen({super.key});

  @override
  State<WebAdminPortalScreen> createState() => _WebAdminPortalScreenState();
}

class _WebAdminPortalScreenState extends State<WebAdminPortalScreen> {
  static const String _superAdminEmail = EmailAuthService.defaultSenderEmail;
  static const String _defaultAdminPin = '123456';

  final TextEditingController _emailCtrl = TextEditingController(text: _superAdminEmail);
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isAuthenticated = false;
  String _statusFilter = 'ALL'; // ALL, ACTIVE, SUSPENDED
  String? _loginError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleAdminLogin() {
    HapticFeedback.lightImpact();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pin = _pinCtrl.text.trim();

    if (email != _superAdminEmail.toLowerCase()) {
      setState(() => _loginError = 'Hanya email Super Admin ($_superAdminEmail) yang diizinkan.');
      return;
    }
    if (pin != _defaultAdminPin) {
      setState(() => _loginError = 'PIN Admin salah (default: $_defaultAdminPin).');
      return;
    }

    setState(() {
      _isAuthenticated = true;
      _loginError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return _buildAdminLoginGate();
    }
    return _buildAdminDashboard();
  }

  Widget _buildAdminLoginGate() {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.royalBlue.withAlpha(24),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 38,
                        color: AppTheme.brightYellow,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'POS Account Management Web Portal',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Super Admin portal to manage store databases, license plans, and active status for every Nusantara POS tenant.',
                      style: TextStyle(fontSize: 12, color: AppTheme.slateMuted, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Super Admin Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.verified_user_rounded, size: 18, color: AppTheme.royalBlue),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Web Admin Access PIN (Default: 123456)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _handleAdminLogin(),
                    decoration: InputDecoration(
                      hintText: 'Enter 6-digit PIN',
                      prefixIcon: const Icon(Icons.lock_rounded, size: 18, color: AppTheme.goldenAmber),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  if (_loginError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(
                        _loginError!,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _handleAdminLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Sign In to Web Admin', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminDashboard() {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: AppTheme.royalBlue,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.brightYellow),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.brightYellow, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nusantara POS • Account Management Web (SaaS Admin)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Super Admin: $_superAdminEmail • Multi-Tenant Database Isolation',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFFDE68A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: 'https://nusantara-hybrid-pos.web.app/?admin=true'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF15803D),
                  behavior: SnackBarBehavior.floating,
                  content: Text('✓ Web Admin link copied to clipboard!'),
                ),
              );
            },
            icon: const Icon(Icons.link_rounded, color: AppTheme.brightYellow, size: 18),
            label: const Text('Copy Web Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          IconButton(
            tooltip: 'Sign Out Admin',
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () => setState(() {
              _isAuthenticated = false;
              _pinCtrl.clear();
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTenantDialog,
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.brightYellow),
        label: const Text('Add Store Account', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tenants').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.royalBlue));
          }

          final docs = snapshot.data?.docs ?? [];
          final query = _searchCtrl.text.trim().toLowerCase();

          final allTenants = docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['tenantId'] = data['tenantId'] ?? d.id;
            return data;
          }).toList();

          allTenants.sort((a, b) => (b['lastActiveAt'] ?? '').toString().compareTo((a['lastActiveAt'] ?? '').toString()));

          final activeCount = allTenants.where((t) => (t['status'] ?? 'ACTIVE') == 'ACTIVE').length;
          final suspendedCount = allTenants.where((t) => (t['status'] ?? 'ACTIVE') == 'SUSPENDED').length;
          final proCount = allTenants.where((t) => (t['plan'] ?? 'PRO') != 'TRIAL').length;

          final filtered = allTenants.where((t) {
            final status = (t['status'] ?? 'ACTIVE').toString();
            if (_statusFilter != 'ALL' && status != _statusFilter) return false;
            if (query.isEmpty) return true;
            final email = (t['ownerEmail'] ?? '').toString().toLowerCase();
            final name = (t['ownerName'] ?? '').toString().toLowerCase();
            final store = (t['storeName'] ?? '').toString().toLowerCase();
            final tid = (t['tenantId'] ?? '').toString().toLowerCase();
            return email.contains(query) || name.contains(query) || store.contains(query) || tid.contains(query);
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. KPI Summary Strip
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildKpiCard('Total Store Accounts', '${allTenants.length}', Icons.storefront_rounded, AppTheme.royalBlue),
                        _buildKpiCard('Active Accounts', '$activeCount', Icons.check_circle_rounded, const Color(0xFF15803D)),
                        _buildKpiCard('Suspended', '$suspendedCount', Icons.pause_circle_filled_rounded, AppTheme.roseRed),
                        _buildKpiCard('Paid Plans (PRO)', '$proCount', Icons.workspace_premium_rounded, const Color(0xFFD97706)),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 2. Search & Filter Bar
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 340,
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search email, owner name, or store name...',
                                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.royalBlue),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          _buildFilterChip('All', 'ALL'),
                          _buildFilterChip('Active', 'ACTIVE'),
                          _buildFilterChip('Suspended', 'SUSPENDED'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Tenant List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.manage_accounts_rounded, size: 54, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'No store accounts registered yet.',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.darkNavy),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Accounts appear automatically when users sign in via Email OTP in the app, or click "+ Add Store Account".',
                                    style: TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) => _buildTenantCard(filtered[index]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 245,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String key) {
    final selected = _statusFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: selected ? Colors.white : AppTheme.darkNavy)),
      selected: selected,
      selectedColor: AppTheme.royalBlue,
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (_) => setState(() => _statusFilter = key),
    );
  }

  Widget _buildTenantCard(Map<String, dynamic> t) {
    final tid = t['tenantId']?.toString() ?? '';
    final email = t['ownerEmail']?.toString() ?? '-';
    final ownerName = t['ownerName']?.toString() ?? 'Pemilik';
    final storeName = t['storeName']?.toString() ?? 'Toko $ownerName';
    final status = (t['status'] ?? 'ACTIVE').toString();
    final plan = (t['plan'] ?? 'PRO').toString();
    final isActive = status == 'ACTIVE';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isActive ? AppTheme.cardBorder : AppTheme.roseRed.withAlpha(120)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isActive ? AppTheme.royalBlue : Colors.grey.shade400,
                child: Text(
                  ownerName.isNotEmpty ? ownerName[0].toUpperCase() : 'T',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(storeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.darkNavy)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'AKTIF' : 'NONAKTIF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isActive ? const Color(0xFF15803D) : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          plan,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFB45309)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('$ownerName • $email', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.royalBlue)),
                  Text('Database ID: /tenants/$tid', style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppTheme.slateMuted)),
                ],
              ),
            ],
          ),

          // Actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _inspectTenantDatabase(tid, storeName, email),
                icon: const Icon(Icons.storage_rounded, size: 15),
                label: const Text('Live DB Explorer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
              DropdownButton<String>(
                value: ['TRIAL', 'PRO', 'ENTERPRISE'].contains(plan) ? plan : 'PRO',
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'TRIAL', child: Text('TRIAL', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'PRO', child: Text('PRO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'ENTERPRISE', child: Text('ENTERPRISE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
                ],
                onChanged: (newPlan) {
                  if (newPlan != null) {
                    FirebaseFirestore.instance.collection('tenants').doc(tid).update({'plan': newPlan});
                  }
                },
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final nextStatus = isActive ? 'SUSPENDED' : 'ACTIVE';
                  FirebaseFirestore.instance.collection('tenants').doc(tid).update({'status': nextStatus});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? const Color(0xFFD97706) : const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16),
                label: Text(isActive ? 'Suspend' : 'Activate', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Delete Account',
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.roseRed),
                onPressed: () => _confirmDeleteTenant(tid, storeName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _inspectTenantDatabase(String tid, String storeName, String email) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _TenantLiveDbDialog(
        tenantId: tid,
        storeName: storeName,
        ownerEmail: email,
      ),
    );
  }

  Future<void> _showAddTenantDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final storeCtrl = TextEditingController();
    String selectedPlan = 'PRO';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Register New Store Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Store Owner Email',
                    hintText: 'owner@gmail.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Owner Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: storeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Store / Business Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedPlan,
                  decoration: InputDecoration(
                    labelText: 'License Plan',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'TRIAL', child: Text('TRIAL (Free)')),
                    DropdownMenuItem(value: 'PRO', child: Text('PRO (Full POS + AI + WA)')),
                    DropdownMenuItem(value: 'ENTERPRISE', child: Text('ENTERPRISE (Multi-Branch)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedPlan = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final email = emailCtrl.text.trim().toLowerCase();
                if (!EmailAuthService.isValidEmail(email)) return;
                final tid = email.replaceAll(RegExp(r'[^a-z0-9]'), '_');
                final nowIso = DateTime.now().toIso8601String();
                await FirebaseFirestore.instance.collection('tenants').doc(tid).set({
                  'tenantId': tid,
                  'ownerEmail': email,
                  'ownerName': nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : email.split('@').first,
                  'storeName': storeCtrl.text.trim().isNotEmpty ? storeCtrl.text.trim() : 'Store $email',
                  'status': 'ACTIVE',
                  'plan': selectedPlan,
                  'createdAt': nowIso,
                  'lastActiveAt': nowIso,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue, foregroundColor: Colors.white),
              child: const Text('Save Account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTenant(String tid, String storeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Store Account?'),
        content: Text('Account "$storeName" (/tenants/$tid) will be removed from the management list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.roseRed, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('tenants').doc(tid).delete();
    }
  }
}

class _TenantLiveDbDialog extends StatefulWidget {
  final String tenantId;
  final String storeName;
  final String ownerEmail;

  const _TenantLiveDbDialog({
    required this.tenantId,
    required this.storeName,
    required this.ownerEmail,
  });

  @override
  State<_TenantLiveDbDialog> createState() => _TenantLiveDbDialogState();
}

class _TenantLiveDbDialogState extends State<_TenantLiveDbDialog> {
  static const List<Map<String, String>> _collections = [
    {'key': 'transactions', 'label': 'Orders & Sales'},
    {'key': 'menu_items', 'label': 'Menu & Bundles'},
    {'key': 'customers', 'label': 'Customers'},
    {'key': 'raw_materials', 'label': 'Raw Materials'},
    {'key': 'expenses', 'label': 'Expenses'},
    {'key': 'z_reports', 'label': 'Z-Reports'},
    {'key': 'wa_logs', 'label': 'WhatsApp Logs'},
  ];

  String _selectedCollection = 'transactions';

  DocumentReference<Map<String, dynamic>> get _tenantRef =>
      FirebaseFirestore.instance.collection('tenants').doc(widget.tenantId);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Database Explorer: ${widget.storeName}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.ownerEmail} • /tenants/${widget.tenantId}/$_selectedCollection',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors_rounded, size: 14, color: Color(0xFF15803D)),
                        SizedBox(width: 4),
                        Text(
                          'LIVE SYNC',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Real-time collection selector chips with live counts
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _collections.map((col) {
                    final key = col['key']!;
                    final label = col['label']!;
                    final isSelected = _selectedCollection == key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _tenantRef.collection(key).snapshots(),
                        builder: (context, snap) {
                          final count = snap.data?.docs.length ?? 0;
                          return ChoiceChip(
                            label: Text('$label ($count)'),
                            selected: isSelected,
                            selectedColor: AppTheme.royalBlue,
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppTheme.darkNavy,
                            ),
                            onSelected: (_) => setState(() => _selectedCollection = key),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 20),

              // Live records stream for the selected collection
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _tenantRef.collection(_selectedCollection).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.royalBlue),
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No live records in "$_selectedCollection" yet.',
                          style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                        ),
                      );
                    }

                    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
                    sorted.sort((a, b) {
                      final ta = (a.data()['timestamp'] ?? a.data()['createdAt'] ?? a.data()['lastOrderAt'] ?? '').toString();
                      final tb = (b.data()['timestamp'] ?? b.data()['createdAt'] ?? b.data()['lastOrderAt'] ?? '').toString();
                      return tb.compareTo(ta);
                    });

                    return ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final doc = sorted[idx];
                        return _buildRecordCard(doc.id, doc.data());
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(String docId, Map<String, dynamic> data) {
    String title = docId;
    String subtitle = '';
    String badge = '';
    Color badgeColor = AppTheme.royalBlue;

    switch (_selectedCollection) {
      case 'transactions':
        final q = data['queueNumber'] ?? '-';
        final cust = data['customerName'] ?? 'Customer';
        final phone = (data['customerPhone'] ?? '').toString();
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final method = data['paymentMethod'] ?? 'Cash';
        final status = (data['kitchenStatus'] ?? 'preparing').toString().toUpperCase();
        title = '$q • $cust${phone.isNotEmpty ? " ($phone)" : ""}';
        subtitle = 'Rp $total • $method • ${data['timestamp'] ?? ''}';
        badge = status;
        badgeColor = status == 'READY' ? const Color(0xFF15803D) : const Color(0xFFD97706);
        break;
      case 'menu_items':
        title = (data['name'] ?? docId).toString();
        subtitle = 'Category: ${data['category'] ?? '-'} • Price: Rp ${(data['price'] as num?)?.toInt() ?? 0}';
        badge = (data['isAvailable'] == false) ? 'SOLD OUT' : 'READY';
        badgeColor = (data['isAvailable'] == false) ? AppTheme.roseRed : const Color(0xFF15803D);
        break;
      case 'customers':
        title = '${data['name'] ?? 'Customer'} (${data['phone'] ?? docId})';
        subtitle = 'Orders: ${data['totalOrders'] ?? 0} • Total Spend: Rp ${(data['totalSpend'] as num?)?.toInt() ?? 0}';
        badge = 'CRM';
        break;
      case 'raw_materials':
        final stock = (data['currentStock'] as num?)?.toDouble() ?? 0;
        final min = (data['minThreshold'] ?? data['minSafetyStock'] ?? 0) as num;
        title = (data['name'] ?? docId).toString();
        subtitle = 'Stock: $stock ${data['unit'] ?? ''} • Min: $min';
        badge = stock <= min ? 'LOW' : 'OK';
        badgeColor = stock <= min ? AppTheme.roseRed : const Color(0xFF15803D);
        break;
      case 'expenses':
        title = (data['title'] ?? data['category'] ?? docId).toString();
        subtitle = 'Rp ${(data['amount'] as num?)?.toInt() ?? 0} • ${data['timestamp'] ?? ''}';
        badge = (data['category'] ?? 'EXPENSE').toString().toUpperCase();
        break;
      case 'z_reports':
        title = 'Shift ${data['shiftLabel'] ?? docId} (${data['cashierName'] ?? '-'})';
        subtitle = 'Gross: Rp ${(data['grossSales'] as num?)?.toInt() ?? 0} • Orders: ${data['totalOrders'] ?? 0}';
        badge = 'Z-REPORT';
        break;
      case 'wa_logs':
        title = '${data['queueNumber'] ?? '-'} -> ${data['phone'] ?? '-'}';
        subtitle = 'Stage: ${data['status'] ?? '-'} • ${data['timestamp'] ?? ''}';
        final sent = data['sent'] == true;
        badge = sent ? 'SENT' : 'QUEUED';
        badgeColor = sent ? const Color(0xFF15803D) : AppTheme.roseRed;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.darkNavy),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
                ),
              ],
            ),
          ),
          if (badge.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: badgeColor),
              ),
            ),
        ],
      ),
    );
  }
}
