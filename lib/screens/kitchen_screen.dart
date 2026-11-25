import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import '../services/local_kitchen_bridge.dart';
import '../services/whatsapp_gateway_service.dart';
import '../services/settings_service.dart';
import '../sdk/nusantara_printer_sdk.dart';
import '../theme/app_theme.dart';
import 'customer_order_tracker_screen.dart';

/// Role 3 — Adaptive Kitchen Display & Auto-Print Station (KDS Kanban)
/// Responsive Phone-to-Tablet adaptive layout:
/// - Phone Mode (width < 600): Single-column mobile view with top segmented tabs.
/// - Tablet Mode (width >= 600): Full 3-column side-by-side Kanban board.
/// Real-Time Kitchen Auto-Print: Automatically prints bold KOT tickets via Wi-Fi/Bluetooth.
/// Offline LAN Discovery: Discovers Master Cashier IP (port 8765) during blackouts.
class KitchenScreen extends StatefulWidget {
  final List<PosTransaction> transactions;

  const KitchenScreen({
    super.key,
    required this.transactions,
  });

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  final FirestoreService _firestore = FirestoreService();
  final LocalKitchenBridge _bridge = LocalKitchenBridge();
  final NusantaraPrinterSDK _printerSdk = NusantaraPrinterSDK();
  final SettingsService _settings = SettingsService();

  String _selectedStage = 'cooking'; // Default to 'cooking' (Sedang Dimasak)
  final Set<String> _printedOrderIds = {};

  @override
  void initState() {
    super.initState();
    _bridge.startAutoDiscovery();
    _loadPrintedCache().then((_) {
      _checkAndAutoPrintKitchenTickets();
    });
  }

  Future<void> _loadPrintedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('printedKitchenOrderIds') ?? [];
      _printedOrderIds.addAll(list);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant KitchenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAndAutoPrintKitchenTickets();
  }

  Future<void> _checkAndAutoPrintKitchenTickets() async {
    if (!_printerSdk.kitchenAutoPrintEnabled) return;

    final merged = _mergeOrders(widget.transactions, _bridge.localOrders);
    for (final order in merged) {
      final keyReceipt = order.receiptId.trim();
      final keyId = order.id.trim();
      final alreadyPrinted = (keyReceipt.isNotEmpty && _printedOrderIds.contains(keyReceipt)) ||
          (keyId.isNotEmpty && _printedOrderIds.contains(keyId));
      if (order.kitchenStatus == 'preparing' && !alreadyPrinted) {
        if (keyReceipt.isNotEmpty) _printedOrderIds.add(keyReceipt);
        if (keyId.isNotEmpty) _printedOrderIds.add(keyId);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('printedKitchenOrderIds', _printedOrderIds.toList());
        } catch (_) {}

        // 1. Play alert chime & haptic alert for kitchen crew
        try {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        } catch (_) {}

        // 2. Automatically print bold Kitchen Order Ticket (KOT) once
        await _printerSdk.printKitchenOrderTicket(order);

        // 3. Immediately advance order status to 'cooking' across Cloud & Local LAN
        _changeKitchenStatus(order.id, 'cooking', order);
      }
    }
  }

  List<PosTransaction> _mergeOrders(List<PosTransaction> remote, List<PosTransaction> local) {
    final Map<String, PosTransaction> map = {};
    for (final t in remote) {
      map[t.receiptId] = t;
    }
    for (final t in local) {
      final existing = map[t.receiptId];
      if (existing != null && t.customerPhone.trim().isEmpty && existing.customerPhone.trim().isNotEmpty) {
        map[t.receiptId] = t.copyWith(customerPhone: existing.customerPhone);
      } else {
        map[t.receiptId] = t;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bridge, _printerSdk]),
      builder: (context, _) {
        final allOrders = _mergeOrders(widget.transactions, _bridge.localOrders);

        final preparingOrders = allOrders.where((t) => t.kitchenStatus == 'preparing').toList();
        final cookingOrders = allOrders.where((t) => t.kitchenStatus == 'cooking').toList();
        final readyOrders = allOrders.where((t) => t.kitchenStatus == 'ready').toList();
        final completedOrders = allOrders.where((t) => t.kitchenStatus == 'completed').toList();

        final activeOrders = allOrders.where((t) {
          if (_selectedStage == 'all') return t.kitchenStatus != 'completed';
          if (_selectedStage == 'cooking') return t.kitchenStatus == 'cooking' || t.kitchenStatus == 'preparing';
          return t.kitchenStatus == _selectedStage;
        }).toList();

        return Scaffold(
          backgroundColor: AppTheme.iceBlueScaffold,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth >= 600;

                return Column(
                  children: [
                    // 1. Top Header: KDS status, Master Bridge discovery, Auto-Print pill
                    _buildKitchenHeader(
                      totalActive: preparingOrders.length + cookingOrders.length + readyOrders.length,
                      isTablet: isTablet,
                    ),

                    // 2. Responsive Content
                    Expanded(
                      child: isTablet
                          ? _buildTablet3ColumnKanban(
                              preparing: preparingOrders,
                              cooking: cookingOrders,
                              ready: readyOrders,
                            )
                          : _buildPhoneSingleColumn(
                              activeOrders: activeOrders,
                              preparingCount: preparingOrders.length,
                              cookingCount: cookingOrders.length,
                              readyCount: readyOrders.length,
                              completedCount: completedOrders.length,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // 1. Top KDS Header
  Widget _buildKitchenHeader({required int totalActive, required bool isTablet}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.cardBorder, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.royalBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.soup_kitchen_rounded,
              color: AppTheme.brightYellow,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isTablet ? 'Kitchen Display (TAB)' : 'Kitchen KDS',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isTablet ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isTablet ? 'Tablet' : 'Mobile',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: isTablet ? const Color(0xFF15803D) : AppTheme.royalBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _bridge.discoveredMasterIp.isNotEmpty
                      ? 'LAN: ${_bridge.discoveredMasterIp}'
                      : 'Dual Cloud + Router LAN',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: _bridge.discoveredMasterIp.isNotEmpty ? const Color(0xFF15803D) : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Pindai IP Master Cashier (Offline Discovery) Button
          IconButton(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: _bridge.isScanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.royalBlue),
                  )
                : const Icon(Icons.wifi_find_rounded, color: AppTheme.royalBlue, size: 20),
            tooltip: 'Scan Master Cashier LAN IP (Port 8765)',
            onPressed: _bridge.isScanning
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    final ip = await _bridge.scanAndDiscoverMasterCashier();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: ip != null ? const Color(0xFF15803D) : AppTheme.roseRed,
                          content: Text(
                            ip != null
                                ? 'Connected to Master Cashier: $ip'
                                : 'Master Cashier not detected on router subnet.',
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(width: 4),

          // Auto-Print Toggle Pill
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _printerSdk.saveKitchenPrinterConfig(
                ip: _printerSdk.kitchenPrinterIp,
                port: _printerSdk.kitchenPrinterPort,
                autoPrint: !_printerSdk.kitchenAutoPrintEnabled,
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _printerSdk.kitchenAutoPrintEnabled
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _printerSdk.kitchenAutoPrintEnabled
                      ? const Color(0xFF15803D)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.print_rounded,
                    size: 11,
                    color: _printerSdk.kitchenAutoPrintEnabled
                        ? const Color(0xFF15803D)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _printerSdk.kitchenAutoPrintEnabled ? 'KOT' : 'OFF',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: _printerSdk.kitchenAutoPrintEnabled
                          ? const Color(0xFF15803D)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Total Active Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.royalBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$totalActive Active',
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2A. Phone Single-Column Mode
  Widget _buildPhoneSingleColumn({
    required List<PosTransaction> activeOrders,
    required int preparingCount,
    required int cookingCount,
    required int readyCount,
    required int completedCount,
  }) {
    return Column(
      children: [
        // Segmented Tabs
        _buildStageFilterBar(
          preparingCount: preparingCount,
          cookingCount: cookingCount,
          readyCount: readyCount,
          completedCount: completedCount,
        ),
        // List
        Expanded(
          child: activeOrders.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: activeOrders.length,
                  itemBuilder: (context, index) {
                    final order = activeOrders[index];
                    return _buildKitchenOrderCard(order);
                  },
                ),
        ),
      ],
    );
  }

  // 2B. Tablet 3-Column Kanban Board (Floor 2 Kitchen TAB)
  Widget _buildTablet3ColumnKanban({
    required List<PosTransaction> preparing,
    required List<PosTransaction> cooking,
    required List<PosTransaction> ready,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column 1: Preparing
          Expanded(
            child: _buildKanbanColumn(
              title: '1. PREPARING',
              subtitle: 'Incoming Queue from Cashier',
              icon: Icons.kitchen_rounded,
              accentColor: const Color(0xFF2563EB),
              badgeColor: const Color(0xFF1E3A8A),
              orders: preparing,
            ),
          ),
          const SizedBox(width: 12),
          // Column 2: Cooking
          Expanded(
            child: _buildKanbanColumn(
              title: '2. COOKING',
              subtitle: 'Chef Is Preparing',
              icon: Icons.outdoor_grill_rounded,
              accentColor: const Color(0xFFD97706),
              badgeColor: const Color(0xFFB45309),
              orders: cooking,
            ),
          ),
          const SizedBox(width: 12),
          // Column 3: Ready for Pickup
          Expanded(
            child: _buildKanbanColumn(
              title: '3. READY FOR PICKUP',
              subtitle: 'Call Customer / Ready to Serve',
              icon: Icons.check_circle_rounded,
              accentColor: const Color(0xFF15803D),
              badgeColor: const Color(0xFF065F46),
              orders: ready,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanColumn({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color badgeColor,
    required List<PosTransaction> orders,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withAlpha(120), width: 1.5),
      ),
      child: Column(
        children: [
          // Column Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFE2E8F0),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable List of Order Cards
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      'Kosong',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return _buildKitchenOrderCard(order, isCompact: true);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Segmented Kanban Stage Filter Bar for Phone Mode
  Widget _buildStageFilterBar({
    required int preparingCount,
    required int cookingCount,
    required int readyCount,
    required int completedCount,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStageTab('cooking', 'Cooking', cookingCount + preparingCount, Icons.outdoor_grill_rounded, const Color(0xFFD97706)),
            const SizedBox(width: 8),
            _buildStageTab('ready', 'Ready', readyCount, Icons.check_circle_rounded, const Color(0xFF15803D)),
            const SizedBox(width: 8),
            _buildStageTab('completed', 'Completed', completedCount, Icons.done_all_rounded, AppTheme.slateMuted),
            const SizedBox(width: 8),
            _buildStageTab('all', 'All Active', preparingCount + cookingCount + readyCount, Icons.dashboard_rounded, AppTheme.royalBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildStageTab(String stageKey, String label, int count, IconData icon, Color activeColor) {
    final isSelected = _selectedStage == stageKey;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedStage = stageKey);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppTheme.darkNavy),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.darkNavy,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withAlpha(50) : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : activeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Kitchen Order Card
  Widget _buildKitchenOrderCard(PosTransaction order, {bool isCompact = false}) {
    final elapsedMinutes = DateTime.now().difference(order.timestamp).inMinutes;
    final isTakeAway = order.orderMode.toUpperCase().contains('TAKE') ||
        order.orderMode.toUpperCase().contains('BUNGKUS');

    Color stageColor;
    switch (order.kitchenStatus) {
      case 'cooking':
        stageColor = const Color(0xFFD97706);
        break;
      case 'ready':
        stageColor = const Color(0xFF15803D);
        break;
      case 'completed':
        stageColor = AppTheme.slateMuted;
        break;
      case 'preparing':
      default:
        stageColor = const Color(0xFF2563EB);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: order.kitchenStatus == 'ready' ? const Color(0xFF15803D) : AppTheme.cardBorder,
          width: order.kitchenStatus == 'ready' ? 2 : 1.2,
        ),
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
          // Header Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: stageColor.withAlpha(22),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                // Queue Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stageColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.queueNumber,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: stageColor.withAlpha(90)),
                  ),
                  child: Text(
                    isTakeAway ? 'TAKE AWAY' : 'DINE IN',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: stageColor,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Text(
                  '$elapsedMinutes mnt',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Items Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...order.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.lightBlueTint,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.royalBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.menuItem.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                              if (item.notes.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Text(
                                    'Notes: ${item.notes}',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: Color(0xFFB45309),
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),

                // Manual KOT Print & Customer Tracker button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _printerSdk.printKitchenOrderTicket(order, forceManual: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.royalBlue,
                            content: Text('Printing Kitchen Order Ticket (KOT) #${order.queueNumber}...'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.print_outlined, size: 13, color: AppTheme.royalBlue),
                          SizedBox(width: 3),
                          Text('Print KOT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.royalBlue)),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final queueInt = int.tryParse(order.queueNumber.replaceAll('#', '')) ?? 1;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerOrderTrackerScreen(
                              orderId: order.id,
                              trackingToken: order.trackingToken,
                              queueNumber: queueInt,
                              initialEtaMinutes: order.estimatedPrepMinutes,
                              customerName: order.customerName,
                              initialTransaction: order,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.qr_code_2_rounded, size: 13, color: AppTheme.royalBlue),
                          SizedBox(width: 3),
                          Text('Tracker QR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.royalBlue)),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        String targetPhone = order.customerPhone.trim();
                        if (targetPhone.isEmpty) {
                          final match = RegExp(r'(?:WA:\s*|08)(\d+)').firstMatch(order.orderNotes);
                          if (match != null) {
                            targetPhone = match.group(0)?.replaceAll('WA:', '').trim() ?? '';
                          }
                        }
                        if (targetPhone.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFFD97706),
                              behavior: SnackBarBehavior.floating,
                              content: Text('Customer WhatsApp number was not entered for this order.'),
                            ),
                          );
                          return;
                        }
                        await WhatsAppGatewayService().openDirectWhatsAppWithQr(
                          customerPhone: targetPhone,
                          order: order,
                          storeName: _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara Hybrid POS',
                          customerName: order.customerName,
                          isReadyAlarm: order.kitchenStatus == 'ready',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.chat_rounded, size: 12, color: Color(0xFF15803D)),
                            SizedBox(width: 3),
                            Text('WA + QR', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF15803D))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 1-Tap Action Progress Button
                _buildActionProgressButton(order),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionProgressButton(PosTransaction order) {
    String label;
    IconData icon;
    Color buttonColor;
    VoidCallback onPressed;

    if (order.kitchenStatus == 'preparing') {
      label = 'Start Cooking →';
      icon = Icons.outdoor_grill_rounded;
      buttonColor = const Color(0xFFD97706);
      onPressed = () => _changeKitchenStatus(order.id, 'cooking', order);
    } else if (order.kitchenStatus == 'cooking') {
      label = 'Done & Notify Customer 🔔';
      icon = Icons.notifications_active_rounded;
      buttonColor = const Color(0xFF15803D);
      onPressed = () => _changeKitchenStatus(order.id, 'ready', order);
    } else if (order.kitchenStatus == 'ready') {
      label = 'Handed Over & Close QR ✓';
      icon = Icons.check_circle_outline_rounded;
      buttonColor = AppTheme.royalBlue;
      onPressed = () => _changeKitchenStatus(order.id, 'completed', order);
    } else {
      label = 'Handed Over';
      icon = Icons.done_all_rounded;
      buttonColor = AppTheme.slateMuted;
      onPressed = () {};
    }

    return SizedBox(
      width: double.infinity,
      height: 38,
      child: ElevatedButton.icon(
        onPressed: order.kitchenStatus == 'completed' ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _changeKitchenStatus(String orderId, String newStatus, PosTransaction order) async {
    HapticFeedback.heavyImpact();

    // 1. Update Firestore
    _firestore.updateKitchenStatus(orderId, newStatus);

    // 2. Update Floor 1 Master / Local Bridge
    _bridge.sendStatusUpdateToMaster(orderId: orderId, status: newStatus);

    if (newStatus == 'cooking' || newStatus == 'ready') {
      final isReady = newStatus == 'ready';
      if (isReady) {
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      }

      final storeName = _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara Hybrid POS';

      if (isReady) {
        WhatsAppGatewayService.triggerLocalReadyNotification(
          title: '🔔 Order ${order.queueNumber} Ready for Pickup!',
          body: 'Order for ${order.customerName} at $storeName is ready for pickup at the counter.',
        );
      }

      // Strictly resolve the WhatsApp number of the buyer who placed THIS specific order/queue
      String waStatusNote = '';
      String targetPhone = order.customerPhone.trim();
      if (targetPhone.isEmpty && order.orderNotes.isNotEmpty) {
        final match = RegExp(r'(?:WA:\s*|HP:\s*|\+?628|08)\d{7,13}').firstMatch(order.orderNotes);
        if (match != null) {
          targetPhone = match.group(0)?.replaceAll(RegExp(r'^(WA:|HP:)\s*'), '').trim() ?? '';
        }
      }
      if (targetPhone.isEmpty) {
        final localMatch = _bridge.localOrders.where(
          (o) =>
              (o.receiptId == order.receiptId || o.id == order.id || o.queueNumber == order.queueNumber) &&
              o.customerPhone.trim().isNotEmpty,
        ).firstOrNull;
        if (localMatch != null) {
          targetPhone = localMatch.customerPhone.trim();
        }
      }
      if (isReady && targetPhone.isEmpty && mounted) {
        final phoneCtrl = TextEditingController();
        final enteredPhone = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              'Customer WhatsApp for ${order.queueNumber}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            content: TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Customer WhatsApp Number (08xx / 628xx)',
                hintText: '081234567890',
                prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF15803D)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Send WA Reminder'),
              ),
            ],
          ),
        );
        if (enteredPhone != null && enteredPhone.trim().length >= 9) {
          targetPhone = enteredPhone.trim();
          await _bridge.updateOrderCustomerPhone(order.id, targetPhone);
          _firestore.updateOrderCustomerPhone(order.id, targetPhone);
        }
      }

      // 100% Automated Background Dispatch via Fonnte when order is cooking or ready
      if (targetPhone.isNotEmpty && (isReady || WhatsAppGatewayService().autoSendReady)) {
        final dispatchRes = await WhatsAppGatewayService().dispatchKitchenStatusViaFonnte(
          customerPhone: targetPhone,
          order: order,
          storeName: storeName,
          status: newStatus,
          customerName: order.customerName,
        );
        if (dispatchRes == 'SENT_FONNTE') {
          waStatusNote = ' • ✓ Fonnte WA reminder sent to $targetPhone!';
        } else if (dispatchRes == 'QUEUED_NO_TOKEN') {
          waStatusNote = ' • WA queued (set Fonnte Token in Settings for auto-send).';
        } else if (dispatchRes == 'QUEUED_OFFLINE' || dispatchRes == 'QUEUED_RETRY') {
          final err = WhatsAppGatewayService().lastError;
          waStatusNote = err.isNotEmpty
              ? ' • WA queued ($err).'
              : ' • WA queued offline (will auto-send when online).';
        }
      } else if (isReady && targetPhone.isEmpty) {
        waStatusNote = ' • No customer phone number on order.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isReady ? const Color(0xFF15803D) : const Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(
                isReady ? Icons.notifications_active_rounded : Icons.soup_kitchen_rounded,
                color: AppTheme.brightYellow,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isReady
                      ? '🔔 Order ${order.queueNumber} Ready for Pickup!$waStatusNote'
                      : '🍳 Order ${order.queueNumber} Is Cooking!$waStatusNote',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.royalBlue.withAlpha(15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.soup_kitchen_rounded,
              size: 42,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No orders in this stage',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.darkNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New orders from the POS will appear here in real-time.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
