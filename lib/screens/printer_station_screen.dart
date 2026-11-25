import 'package:flutter/material.dart';
import '../models/order_item.dart';
import '../models/menu_item.dart';
import '../models/transaction_model.dart';
import '../services/settings_service.dart';
import '../sdk/nusantara_printer_sdk.dart';
import '../theme/app_theme.dart';

class PrinterStationScreen extends StatefulWidget {
  final VoidCallback? onReturnToCashier;
  final VoidCallback? onOpenDrawer;

  const PrinterStationScreen({
    super.key,
    this.onReturnToCashier,
    this.onOpenDrawer,
  });

  @override
  State<PrinterStationScreen> createState() => _PrinterStationScreenState();
}

class _PrinterStationScreenState extends State<PrinterStationScreen> {
  final NusantaraPrinterSDK _printerSdk = NusantaraPrinterSDK();
  final SettingsService _settings = SettingsService();

  late TextEditingController _kitchenIpController;
  List<BluetoothPrinterDevice> _pairedDevices = [];
  List<DiscoveredNetworkPrinter> _discoveredPrinters = [];
  bool _isLoadingBt = false;
  bool _isScanningWifi = false;
  bool _isTestingBt = false;
  bool _isTestingWifi = false;

  @override
  void initState() {
    super.initState();
    _kitchenIpController = TextEditingController(text: _printerSdk.kitchenPrinterIp);
    _refreshBluetoothDevices();
  }

  @override
  void dispose() {
    _kitchenIpController.dispose();
    super.dispose();
  }

  Future<void> _refreshBluetoothDevices() async {
    setState(() => _isLoadingBt = true);
    await _printerSdk.checkAndRequestPermissions();
    final devices = await _printerSdk.getPairedPrinters();
    if (mounted) {
      setState(() {
        _pairedDevices = devices;
        _isLoadingBt = false;
      });
    }
  }

  Future<void> _scanKitchenWifi() async {
    setState(() => _isScanningWifi = true);
    final results = await _printerSdk.scanKitchenWifiPrinters();
    if (mounted) {
      setState(() {
        _discoveredPrinters = results;
        _isScanningWifi = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: results.isNotEmpty ? const Color(0xFF15803D) : const Color(0xFFD97706),
          content: Text(
            results.isNotEmpty
                ? 'Ditemukan ${results.length} printer ESC/POS port 9100!'
                : 'Tidak ada printer port 9100 terdeteksi pada subnet saat ini.',
          ),
        ),
      );
    }
  }

  Future<void> _testPrintReceipt() async {
    if (!_printerSdk.hasPrinterSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.roseRed,
          content: Text('Pilih perangkat printer Bluetooth terlebih dahulu.'),
        ),
      );
      return;
    }

    setState(() => _isTestingBt = true);
    try {
      final ok = await _printerSdk.printTestReceipt(storeName: _settings.storeName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: ok ? const Color(0xFF15803D) : AppTheme.roseRed,
            content: Text(ok ? 'Struk uji Bluetooth berhasil dikirim!' : 'Gagal mengirim struk ke printer Bluetooth.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingBt = false);
    }
  }

  Future<void> _testPrintKitchenTicket() async {
    setState(() => _isTestingWifi = true);
    try {
      final dummyTx = PosTransaction(
        id: 'KDS-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        timestamp: DateTime.now(),
        items: [
          OrderItem(
            menuItem: MenuItem(
              id: 'm1',
              name: 'Nasi Goreng Kampung',
              category: 'Makanan',
              price: 32000,
              description: '',
            ),
            quantity: 2,
            notes: 'Pedas level 3, ekstra telur ceplok',
          ),
          OrderItem(
            menuItem: MenuItem(
              id: 'd1',
              name: 'Es Kopi Gula Aren',
              category: 'Minuman',
              price: 18000,
              description: '',
            ),
            quantity: 2,
            notes: 'Less sugar, less ice',
          ),
        ],
        subtotal: 100000,
        tax: 10000,
        total: 110000,
        paymentMethod: 'Cash',
        cashReceived: 110000,
        changeAmount: 0,
        orderMode: 'Dine In (Meja #07)',
        queueNumber: '#015',
      );

      final ok = await _printerSdk.printKitchenOrderTicket(dummyTx, forceManual: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: ok ? const Color(0xFF15803D) : AppTheme.roseRed,
            content: Text(
              ok
                  ? 'Tiket Dapur berhasil dicetak ke ${_printerSdk.kitchenPrinterIp}!'
                  : 'Gagal mencetak tiket dapur. Pastikan printer menyala di port 9100.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingWifi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _printerSdk,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.iceBlueScaffold,
          appBar: AppBar(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              tooltip: 'Menu Navigasi',
              onPressed: () {
                widget.onOpenDrawer?.call();
              },
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print_rounded, color: AppTheme.brightYellow, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Stasiun Auto-Printer (Role 5)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Relay Bluetooth & ESC/POS Wi-Fi Port 9100',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.onReturnToCashier != null)
                TextButton.icon(
                  onPressed: widget.onReturnToCashier,
                  icon: const Icon(Icons.storefront_rounded, color: AppTheme.brightYellow, size: 16),
                  label: const Text('Ke Kasir', style: TextStyle(color: AppTheme.brightYellow, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Live Relay Status Banner
                _buildRelayStatusCard(),
                const SizedBox(height: 16),

                // Card 1: Bluetooth Receipt Printer (Cashier)
                _buildBluetoothCard(),
                const SizedBox(height: 16),

                // Card 2: Kitchen Wi-Fi Printer (KDS ESC/POS Port 9100)
                _buildKitchenWifiCard(),
                const SizedBox(height: 16),

                // Card 3: Auto-Print Automation Settings
                _buildAutomationCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRelayStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hub_rounded, color: AppTheme.royalBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Status Relay Pencetakan POS',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.darkNavy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatusPill(
                  title: 'Cashier Receipt Printer',
                  status: _printerSdk.hasPrinterSelected
                      ? _printerSdk.selectedPrinterName
                      : 'Not Connected',
                  isOk: _printerSdk.hasPrinterSelected,
                  icon: Icons.bluetooth_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusPill(
                  title: 'Floor 2 Kitchen Printer',
                  status: _printerSdk.hasKitchenPrinterSelected
                      ? '${_printerSdk.kitchenPrinterIp}:9100'
                      : 'Not Connected',
                  isOk: _printerSdk.hasKitchenPrinterSelected,
                  icon: Icons.wifi_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    required String title,
    required String status,
    required bool isOk,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isOk ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOk ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isOk ? const Color(0xFF15803D) : AppTheme.roseRed),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 9.5, color: AppTheme.slateMuted)),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isOk ? const Color(0xFF15803D) : AppTheme.roseRed,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_searching_rounded, color: AppTheme.royalBlue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bluetooth Receipt Printer (ESC/POS)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: _isLoadingBt
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, color: AppTheme.royalBlue),
                tooltip: 'Scan Devices',
                onPressed: _isLoadingBt ? null : _refreshBluetoothDevices,
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_pairedDevices.isEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.slateMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No Bluetooth printer connected. Pair a printer in your device Bluetooth settings.',
                      style: TextStyle(fontSize: 10.5, color: AppTheme.slateMuted),
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
                  hint: const Text('Select Bluetooth Receipt Printer', style: TextStyle(fontSize: 12)),
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
          // Paper Width Segmented Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Receipt Paper Width:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 58, label: Text('58 mm', style: TextStyle(fontSize: 10))),
                  ButtonSegment(value: 80, label: Text('80 mm', style: TextStyle(fontSize: 10))),
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
            ],
          ),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isTestingBt
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text('Print Bluetooth Test Receipt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _isTestingBt ? null : _testPrintReceipt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKitchenWifiCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.wifi_rounded, color: AppTheme.royalBlue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Wi-Fi Kitchen Printer (Port 9100)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.goldenAmber,
                  foregroundColor: AppTheme.darkNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isScanningWifi
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkNavy))
                    : const Icon(Icons.radar_rounded, size: 14),
                label: Text(
                  _isScanningWifi ? 'Scanning...' : 'Scan Subnet',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _isScanningWifi ? null : _scanKitchenWifi,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Discovered list
          if (_discoveredPrinters.isNotEmpty) ...[
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
                  const Text('Wi-Fi Printers Found:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ..._discoveredPrinters.map((p) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.print, color: AppTheme.royalBlue, size: 18),
                      title: Text('${p.ip}:9100', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
                      subtitle: Text('Response: ${p.latencyMs}ms', style: const TextStyle(fontSize: 9.5, color: Color(0xFF15803D))),
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        onPressed: () {
                          setState(() {
                            _kitchenIpController.text = p.ip;
                          });
                          _printerSdk.saveKitchenPrinterConfig(
                            ip: p.ip,
                            autoPrint: _printerSdk.kitchenAutoPrintEnabled,
                          );
                        },
                        child: const Text('Use', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // IP TextField
          TextField(
            controller: _kitchenIpController,
            decoration: InputDecoration(
              labelText: 'Kitchen Printer IP Address',
              hintText: '192.168.1.200',
              prefixIcon: const Icon(Icons.lan_rounded, size: 18, color: AppTheme.royalBlue),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_rounded, size: 18, color: AppTheme.royalBlue),
                tooltip: 'Save IP',
                onPressed: () {
                  _printerSdk.saveKitchenPrinterConfig(
                    ip: _kitchenIpController.text.trim(),
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

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.royalBlue,
                side: const BorderSide(color: AppTheme.royalBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isTestingWifi
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restaurant_menu_rounded, size: 16),
              label: const Text('Print Kitchen Test Ticket (KOT Test)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _isTestingWifi ? null : _testPrintKitchenTicket,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_mode_rounded, color: AppTheme.royalBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Print Automation',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-Print Kitchen Order Ticket (KOT)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            subtitle: const Text('Send order ticket print job to kitchen Wi-Fi immediately after cashier checkout', style: TextStyle(fontSize: 10, color: AppTheme.slateLight)),
            value: _printerSdk.kitchenAutoPrintEnabled,
            activeTrackColor: AppTheme.goldenAmber,
            onChanged: (val) {
              _printerSdk.saveKitchenPrinterConfig(
                ip: _kitchenIpController.text.trim(),
                autoPrint: val,
              );
            },
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reset Kitchen Ticket Cache', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(
                      'Clear history of order IDs already printed in the kitchen',
                      style: TextStyle(fontSize: 10, color: AppTheme.slateLight),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  await _printerSdk.clearPrintedKitchenOrderIds();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF15803D),
                        content: Text('Kitchen ticket ID cache cleared!'),
                      ),
                    );
                  }
                },
                child: const Text('Bersihkan Cache', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
