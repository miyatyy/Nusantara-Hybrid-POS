import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/settings_service.dart';
import '../services/local_kitchen_bridge.dart';
import '../theme/app_theme.dart';

/// Role 2 — Queue Display Screen (Layar Antrian Pelanggan)
/// Real-time live customer queue board with 2 prominent columns:
/// 1. Sedang Disiapkan (Preparing / Cooking)
/// 2. Siap Diambil (Ready for Pickup)
/// Triggers audible chime and callout when an order moves to Ready.
class QueueDisplayScreen extends StatefulWidget {
  final List<PosTransaction> transactions;

  const QueueDisplayScreen({
    super.key,
    required this.transactions,
  });

  @override
  State<QueueDisplayScreen> createState() => _QueueDisplayScreenState();
}

class _QueueDisplayScreenState extends State<QueueDisplayScreen> {
  final SettingsService _settings = SettingsService();
  final LocalKitchenBridge _bridge = LocalKitchenBridge();
  final Set<String> _announcedReadyOrders = {};
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  String? _activeAnnouncement;
  Timer? _announcementTimer;

  @override
  void initState() {
    super.initState();
    _bridge.startAutoDiscovery();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _announcementTimer?.cancel();
    super.dispose();
  }

  void _checkAndAnnounceReady(List<PosTransaction> readyOrders) {
    for (final order in readyOrders) {
      if (!_announcedReadyOrders.contains(order.receiptId)) {
        _announcedReadyOrders.add(order.receiptId);
        // Play audible alert and haptic chime
        try {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        } catch (_) {}

        if (mounted) {
          setState(() {
            _activeAnnouncement = 'Queue number ${order.queueNumber}, please pick up your order at the counter!';
          });
          _announcementTimer?.cancel();
          _announcementTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _activeAnnouncement = null);
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bridge,
      builder: (context, _) {
        // Merge Firestore transactions with local offline orders
        final allOrders = _mergeOrders(widget.transactions, _bridge.localOrders);

        final preparingOrders = allOrders
            .where((t) => t.kitchenStatus == 'preparing' || t.kitchenStatus == 'cooking')
            .toList();

        final readyOrders = allOrders
            .where((t) => t.kitchenStatus == 'ready')
            .toList();

        // Trigger audio callout for newly ready orders
        _checkAndAnnounceReady(readyOrders);

        final timeStr = DateFormat('HH:mm:ss').format(_now);
        String dateStr;
        try {
          dateStr = DateFormat('EEEE, d MMMM yyyy', 'en_US').format(_now);
        } catch (_) {
          dateStr = DateFormat('EEEE, d MMMM yyyy').format(_now);
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A), // Deep Midnight Navy for high contrast
          body: SafeArea(
            child: Column(
              children: [
                // Live Callout Announcement Banner
                if (_activeAnnouncement != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      boxShadow: [
                        BoxShadow(color: Color(0xFFF59E0B), blurRadius: 16, spreadRadius: 2),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.campaign_rounded, color: Color(0xFF1E3A8A), size: 28),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _activeAnnouncement!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E3A8A),
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1. Top Header: Store Branding & Live Clock
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.royalBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.tv_rounded, color: AppTheme.brightYellow, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _settings.storeName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'OFFICIAL QUEUE DISPLAY • NUSANTARA HYBRID POS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.goldenAmber.withAlpha(220),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. The 2 Large Columns
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Column A: Preparing
                        Expanded(
                          child: _buildQueueColumn(
                            title: 'PREPARING',
                            subtitle: 'Chef Is Preparing Your Order',
                            icon: Icons.outdoor_grill_rounded,
                            accentColor: const Color(0xFFF59E0B),
                            badgeColor: const Color(0xFFB45309),
                            orders: preparingOrders,
                            isReadyColumn: false,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Column B: Ready for Pickup
                        Expanded(
                          child: _buildQueueColumn(
                            title: 'READY FOR PICKUP',
                            subtitle: 'Please Proceed to the Pickup Counter',
                            icon: Icons.check_circle_rounded,
                            accentColor: const Color(0xFF10B981),
                            badgeColor: const Color(0xFF065F46),
                            orders: readyOrders,
                            isReadyColumn: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Bottom Ticker & Customer Info
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: const Color(0xFF1E293B),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded, color: AppTheme.brightYellow, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Scan the QR code on your receipt to track kitchen progress & receive live pickup alerts on your phone.',
                          style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${preparingOrders.length + readyOrders.length} Active Orders',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueColumn({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color badgeColor,
    required List<PosTransaction> orders,
    required bool isReadyColumn,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withAlpha(120), width: 2),
        boxShadow: isReadyColumn
            ? [
                BoxShadow(
                  color: accentColor.withAlpha(50),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE2E8F0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Numbers Grid
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isReadyColumn ? Icons.check_circle_outline : Icons.hourglass_empty_rounded,
                          size: 48,
                          color: const Color(0xFF475569),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isReadyColumn ? 'No orders ready yet' : 'No orders currently preparing',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isTakeAway = order.orderMode.toUpperCase().contains('TAKE') ||
                          order.orderMode.toUpperCase().contains('BUNGKUS');

                      return Container(
                        decoration: BoxDecoration(
                          color: isReadyColumn ? const Color(0xFF064E3B) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isReadyColumn ? const Color(0xFF10B981) : const Color(0xFF3B82F6).withAlpha(140),
                            width: isReadyColumn ? 2.2 : 1.5,
                          ),
                          boxShadow: isReadyColumn
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withAlpha(70),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              order.queueNumber,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: isReadyColumn ? AppTheme.brightYellow : Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isTakeAway ? 'TAKE AWAY' : 'DINE IN',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<PosTransaction> _mergeOrders(List<PosTransaction> remote, List<PosTransaction> local) {
    final Map<String, PosTransaction> map = {};
    for (final t in remote) {
      map[t.receiptId] = t;
    }
    for (final t in local) {
      map[t.receiptId] = t;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }
}
