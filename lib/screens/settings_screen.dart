import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/transaction_model.dart';
import '../models/raw_material.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/firestore_service.dart';
import '../services/offline_outbox_service.dart';
import '../sdk/nusantara_printer_sdk.dart';
import '../services/shift_service.dart';
import '../models/cashier_shift.dart';
import '../theme/app_theme.dart';
import '../state/pos_state.dart';
import '../services/menu_availability_notifier.dart';
import '../services/menu_catalog_service.dart';
import '../services/whatsapp_gateway_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/customer_directory_service.dart';
import '../services/email_auth_service.dart';
import '../services/local_kitchen_bridge.dart';

class SettingsScreen extends StatefulWidget {
  final List<MenuItem> menuItems;
  final List<RawMaterial> rawMaterials;

  const SettingsScreen({
    super.key,
    required this.menuItems,
    required this.rawMaterials,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final FirestoreService _firestore = FirestoreService();
  final LocalizationService _loc = LocalizationService();
  final OfflineOutboxService _outbox = OfflineOutboxService();
  final NusantaraPrinterSDK _printerSdk = NusantaraPrinterSDK();
  final ShiftService _shiftService = ShiftService();
  final PosState _posState = PosState();
  final WhatsAppGatewayService _waGateway = WhatsAppGatewayService();

  late TextEditingController _nameController;
  late TextEditingController _taglineController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _footerController;
  late TextEditingController _taxController;
  late TextEditingController _serviceController;
  late TextEditingController _keyController;
  late TextEditingController _kitchenPrinterIpController;
  late TextEditingController _waFonnteTokenController;
  late TextEditingController _waFonntePairPhoneController;
  late TextEditingController _waWabaTokenController;
  late TextEditingController _waWabaPhoneIdController;

  List<BluetoothPrinterDevice> _pairedDevices = [];
  bool _isLoadingDevices = false;
  bool _isTestingPrinter = false;
  bool _isScanningWifiPrinters = false;
  bool _isTestingKitchenPrinter = false;
  List<DiscoveredNetworkPrinter> _discoveredWifiPrinters = [];
  bool _isPairingFonnte = false;
  bool _fonnteConnected = false;
  String _fonnteDeviceLabel = '';
  Uint8List? _fonnteQrBytes;
  String? _fonntePairingCode;
  String? _fonntePairMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _settings.storeName);
    _taglineController = TextEditingController(text: _settings.storeTagline);
    _addressController = TextEditingController(text: _settings.storeAddress);
    _phoneController = TextEditingController(text: _settings.storePhone);
    _footerController = TextEditingController(text: _settings.receiptFooter);
    _taxController = TextEditingController(text: _settings.taxRate.toStringAsFixed(0));
    _serviceController = TextEditingController(text: _settings.serviceChargeRate.toStringAsFixed(0));
    _keyController = TextEditingController(text: _settings.localMidtransKey);
    _kitchenPrinterIpController = TextEditingController(text: _printerSdk.kitchenWifiPrinterIp);
    _waFonnteTokenController = TextEditingController(text: _waGateway.fonnteToken);
    _waFonntePairPhoneController = TextEditingController(text: _settings.storePhone);
    _waWabaTokenController = TextEditingController(text: _waGateway.wabaToken);
    _waWabaPhoneIdController = TextEditingController(text: _waGateway.wabaPhoneId);

    _refreshPairedDevices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _footerController.dispose();
    _taxController.dispose();
    _serviceController.dispose();
    _keyController.dispose();
    _kitchenPrinterIpController.dispose();
    _waFonnteTokenController.dispose();
    _waFonntePairPhoneController.dispose();
    _waWabaTokenController.dispose();
    _waWabaPhoneIdController.dispose();
    super.dispose();
  }

  Future<void> _refreshPairedDevices() async {
    setState(() => _isLoadingDevices = true);
    await _printerSdk.checkAndRequestPermissions();
    final devices = await _printerSdk.getPairedPrinters();
    if (mounted) {
      setState(() {
        _pairedDevices = devices;
        _isLoadingDevices = false;
      });
    }
  }

  Future<void> _handleTestPrint() async {
    if (!_printerSdk.hasPrinterSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.roseRed,
          content: Text(tr('printer_no_devices')),
        ),
      );
      return;
    }

    setState(() => _isTestingPrinter = true);
    try {
      final ok = await _printerSdk.printTestReceipt(storeName: _settings.storeName);
      if (mounted && ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            content: Text(tr('printer_test_success')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Test Print Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingPrinter = false);
    }
  }

  void _showJsonLogDialog() {
    final logText = _outbox.getFormattedJsonLog();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.data_object_rounded, color: AppTheme.royalBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              tr('offline_view_log'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 380),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: Text(
              logText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: Color(0xFF38BDF8),
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppTheme.royalBlue,
                  content: Text('Log JSON disalin ke clipboard!'),
                ),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('Copy Log'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _saveProfile() async {
    HapticFeedback.lightImpact();
    final tax = double.tryParse(_taxController.text) ?? 10.0;
    final sc = double.tryParse(_serviceController.text) ?? 5.0;

    await _settings.updateStoreProfile(
      storeName: _nameController.text.trim().isEmpty ? 'Nusantara POS Café' : _nameController.text.trim(),
      storeTagline: _taglineController.text.trim(),
      storeAddress: _addressController.text.trim(),
      storePhone: _phoneController.text.trim(),
      receiptFooter: _footerController.text.trim(),
      taxRate: tax,
      serviceChargeRate: sc,
    );

    await _settings.setLocalMidtransKey(_keyController.text.trim());

    await _printerSdk.saveKitchenPrinterConfig(
      ip: _kitchenPrinterIpController.text.trim(),
      autoPrint: _printerSdk.kitchenAutoPrintEnabled,
    );
    await _waGateway.saveSettings(
      provider: _waGateway.provider,
      fonnteToken: _waFonnteTokenController.text.trim(),
      wabaToken: _waWabaTokenController.text.trim(),
      wabaPhoneId: _waWabaPhoneIdController.text.trim(),
      autoSendReceipt: _waGateway.autoSendReceipt,
      autoSendReady: _waGateway.autoSendReady,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Store Profile, Tax & Payment Keys Saved Successfully!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Map<String, RawMaterial> get _rawStockMap {
    return {for (var r in widget.rawMaterials) r.id: r};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.iceBlueScaffold,
      appBar: AppBar(
        title: Text(
          tr('settings_title'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Save Settings',
            icon: const Icon(Icons.check_rounded, color: AppTheme.brightYellow),
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_settings, _outbox, _printerSdk, _shiftService, _posState, _waGateway]),
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Store Profile & Receipt Section
                  _buildStoreProfileSection(),
                  const SizedBox(height: 16),

                  // 2. Custom Bluetooth ESC/POS Printer SDK Section
                  _buildBluetoothPrinterSection(),
                  const SizedBox(height: 16),

                  // 2b-2. Kitchen Wi-Fi Printer (ESC/POS Port 9100)
                  _buildKitchenWifiPrinterSection(),
                  const SizedBox(height: 16),

                  // 2b. Cashier Roster & Shift Schedules Section
                  _buildCashierShiftRosterSection(),
                  const SizedBox(height: 16),

                  // 3. Offline JSON Outbox & Cloud Sync Section
                  _buildOfflineOutboxSection(),
                  const SizedBox(height: 16),

                  // 4. Stock & AI Menu Automation Section
                  _buildStockAutomationSection(),
                  const SizedBox(height: 16),

                  // 5. Quick Menu Availability Overrides
                  _buildMenuOverridesSection(),
                  const SizedBox(height: 16),

                  // 6. Midtrans Sandbox & Payment Config Section
                  _buildMidtransConfigSection(),
                  const SizedBox(height: 16),

                  // 6b. WhatsApp Gateway Configuration Section
                  _buildWhatsAppGatewaySection(),
                  const SizedBox(height: 16),

                  // 7. Hybrid AI & Demo Controls
                  _buildAiAndDemoSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardWrapper({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlueTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.royalBlue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // Section 2b-2: Kitchen Wi-Fi Printer (Port 9100) Section
  Widget _buildKitchenWifiPrinterSection() {
    return _buildCardWrapper(
      title: 'Wi-Fi Kitchen Printer (ESC/POS Port 9100)',
      icon: Icons.print_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Floor 2 LAN / Wi-Fi Router Connection',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.darkNavy),
                  ),
                  Text(
                    _printerSdk.kitchenWifiPrinterIp.isNotEmpty
                        ? 'IP: ${_printerSdk.kitchenWifiPrinterIp}:9100'
                        : 'Not set (Auto-scan or enter IP)',
                    style: const TextStyle(fontSize: 11, color: AppTheme.royalBlue, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isScanningWifiPrinters
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.radar_rounded, size: 16),
              label: Text(
                _isScanningWifiPrinters ? 'Scanning...' : 'Scan Wi-Fi',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: _isScanningWifiPrinters
                  ? null
                  : () async {
                      setState(() => _isScanningWifiPrinters = true);
                      final printers = await _printerSdk.scanKitchenWifiPrinters();
                      if (mounted) {
                        setState(() {
                          _discoveredWifiPrinters = printers;
                          _isScanningWifiPrinters = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: printers.isNotEmpty ? const Color(0xFF15803D) : const Color(0xFFD97706),
                            content: Text(
                              printers.isNotEmpty
                                  ? 'Found ${printers.length} ESC/POS port 9100 printer(s)!'
                                  : 'No port 9100 printer detected on the current subnet.',
                            ),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Discovered Printers List
        if (_discoveredWifiPrinters.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.lightBlueTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.royalBlue.withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wi-Fi Printers Detected on Subnet:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                ),
                const SizedBox(height: 6),
                ..._discoveredWifiPrinters.map((p) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.print, color: AppTheme.royalBlue, size: 20),
                    title: Text(
                      '${p.ip}:9100',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                    ),
                    subtitle: Text('Response: ${p.pingMs}ms', style: const TextStyle(fontSize: 10, color: Color(0xFF15803D))),
                    trailing: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: () {
                        setState(() {
                          _kitchenPrinterIpController.text = p.ip;
                        });
                        _printerSdk.saveKitchenWifiPrinter(
                          ip: p.ip,
                          autoPrint: _printerSdk.kitchenAutoPrintEnabled,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF15803D),
                            content: Text('Printer ${p.ip} selected as kitchen printer!'),
                          ),
                        );
                      },
                      child: const Text('Use', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Manual IP input
        TextField(
          controller: _kitchenPrinterIpController,
          decoration: InputDecoration(
            labelText: 'Kitchen Printer IP Address',
            hintText: '192.168.1.200',
            prefixIcon: const Icon(Icons.lan_rounded, size: 18, color: AppTheme.royalBlue),
            suffixIcon: IconButton(
              icon: const Icon(Icons.save_rounded, size: 18, color: AppTheme.royalBlue),
              tooltip: 'Save IP',
              onPressed: () {
                _printerSdk.saveKitchenWifiPrinter(
                  ip: _kitchenPrinterIpController.text.trim(),
                  autoPrint: _printerSdk.kitchenAutoPrintEnabled,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF15803D),
                    content: Text('Kitchen Printer IP saved!'),
                  ),
                );
              },
            ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),

        // Auto-print toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-Print Kitchen Tickets (KOT)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          subtitle: const Text('Send print job immediately when a new order is placed (<1 sec)', style: TextStyle(fontSize: 10, color: AppTheme.slateLight)),
          value: _printerSdk.kitchenAutoPrintEnabled,
          activeTrackColor: AppTheme.goldenAmber,
          onChanged: (val) {
            _printerSdk.saveKitchenWifiPrinter(
              ip: _kitchenPrinterIpController.text.trim(),
              autoPrint: val,
            );
          },
        ),

        const SizedBox(height: 6),
        // Test Print KOT Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.royalBlue,
              side: const BorderSide(color: AppTheme.royalBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isTestingKitchenPrinter
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long_rounded, size: 16),
            label: const Text('Print Kitchen Test Ticket (KOT Test)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: _isTestingKitchenPrinter
                ? null
                : () async {
                    setState(() => _isTestingKitchenPrinter = true);
                    final sampleTx = PosTransaction(
                      id: 'TEST-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                      timestamp: DateTime.now(),
                      items: widget.menuItems.take(2).map((m) => OrderItem(menuItem: m, quantity: 2, notes: 'Spicy, No Onion')).toList(),
                      subtotal: 50000,
                      tax: 5000,
                      total: 55000,
                      paymentMethod: 'Cash',
                      cashReceived: 60000,
                      changeAmount: 5000,
                      orderMode: 'Dine In (Table #04)',
                      queueNumber: '#099',
                    );
                    final ok = await _printerSdk.printKitchenOrderTicket(sampleTx, forceManual: true);
                    if (mounted) {
                      setState(() => _isTestingKitchenPrinter = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: ok ? const Color(0xFF15803D) : AppTheme.roseRed,
                          content: Text(
                            ok ? 'Kitchen Ticket printed to ${_printerSdk.kitchenWifiPrinterIp}!' : 'Failed to print to kitchen printer. Ensure printer is online on port 9100.',
                          ),
                        ),
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  // Section: WhatsApp Gateway Config
  Widget _buildWhatsAppGatewaySection() {
    return _buildCardWrapper(
      title: 'WhatsApp Gateway (Fonnte / Meta WABA)',
      icon: Icons.chat_bubble_outline_rounded,
      children: [
        // Provider Dropdown
        const Text('Select WhatsApp Provider:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<WhatsAppProvider>(
              isExpanded: true,
              value: _waGateway.provider,
              items: const [
                DropdownMenuItem(
                  value: WhatsAppProvider.fonnte,
                  child: Text('Provider A: Fonnte (Sandbox / Demo Hackathon)', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: WhatsAppProvider.wabaOfficial,
                  child: Text('Provider B: Meta WABA Official (Cloud API)', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  _waGateway.saveSettings(
                    provider: val,
                    fonnteToken: _waFonnteTokenController.text.trim(),
                    wabaToken: _waWabaTokenController.text.trim(),
                    wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                    autoSendReceipt: _waGateway.autoSendReceipt,
                    autoSendReady: _waGateway.autoSendReady,
                  );
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_waGateway.provider == WhatsAppProvider.fonnte) ...[
          TextField(
            controller: _waFonnteTokenController,
            decoration: InputDecoration(
              labelText: 'Fonnte API Token (Device Token from fonnte.com)',
              hintText: 'Paste your Fonnte Token here',
              prefixIcon: const Icon(Icons.key_rounded, size: 18, color: Color(0xFF15803D)),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _waGateway.saveSettings(
                      provider: _waGateway.provider,
                      fonnteToken: _waFonnteTokenController.text.trim(),
                      wabaToken: _waWabaTokenController.text.trim(),
                      wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                      autoSendReceipt: _waGateway.autoSendReceipt,
                      autoSendReady: _waGateway.autoSendReady,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF15803D),
                        content: Text('✓ Fonnte Token saved!'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 15),
                  label: const Text('Save Token', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _waGateway.saveSettings(
                      provider: _waGateway.provider,
                      fonnteToken: _waFonnteTokenController.text.trim(),
                      wabaToken: _waWabaTokenController.text.trim(),
                      wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                      autoSendReceipt: _waGateway.autoSendReceipt,
                      autoSendReady: _waGateway.autoSendReady,
                    );
                    if (!mounted) return;
                    final phoneCtrl = TextEditingController(text: '08');
                    final target = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Test Fonnte WA Send', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        content: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Target WA Number (08xx / 628xx)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D), foregroundColor: Colors.white),
                            child: const Text('Send Test'),
                          ),
                        ],
                      ),
                    );
                    if (target == null || target.length < 9) return;
                    final ok = await _waGateway.sendMessage(
                      targetPhone: WhatsAppGatewayService.formatPhoneNumber(target),
                      messageText: '🔔 *NUSANTARA POS TEST ALARM*\nFonnte connection successful! Ready-for-Pickup notifications are ready to send automatically.',
                      type: 'TEST',
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: ok ? const Color(0xFF15803D) : AppTheme.roseRed,
                        content: Text(
                          ok
                              ? '✓ Fonnte WA Test SENT to $target!'
                              : '✗ Fonnte failed: ${_waGateway.lastError.isNotEmpty ? _waGateway.lastError : "Invalid token / WA device not connected on fonnte.com"}',
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF15803D),
                    side: const BorderSide(color: Color(0xFF15803D)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label: const Text('Test WA Send', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fonnte WhatsApp Channel Pairing (Scan QR / Pairing Code)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_rounded, size: 18, color: Color(0xFF15803D)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Fonnte WhatsApp Channel Pairing',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isPairingFonnte
                          ? null
                          : () async {
                              await _waGateway.saveSettings(
                                provider: _waGateway.provider,
                                fonnteToken: _waFonnteTokenController.text.trim(),
                                wabaToken: _waWabaTokenController.text.trim(),
                                wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                                autoSendReceipt: _waGateway.autoSendReceipt,
                                autoSendReady: _waGateway.autoSendReady,
                              );
                              setState(() => _isPairingFonnte = true);
                              final status = await _waGateway.getFonnteDeviceStatus();
                              if (!mounted) return;
                              setState(() {
                                _isPairingFonnte = false;
                                _fonnteConnected = status.isConnected;
                                _fonnteDeviceLabel = status.deviceNumber;
                                _fonntePairMessage = status.message;
                                if (status.isConnected) {
                                  _fonnteQrBytes = null;
                                  _fonntePairingCode = null;
                                }
                              });
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF15803D),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Check Status', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _waFonntePairPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Store WhatsApp Number (for Pairing Code)',
                    hintText: '6281234567890',
                    prefixIcon: const Icon(Icons.phone_android_rounded, size: 17, color: Color(0xFF15803D)),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isPairingFonnte
                            ? null
                            : () async {
                                await _waGateway.saveSettings(
                                  provider: _waGateway.provider,
                                  fonnteToken: _waFonnteTokenController.text.trim(),
                                  wabaToken: _waWabaTokenController.text.trim(),
                                  wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                                  autoSendReceipt: _waGateway.autoSendReceipt,
                                  autoSendReady: _waGateway.autoSendReady,
                                );
                                setState(() {
                                  _isPairingFonnte = true;
                                  _fonnteQrBytes = null;
                                  _fonntePairingCode = null;
                                  _fonntePairMessage = 'Generating Fonnte QR Code...';
                                });
                                final res = await _waGateway.requestFonntePairing(
                                  type: 'qr',
                                  whatsapp: _waFonntePairPhoneController.text.trim(),
                                );
                                if (!mounted) return;
                                setState(() {
                                  _isPairingFonnte = false;
                                  _fonnteQrBytes = res.qrImageBytes;
                                  _fonnteConnected = res.alreadyConnected;
                                  _fonntePairMessage = res.message;
                                });
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 15),
                        label: const Text('Scan QR Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPairingFonnte
                            ? null
                            : () async {
                                await _waGateway.saveSettings(
                                  provider: _waGateway.provider,
                                  fonnteToken: _waFonnteTokenController.text.trim(),
                                  wabaToken: _waWabaTokenController.text.trim(),
                                  wabaPhoneId: _waWabaPhoneIdController.text.trim(),
                                  autoSendReceipt: _waGateway.autoSendReceipt,
                                  autoSendReady: _waGateway.autoSendReady,
                                );
                                setState(() {
                                  _isPairingFonnte = true;
                                  _fonnteQrBytes = null;
                                  _fonntePairingCode = null;
                                  _fonntePairMessage = 'Requesting 8-digit Pairing Code...';
                                });
                                final res = await _waGateway.requestFonntePairing(
                                  type: 'code',
                                  whatsapp: _waFonntePairPhoneController.text.trim(),
                                );
                                if (!mounted) return;
                                setState(() {
                                  _isPairingFonnte = false;
                                  _fonntePairingCode = res.pairingCode;
                                  _fonnteConnected = res.alreadyConnected;
                                  _fonntePairMessage = res.message;
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.royalBlue,
                          side: const BorderSide(color: AppTheme.royalBlue),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.pin_rounded, size: 15),
                        label: const Text('Pairing Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                if (_isPairingFonnte) ...[
                  const SizedBox(height: 10),
                  const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
                ],
                if (_fonntePairMessage != null && _fonntePairMessage!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _fonnteConnected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        size: 14,
                        color: _fonnteConnected ? const Color(0xFF15803D) : AppTheme.royalBlue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _fonnteDeviceLabel.isNotEmpty && _fonnteConnected
                              ? '$_fonntePairMessage ($_fonnteDeviceLabel)'
                              : _fonntePairMessage!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _fonnteConnected ? const Color(0xFF15803D) : AppTheme.darkNavy,
                          ),
                        ),
                      ),
                      if (_fonnteConnected)
                        TextButton(
                          onPressed: () async {
                            final ok = await _waGateway.disconnectFonnteDevice();
                            if (!mounted) return;
                            setState(() {
                              if (ok) {
                                _fonnteConnected = false;
                                _fonnteDeviceLabel = '';
                                _fonntePairMessage = 'Disconnected. You can scan QR or request a Pairing Code now.';
                              }
                            });
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.roseRed,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Disconnect', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
                if (_fonnteQrBytes != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Image.memory(
                        _fonnteQrBytes!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
                if (_fonntePairingCode != null && _fonntePairingCode!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.royalBlue),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _fonntePairingCode!,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              letterSpacing: 3,
                              color: AppTheme.royalBlue,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _fonntePairingCode!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF15803D),
                                content: Text('✓ Pairing Code copied!'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          TextField(
            controller: _waWabaTokenController,
            decoration: InputDecoration(
              labelText: 'Meta WABA System User Access Token',
              hintText: 'EAA...',
              prefixIcon: const Icon(Icons.key_rounded, size: 18, color: AppTheme.royalBlue),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _waWabaPhoneIdController,
            decoration: InputDecoration(
              labelText: 'Meta Phone Number ID',
              hintText: '1092837465...',
              prefixIcon: const Icon(Icons.tag_rounded, size: 18, color: AppTheme.royalBlue),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],

        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send Receipt & Live Tracker Link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          subtitle: const Text('Automatically send receipt details & Customer Tracker URL to customer WhatsApp at checkout', style: TextStyle(fontSize: 10, color: AppTheme.slateLight)),
          value: _waGateway.autoSendReceipt,
          activeTrackColor: const Color(0xFF15803D),
          onChanged: (val) {
            _waGateway.saveSettings(
              provider: _waGateway.provider,
              fonnteToken: _waFonnteTokenController.text.trim(),
              wabaToken: _waWabaTokenController.text.trim(),
              wabaPhoneId: _waWabaPhoneIdController.text.trim(),
              autoSendReceipt: val,
              autoSendReady: _waGateway.autoSendReady,
            );
          },
        ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send Order Ready Notification', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          subtitle: const Text('Automatically send WhatsApp alert when Kitchen KDS marks an order Ready for Pickup', style: TextStyle(fontSize: 10, color: AppTheme.slateLight)),
          value: _waGateway.autoSendReady,
          activeTrackColor: const Color(0xFF15803D),
          onChanged: (val) {
            _waGateway.saveSettings(
              provider: _waGateway.provider,
              fonnteToken: _waFonnteTokenController.text.trim(),
              wabaToken: _waWabaTokenController.text.trim(),
              wabaPhoneId: _waWabaPhoneIdController.text.trim(),
              autoSendReceipt: _waGateway.autoSendReceipt,
              autoSendReady: val,
            );
          },
        ),

        const SizedBox(height: 8),
        // Outbox Status Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _waGateway.outbox.isEmpty ? const Color(0xFFF0FDF4) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _waGateway.outbox.isEmpty ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _waGateway.outbox.isEmpty ? Icons.mark_email_read_rounded : Icons.outbox_rounded,
                color: _waGateway.outbox.isEmpty ? const Color(0xFF15803D) : const Color(0xFFB45309),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _waGateway.outbox.isEmpty
                          ? 'WhatsApp Outbox Clear (All Sent)'
                          : '${_waGateway.outbox.length} Pending WhatsApp Messages (Offline)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _waGateway.outbox.isEmpty ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                    const Text(
                      'Messages are automatically sent when internet is back online.',
                      style: TextStyle(fontSize: 9.5, color: AppTheme.slateLight),
                    ),
                  ],
                ),
              ),
              if (_waGateway.outbox.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onPressed: () async {
                    await _waGateway.drainOutbox();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF15803D),
                          content: Text('Retrying WhatsApp outbox queue...'),
                        ),
                      );
                    }
                  },
                  child: const Text('Resend', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Local-First + Cloud Firebase Backup Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_sync_rounded, size: 18, color: AppTheme.royalBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Firebase Cloud Database Backup (${EmailAuthService().tenantId})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Menu (${MenuCatalogService().items.length}), Customers (${CustomerDirectoryService().customers.length}), & Orders (${LocalKitchenBridge().localOrders.length}) are stored locally and ready to back up to Firebase anytime.',
                style: const TextStyle(fontSize: 10.5, color: AppTheme.slateMuted, height: 1.35),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final res = await CloudBackupService().backupLocalToFirebase();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: res.success ? const Color(0xFF15803D) : AppTheme.roseRed,
                            content: Text(res.message),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                      label: const Text('Backup ke Firebase', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final res = await CloudBackupService().restoreFromFirebaseToLocal();
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: res.success ? const Color(0xFF15803D) : AppTheme.roseRed,
                            content: Text(res.message),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                        side: const BorderSide(color: AppTheme.royalBlue),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cloud_download_rounded, size: 16),
                      label: const Text('Restore Firebase', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Section 1: Store & Receipt Profile
  Widget _buildStoreProfileSection() {
    return _buildCardWrapper(
      title: tr('settings_store_profile'),
      icon: Icons.storefront_rounded,
      children: [
        _buildTextField(_nameController, tr('settings_store_name')),
        const SizedBox(height: 10),
        _buildTextField(_taglineController, tr('settings_store_tagline')),
        const SizedBox(height: 10),
        _buildTextField(_addressController, tr('settings_store_address')),
        const SizedBox(height: 10),
        _buildTextField(_phoneController, tr('settings_store_phone'), keyboardType: TextInputType.phone),
        const SizedBox(height: 10),
        _buildTextField(_footerController, tr('settings_receipt_footer')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _taxController,
                tr('settings_tax_rate'),
                keyboardType: TextInputType.number,
                suffix: '%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _serviceController,
                tr('settings_service_charge'),
                keyboardType: TextInputType.number,
                suffix: '%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            onPressed: _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Profile & Tax', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // Section 2: Custom Bluetooth Thermal Printer SDK
  Widget _buildBluetoothPrinterSection() {
    return _buildCardWrapper(
      title: tr('printer_sdk_title'),
      icon: Icons.bluetooth_connected_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _printerSdk.hasPrinterSelected
                        ? '${tr('printer_status_connected')}: ${_printerSdk.selectedPrinterName}'
                        : tr('printer_status_none'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _printerSdk.hasPrinterSelected ? const Color(0xFF15803D) : AppTheme.slateMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_printerSdk.hasPrinterSelected)
                    Text(
                      _printerSdk.selectedPrinterAddress,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.slateLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: _isLoadingDevices
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, color: AppTheme.royalBlue),
              tooltip: tr('printer_scan_refresh'),
              onPressed: _isLoadingDevices ? null : _refreshPairedDevices,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Device Selection
        if (_pairedDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppTheme.slateMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('printer_no_devices'),
                    style: const TextStyle(fontSize: 10.5, color: AppTheme.slateMuted),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Select Bluetooth Printer', style: TextStyle(fontSize: 12)),
                value: _printerSdk.hasPrinterSelected ? _printerSdk.selectedPrinterAddress : null,
                items: _pairedDevices.map((d) {
                  return DropdownMenuItem<String>(
                    value: d.address,
                    child: Text('${d.name} (${d.address})', style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    final selected = _pairedDevices.firstWhere((d) => d.address == val);
                    _printerSdk.saveSelectedPrinter(
                      name: selected.name,
                      address: selected.address,
                      paperWidthMm: _printerSdk.paperWidthMm,
                    );
                  }
                },
              ),
            ),
          ),

        const SizedBox(height: 12),
        // Paper Width Selector
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('printer_paper_width'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 58, label: Text('58 mm (32 cols)', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 80, label: Text('80 mm (48 cols)', style: TextStyle(fontSize: 11))),
                ],
                selected: {_printerSdk.paperWidthMm},
                onSelectionChanged: (set) {
                  _printerSdk.saveSelectedPrinter(
                    name: _printerSdk.selectedPrinterName,
                    address: _printerSdk.selectedPrinterAddress,
                    paperWidthMm: set.first,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Print Test Page Button
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _isTestingPrinter ? null : _handleTestPrint,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.royalBlue,
              side: const BorderSide(color: AppTheme.royalBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isTestingPrinter
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_outlined, size: 16),
            label: Text(
              _isTestingPrinter ? 'Sending Data...' : tr('printer_test_page'),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // Section 3: Offline JSON Outbox & Cloud Sync
  Widget _buildOfflineOutboxSection() {
    final pendingCount = _outbox.pendingCount;

    return _buildCardWrapper(
      title: tr('offline_outbox_title'),
      icon: Icons.outbox_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pendingCount > 0
                        ? '${tr('offline_queue_badge')}: $pendingCount transactions'
                        : tr('offline_all_synced'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: pendingCount > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    pendingCount > 0
                        ? 'Safely stored in local SharedPreferences'
                        : 'All offline transactions synced to Firestore',
                    style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pendingCount > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: pendingCount > 0 ? const Color(0xFFFDE68A) : const Color(0xFF86EFAC),
                ),
              ),
              child: Text(
                pendingCount > 0 ? '$pendingCount PENDING' : 'SYNCED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: pendingCount > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showJsonLogDialog,
                icon: const Icon(Icons.code_rounded, size: 14),
                label: Text(
                  tr('offline_view_log'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.royalBlue,
                  side: const BorderSide(color: AppTheme.royalBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _outbox.isSyncing || pendingCount == 0
                    ? null
                    : () => _outbox.syncPendingOutbox(),
                icon: _outbox.isSyncing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, size: 14),
                label: Text(
                  _outbox.isSyncing ? 'Sinkronisasi...' : tr('offline_sync_now'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Section 4: Stock & AI Menu Automation
  Widget _buildStockAutomationSection() {
    return _buildCardWrapper(
      title: tr('settings_stock_automation'),
      icon: Icons.inventory_2_rounded,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppTheme.royalBlue,
          value: _settings.autoDeductEnabled,
          onChanged: (val) => _settings.setAutoDeduct(val),
          title: Text(
            tr('settings_auto_deduct'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            tr('settings_auto_deduct_sub'),
            style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
          ),
        ),
        const Divider(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: AppTheme.royalBlue,
          value: _settings.aiStockGuardEnabled,
          onChanged: (val) => _settings.setAiStockGuard(val),
          title: Text(
            tr('settings_ai_stock_guard'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            tr('settings_ai_stock_guard_sub'),
            style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
          ),
        ),
      ],
    );
  }

  // Section 5: Quick Menu Availability Overrides
  Widget _buildMenuOverridesSection() {
    return _buildCardWrapper(
      title: tr('settings_menu_overrides'),
      icon: Icons.checklist_rounded,
      children: [
        const Text(
          'Directly override item availability (Enable to Force Ready, Disable to Force Sold Out):',
          style: TextStyle(fontSize: 11, color: AppTheme.slateMuted),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<MenuItem>>(
          stream: _firestore.streamMenuItems(),
          initialData: widget.menuItems,
          builder: (context, snapshot) {
            final liveItems = snapshot.data ?? widget.menuItems;
            // Merge & deduplicate by ID and trimmed lowercase name across local catalog, widget, and Firestore
            final Map<String, MenuItem> mergedMap = {};
            for (final it in widget.menuItems) {
              final key = it.id.isNotEmpty ? it.id : it.name.trim().toLowerCase();
              mergedMap[key] = it;
            }
            for (final it in MenuCatalogService().items) {
              final key = it.id.isNotEmpty ? it.id : it.name.trim().toLowerCase();
              mergedMap[key] = it;
            }
            for (final it in liveItems) {
              final key = it.id.isNotEmpty ? it.id : it.name.trim().toLowerCase();
              mergedMap[key] = it;
            }
            final allItems = mergedMap.values.toList();

            return ValueListenableBuilder<Map<String, MenuOverrideState>>(
              valueListenable: MenuAvailabilityNotifier(),
              builder: (context, overrides, _) {
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: allItems.length,
                  itemBuilder: (context, index) {
                    final item = allItems[index];
                    final override = MenuAvailabilityNotifier().getOverride(item);
                    final isReady = MenuAvailabilityNotifier().isItemReady(item, _rawStockMap);
                    final isOverridden = override != MenuOverrideState.auto;

                    String badgeLabel;
                    Color badgeBg;
                    Color badgeFg;
                    if (override == MenuOverrideState.forceReady) {
                      badgeLabel = 'FORCE READY';
                      badgeBg = const Color(0xFFDCFCE7);
                      badgeFg = const Color(0xFF15803D);
                    } else if (override == MenuOverrideState.forceSoldOut) {
                      badgeLabel = 'FORCE SOLD OUT';
                      badgeBg = const Color(0xFFFEE2E2);
                      badgeFg = AppTheme.roseRed;
                    } else {
                      badgeLabel = isReady ? 'AUTO (Ready)' : 'AUTO (Sold Out)';
                      badgeBg = AppTheme.lightBlueTint;
                      badgeFg = AppTheme.royalBlue;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Text(item.iconEmoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        badgeLabel,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: badgeFg,
                                        ),
                                      ),
                                    ),
                                    if (isOverridden) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => _handleResetAuto(item),
                                        borderRadius: BorderRadius.circular(4),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          child: Text(
                                            'Reset Auto',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.cobaltBlue,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Transform.scale(
                            scale: 0.85,
                            child: Switch.adaptive(
                              value: isReady,
                              activeThumbColor: const Color(0xFF15803D),
                              activeTrackColor: const Color(0xFF86EFAC),
                              inactiveThumbColor: AppTheme.roseRed,
                              inactiveTrackColor: const Color(0xFFFECACA),
                              onChanged: (bool newVal) {
                                _handleMenuOverrideToggle(item, newVal);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleMenuOverrideToggle(MenuItem item, bool isReady) async {
    HapticFeedback.lightImpact();
    final nextState = isReady ? MenuOverrideState.forceReady : MenuOverrideState.forceSoldOut;

    // 1. Update in-memory reactive notifier, SharedPreferences, and Firestore
    await MenuAvailabilityNotifier().setOverride(item, nextState);

    // 2. Notify PosState for any dependent UI
    _posState.notifyMenuChanged();
    if (mounted) setState(() {});
  }

  Future<void> _handleResetAuto(MenuItem item) async {
    HapticFeedback.lightImpact();
    await MenuAvailabilityNotifier().resetItem(item);
    _posState.notifyMenuChanged();
    if (mounted) setState(() {});
  }

  // Section 6: Midtrans Sandbox & Payment Config
  Widget _buildMidtransConfigSection() {
    return _buildCardWrapper(
      title: tr('settings_midtrans_config'),
      icon: Icons.qr_code_2_rounded,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: AppTheme.royalBlue,
          value: _settings.enableCash,
          title: const Text('Cash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Full offline transaction support', style: TextStyle(fontSize: 11)),
          onChanged: (val) => _settings.setPaymentChannels(
            cash: val ?? true,
            qris: _settings.enableMidtransQris,
            card: _settings.enableMidtransCard,
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: AppTheme.royalBlue,
          value: _settings.enableMidtransQris,
          title: const Text('Midtrans QRIS Sandbox', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Pindai GoPay / BCA / ShopeePay Sandbox', style: TextStyle(fontSize: 11)),
          onChanged: (val) => _settings.setPaymentChannels(
            cash: _settings.enableCash,
            qris: val ?? true,
            card: _settings.enableMidtransCard,
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: AppTheme.royalBlue,
          value: _settings.enableMidtransCard,
          title: const Text('Midtrans Debit/Credit Card Sandbox', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: const Text('Kartu Uji 4811-1111-1111-1114', style: TextStyle(fontSize: 11)),
          onChanged: (val) => _settings.setPaymentChannels(
            cash: _settings.enableCash,
            qris: _settings.enableMidtransQris,
            card: val ?? true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr('settings_qris_expiry'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            DropdownButton<int>(
              value: _settings.qrisExpiryMinutes,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 Menit')),
                DropdownMenuItem(value: 10, child: Text('10 Menit')),
                DropdownMenuItem(value: 15, child: Text('15 Menit')),
              ],
              onChanged: (val) {
                if (val != null) _settings.setQrisExpiryMinutes(val);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildTextField(
          _keyController,
          tr('settings_local_key'),
          hint: tr('settings_local_key_hint'),
          onChanged: (val) => _settings.setLocalMidtransKey(val),
        ),
      ],
    );
  }

  // Section 7: Hybrid AI & Demo Controls
  Widget _buildAiAndDemoSection() {
    return _buildCardWrapper(
      title: tr('settings_hybrid_ai_demo'),
      icon: Icons.psychology_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'Bahasa / Language:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English (EN)')),
                ButtonSegment(value: 'id', label: Text('Bahasa (ID)')),
              ],
              selected: {_loc.currentLanguage.value},
              onSelectionChanged: (set) => _loc.setLanguage(set.first),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                tr('settings_ai_mode'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            DropdownButton<String>(
              value: _settings.aiMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'preferOnDevice', child: Text('preferOnDevice (Hybrid)')),
                DropdownMenuItem(value: 'onlyInCloud', child: Text('onlyInCloud (Gemini 3.8)')),
              ],
              onChanged: (val) {
                if (val != null) _settings.setAiMode(val);
              },
            ),
          ],
        ),
        const Divider(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('settings_reset_demo')),
                  content: Text(tr('settings_reset_confirm')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.roseRed),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _firestore.seedInitialDataIfEmpty();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Demo data re-seeded!')),
                          );
                        }
                      },
                      child: const Text('Reset', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.roseRed,
              side: const BorderSide(color: AppTheme.roseRed),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(tr('settings_reset_demo'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    String? suffix,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppTheme.slateLight),
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildCashierShiftRosterSection() {
    final roster = _shiftService.roster;
    final active = _shiftService.currentSession;
    final history = _shiftService.history;

    return _buildCardWrapper(
      title: tr('manage_roster_title'),
      icon: Icons.badge_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${roster.length} Staff Terdaftar',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkNavy,
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldenAmber,
                foregroundColor: AppTheme.darkNavy,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.person_add_rounded, size: 14),
              label: Text(
                tr('add_employee_btn'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: _showAddStaffDialog,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // List of staff
        ...roster.map((emp) {
          final isActiveCashier = active.cashierId == emp.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActiveCashier ? AppTheme.lightBlueTint : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActiveCashier ? AppTheme.cobaltBlue : AppTheme.cardBorder,
                width: isActiveCashier ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isActiveCashier ? AppTheme.royalBlue : AppTheme.lightBlueTint,
                  child: Text(
                    emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'K',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isActiveCashier ? AppTheme.brightYellow : AppTheme.royalBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              emp.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.darkNavy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActiveCashier) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.brightYellow,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ACTIVE NOW',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${emp.role} • ${emp.defaultShiftLabel} (${emp.startTime} - ${emp.endTime})',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),

        if (history.isNotEmpty) ...[
          const Divider(height: 20, color: AppTheme.cardBorder),
          Text(
            '${tr('shift_history_title')} (${history.length})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 6),
          ...history.take(3).map((h) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.iceBlueScaffold,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${h.cashierName} (${h.shiftLabel})',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${h.startTime.toString().substring(5, 16)} • ${h.totalOrders} order',
                        style: const TextStyle(fontSize: 10, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                  Text(
                    'Omzet: Rp ${h.grossSales}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.royalBlue),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  void _showAddStaffDialog() {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: 'Cashier');
    final shiftLabelCtrl = TextEditingController(text: 'General Shift');
    final startCtrl = TextEditingController(text: '08:00');
    final endCtrl = TextEditingController(text: '16:00');
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.person_add_rounded, color: AppTheme.royalBlue, size: 20),
            const SizedBox(width: 8),
            Text(tr('add_employee_btn')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Karyawan'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(labelText: 'Jabatan / Role'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: shiftLabelCtrl,
                decoration: const InputDecoration(labelText: 'Label Shift (e.g. Morning Shift)'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(labelText: '4-Digit PIN (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final newEmp = CashierEmployee(
                id: 'emp_${DateTime.now().millisecondsSinceEpoch}',
                name: nameCtrl.text.trim(),
                role: roleCtrl.text.trim().isNotEmpty ? roleCtrl.text.trim() : 'Cashier',
                defaultShiftLabel: shiftLabelCtrl.text.trim().isNotEmpty ? shiftLabelCtrl.text.trim() : 'General Shift',
                startTime: startCtrl.text.trim().isNotEmpty ? startCtrl.text.trim() : '08:00',
                endTime: endCtrl.text.trim().isNotEmpty ? endCtrl.text.trim() : '16:00',
                pin: pinCtrl.text.trim(),
              );

              await _shiftService.addEmployee(newEmp);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF15803D),
                    content: Text('Employee ${newEmp.name} added successfully!'),
                  ),
                );
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

}
