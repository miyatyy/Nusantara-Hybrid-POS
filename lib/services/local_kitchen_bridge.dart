import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import 'connectivity_service.dart';
import 'email_auth_service.dart';
import 'firestore_service.dart';
import 'bridge_platform_helper.dart';

/// Embedded Local Master Server and LAN Kitchen Discovery Bridge.
/// Allows Nusantara Hybrid POS to operate during TOTAL BLACKOUTS / ZERO-INTERNET:
/// 1. Master Server (Floor 1 Cashier): Runs an HTTP server on port 8765 (`/ping`, `/orders`, `POST /orders/status`, `/track`).
/// 2. UDP Discovery Beacon: Master broadcasts beacon on UDP port 8766 every 3s so Floor 2 Tablets
///    discover the Master Cashier instantly with zero manual configuration.
/// 3. Outbox persistence: All offline transactions are preserved in `offline_transactions_json`
///    and auto-synced to Cloud Firestore when internet returns.
class LocalKitchenBridge extends ChangeNotifier {
  static final LocalKitchenBridge _instance = LocalKitchenBridge._internal();
  factory LocalKitchenBridge() => _instance;
  LocalKitchenBridge._internal();

  static const int kBridgePort = 8765;
  static const int kUdpBeaconPort = 8766;
  static const String _kOfflineTransactionsKey = 'offline_transactions_json';
  static const String _kMasterIpKey = 'kitchen_bridge_master_ip';

  bool _isServerRunning = false;
  String _discoveredMasterIp = '';
  String _localIp = '';
  bool _isScanning = false;
  Timer? _offlinePollTimer;
  Timer? _fallbackDiscoveryTimer;

  final List<PosTransaction> _localOrders = [];
  List<PosTransaction> get localOrders => List.unmodifiable(_localOrders);

  bool get isServerRunning => _isServerRunning;
  String get discoveredMasterIp => _discoveredMasterIp;
  String get masterIp => _discoveredMasterIp.isNotEmpty ? _discoveredMasterIp : _localIp;
  String get localIp => _localIp;
  bool get isScanning => _isScanning;

  Future<void> init() async {
    await _loadOfflineTransactions();
    try {
      final prefs = await SharedPreferences.getInstance();
      _discoveredMasterIp = prefs.getString(_kMasterIpKey) ?? '';
    } catch (_) {}

    try {
      _localIp = await BridgePlatform.instance.getLocalIp() ?? '';
    } catch (_) {}
  }

  /// Start Embedded HTTP Server & UDP Beacon on Floor 1 Cashier (Master)
  Future<bool> startMasterServer({String storeName = 'Nusantara POS'}) async {
    if (_isServerRunning) return true;

    _localIp = await BridgePlatform.instance.getLocalIp() ?? '';

    final ok = await BridgePlatform.instance.startServer(
      port: kBridgePort,
      onRequest: (path, method, body) async {
        if (path == '/ping' && method == 'GET') {
          return {
            'statusCode': 200,
            'data': {
              'status': 'ok',
              'role': 'master_cashier',
              'app': 'Nusantara Hybrid POS',
              'timestamp': DateTime.now().toIso8601String(),
            },
          };
        }

        if (path == '/orders' && method == 'GET') {
          final jsonList = _localOrders.map((t) => t.toMap()).toList();
          return {
            'statusCode': 200,
            'data': jsonList,
          };
        }

        if (path.startsWith('/track') && method == 'GET') {
          return _generateCustomerTrackerHtml(path);
        }

        if (path == '/orders/status' && method == 'POST') {
          try {
            final data = jsonDecode(body) as Map<String, dynamic>;
            final orderId = data['orderId']?.toString() ?? '';
            final status = data['status']?.toString() ?? '';

            if (orderId.isNotEmpty && status.isNotEmpty) {
              await updateOrderStatusLocally(orderId: orderId, newStatus: status);
              return {
                'statusCode': 200,
                'data': {'success': true, 'orderId': orderId, 'status': status},
              };
            } else {
              return {
                'statusCode': 400,
                'data': {'error': 'Missing orderId or status'},
              };
            }
          } catch (e) {
            return {
              'statusCode': 500,
              'data': {'error': e.toString()},
            };
          }
        }

        return {
          'statusCode': 404,
          'data': {'error': 'Not found'},
        };
      },
    );

    if (ok) {
      _isServerRunning = true;
      // Start UDP Beacon broadcast
      await BridgePlatform.instance.startUdpBeacon(
        port: kUdpBeaconPort,
        message: 'NUSANTARA_POS_MASTER|$kBridgePort|$storeName',
      );
      notifyListeners();
    }
    return ok;
  }

  /// Generates self-contained, responsive HTML customer tracker view for local LAN clients
  Map<String, dynamic> _generateCustomerTrackerHtml(String uriPath) {
    try {
      final uri = Uri.parse('http://localhost$uriPath');
      final orderId = uri.queryParameters['order'] ?? '';
      final token = uri.queryParameters['token'] ?? '';

      final cleanOrderId = orderId.trim().toLowerCase();
      PosTransaction? order;
      try {
        order = _localOrders.firstWhere(
          (t) => t.receiptId.trim().toLowerCase() == cleanOrderId || t.id.trim().toLowerCase() == cleanOrderId,
        );
      } catch (_) {
        order = null;
      }

      if (order == null) throw Exception('Order not found');

      if (token.isNotEmpty && order.trackingToken.isNotEmpty && token != order.trackingToken) {
        return {
          'statusCode': 403,
          'contentType': 'text/html',
          'data': _buildAccessDeniedHtml(),
        };
      }

      final isCompleted = order.kitchenStatus == 'completed';
      final isReady = order.kitchenStatus == 'ready';
      final isCooking = order.kitchenStatus == 'cooking' || order.kitchenStatus == 'preparing';

      final stageTitle = isCompleted ? 'Order Completed' : (isReady ? '🔔 READY FOR PICKUP!' : '🔥 COOKING NOW');
      final stageColor = isCompleted ? '#64748B' : (isReady ? '#15803D' : '#D97706');
      final stageBadgeBg = isCompleted ? '#F1F5F9' : (isReady ? '#DCFCE7' : '#FEF3C7');
      final stageDesc = isCompleted
          ? 'Your order has been handed over. This tracking session is now closed.'
          : (isReady
              ? 'Your order is ready! Please proceed to the pickup counter to collect your meal.'
              : 'Your order is being freshly prepared and cooked by our chefs.');

      final itemsHtml = order.items.map((item) {
        final notes = item.notes.isNotEmpty ? '<div style="color:#B45309;font-size:12px;margin-top:2px;">* ${item.notes}</div>' : '';
        return '''
        <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #E2E8F0;">
          <div>
            <span style="font-weight:bold;color:#1E3A8A;">${item.quantity}x</span> 
            <span style="color:#0F172A;font-weight:600;">${item.menuItem.name}</span>
            $notes
          </div>
        </div>
        ''';
      }).join('');

      final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Order Tracker - Nusantara Hybrid POS</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #F8FAFC; margin: 0; padding: 16px; color: #0F172A; }
    .card { background: white; max-width: 440px; margin: 0 auto; border-radius: 18px; box-shadow: 0 4px 20px rgba(30,58,138,0.08); border: 1px solid #E2E8F0; overflow: hidden; }
    .header { background: #1E3A8A; color: white; padding: 20px; text-align: center; }
    .queue-badge { display: inline-block; background: #F59E0B; color: #1E3A8A; font-size: 26px; font-weight: 900; padding: 6px 20px; border-radius: 30px; margin-top: 10px; }
    .content { padding: 20px; }
    .stage-card { background: $stageBadgeBg; border: 1.5px solid $stageColor; border-radius: 14px; padding: 16px; text-align: center; margin-bottom: 20px; }
    .stage-title { font-size: 18px; font-weight: 900; color: $stageColor; }
    .stage-desc { font-size: 12.5px; color: #334155; margin-top: 6px; line-height: 1.4; }
    .items-title { font-size: 14px; font-weight: 800; color: #1E3A8A; margin-bottom: 10px; }
    .footer { text-align: center; font-size: 11px; color: #94A3B8; padding: 14px; }
    .pulse { animation: pulse-animation 1.5s infinite; }
    @keyframes pulse-animation { 0% { opacity: 0.6; } 50% { opacity: 1; } 100% { opacity: 0.6; } }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div style="font-size:12px;letter-spacing:1px;font-weight:700;color:#FDE68A;">NUSANTARA HYBRID POS (OFFLINE LAN TRACKER)</div>
      <div class="queue-badge">${order.queueNumber}</div>
      <div style="font-size:12px;margin-top:6px;font-weight:600;">[ ${order.orderMode.toUpperCase()} ]</div>
    </div>
    <div class="content">
      <div class="stage-card">
        <div class="stage-title ${isCooking ? 'pulse' : ''}">$stageTitle</div>
        <div class="stage-desc">$stageDesc</div>
      </div>
      <div class="items-title">Order Items:</div>
      <div style="margin-bottom:16px;">
        $itemsHtml
      </div>
    </div>
    <div class="footer">
      Automatically updated in real time via Floor 1 Cashier Wi-Fi Network.<br>
      Order ID: ${order.receiptId}
    </div>
  </div>
  <script>
    setInterval(async () => {
      try {
        const res = await fetch('/orders');
        if (res.ok) {
          const list = await res.json();
          const found = list.find(o => o.id === '${order.receiptId}' || o.receiptId === '${order.receiptId}');
          if (found && found.kitchenStatus !== '${order.kitchenStatus}') {
            window.location.reload();
          }
        }
      } catch (e) {}
    }, 2000);
  </script>
</body>
</html>
      ''';

      return {
        'statusCode': 200,
        'contentType': 'text/html',
        'data': html,
      };
    } catch (_) {
      return {
        'statusCode': 404,
        'contentType': 'text/html',
        'data': '<h2 style="font-family:sans-serif;text-align:center;margin-top:40px;color:#1E3A8A;">Order Not Found on Master Cashier</h2>',
      };
    }
  }

  String _buildAccessDeniedHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Access Denied</title>
</head>
<body style="font-family:sans-serif;text-align:center;padding:40px;background:#F8FAFC;">
  <div style="max-width:400px;margin:0 auto;background:white;padding:24px;border-radius:16px;border:1px solid #CBD5E1;">
    <h3 style="color:#DC2626;">Access Denied / Invalid QR Token</h3>
    <p style="font-size:13px;color:#64748B;">This tracking page is locked for customer privacy. Please scan the official QR code on your cashier receipt.</p>
  </div>
</body>
</html>
    ''';
  }

  /// Stop Embedded HTTP Server & Beacon
  Future<void> stopMasterServer() async {
    BridgePlatform.instance.stopUdpBeacon();
    _isServerRunning = false;
    notifyListeners();
  }

  /// Registers a newly created transaction into local memory and offline storage
  Future<void> registerLocalOrder(PosTransaction tx) async {
    final idx = _localOrders.indexWhere((t) => t.receiptId == tx.receiptId || t.id == tx.id);
    if (idx >= 0) {
      _localOrders[idx] = tx;
    } else {
      _localOrders.insert(0, tx);
    }
    await _saveOfflineTransactions();
    notifyListeners();
  }

  /// Updates status of an order locally and syncs to Firestore if online
  Future<void> updateOrderStatusLocally({
    required String orderId,
    required String newStatus,
  }) async {
    final idx = _localOrders.indexWhere((t) => t.id == orderId || t.receiptId == orderId);
    if (idx >= 0) {
      final current = _localOrders[idx];
      _localOrders[idx] = current.copyWith(
        kitchenStatus: newStatus,
        readyAt: newStatus == 'ready' ? DateTime.now() : current.readyAt,
      );
      await _saveOfflineTransactions();
      notifyListeners();
    }

    if (ConnectivityService().isOnline) {
      try {
        await FirestoreService().updateKitchenStatus(orderId, newStatus);
      } catch (_) {}
    }
  }

  /// Updates and persists customer WhatsApp number on an existing local order.
  Future<void> updateOrderCustomerPhone(String orderId, String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    final idx = _localOrders.indexWhere(
      (t) => t.id == orderId || t.receiptId == orderId,
    );
    if (idx != -1) {
      _localOrders[idx] = _localOrders[idx].copyWith(customerPhone: clean);
      await _saveOfflineTransactions();
      notifyListeners();
    }
  }

  /// Reloads tenant-scoped local orders when user logs in or switches store account
  Future<void> reloadForTenant() async {
    _localOrders.clear();
    await _loadOfflineTransactions();
    notifyListeners();
  }

  /// Save offline transactions to SharedPreferences (tenant-scoped)
  Future<void> _saveOfflineTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _localOrders.map((t) => t.toMap()).toList();
      await prefs.setString(EmailAuthService.scopedKey(_kOfflineTransactionsKey), jsonEncode(list));
    } catch (_) {}
  }

  /// Load offline transactions from SharedPreferences (tenant-scoped)
  Future<void> _loadOfflineTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(EmailAuthService.scopedKey(_kOfflineTransactionsKey));
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _localOrders.clear();
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          _localOrders.add(PosTransaction.fromMap(map, map['id']?.toString() ?? ''));
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Zero-Config Auto-Discovery: Listens on UDP port 8766 for Master Beacon
  /// and falls back to subnet sweep if beacon is delayed or filtered.
  Future<void> startAutoDiscovery() async {
    if (kIsWeb) return;

    // 1. Listen for UDP beacon first
    await BridgePlatform.instance.listenUdpBeacon(
      port: kUdpBeaconPort,
      onMasterFound: (masterIp, masterPort, storeName) async {
        if (_discoveredMasterIp != masterIp) {
          _discoveredMasterIp = masterIp;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kMasterIpKey, masterIp);
          notifyListeners();
          startOfflineOrderPolling();
        }
      },
    );

    // 2. Set fallback timer: if no UDP beacon received after 3.5s, run sweep
    _fallbackDiscoveryTimer?.cancel();
    _fallbackDiscoveryTimer = Timer(const Duration(milliseconds: 3500), () async {
      if (_discoveredMasterIp.isEmpty) {
        await scanAndDiscoverMasterCashier();
      }
    });
  }

  /// Floor 2 Kitchen Discovery: Scans local Wi-Fi subnet for Master Cashier port 8765
  Future<String?> scanAndDiscoverMasterCashier() async {
    if (kIsWeb) return null;
    _isScanning = true;
    notifyListeners();

    try {
      final foundIp = await BridgePlatform.instance.scanMaster(kBridgePort);
      if (foundIp != null) {
        _discoveredMasterIp = foundIp;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kMasterIpKey, foundIp);
        startOfflineOrderPolling();
        _isScanning = false;
        notifyListeners();
        return foundIp;
      }
    } catch (e) {
      debugPrint('[LocalKitchenBridge] Discovery error: $e');
    }

    _isScanning = false;
    notifyListeners();
    return null;
  }

  /// Start polling orders from Floor 1 Master when running offline
  void startOfflineOrderPolling() {
    _offlinePollTimer?.cancel();
    if (_discoveredMasterIp.isEmpty || kIsWeb) return;

    _offlinePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await fetchOrdersFromMaster();
    });
  }

  void stopOfflineOrderPolling() {
    _offlinePollTimer?.cancel();
    _offlinePollTimer = null;
    _fallbackDiscoveryTimer?.cancel();
    _fallbackDiscoveryTimer = null;
    BridgePlatform.instance.stopListeningUdpBeacon();
  }

  /// Fetch orders from Floor 1 Master via HTTP
  Future<void> fetchOrdersFromMaster() async {
    if (_discoveredMasterIp.isEmpty || kIsWeb) return;

    try {
      final list = await BridgePlatform.instance.getOrders(ip: _discoveredMasterIp, port: kBridgePort);
      if (list != null && list.isNotEmpty) {
        final List<PosTransaction> fetched = [];
        for (final map in list) {
          fetched.add(PosTransaction.fromMap(map, map['id']?.toString() ?? ''));
        }
        if (fetched.isNotEmpty) {
          final Map<String, PosTransaction> merged = {for (var t in _localOrders) t.id: t};
          for (final t in fetched) {
            merged[t.id] = t;
          }
          _localOrders.clear();
          _localOrders.addAll(merged.values);
          _localOrders.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          await _saveOfflineTransactions();
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Post status update to Master from Floor 2 Kitchen Tablet
  Future<bool> sendStatusUpdateToMaster({
    required String orderId,
    required String status,
  }) async {
    await updateOrderStatusLocally(orderId: orderId, newStatus: status);

    if (_discoveredMasterIp.isEmpty || kIsWeb) return false;

    try {
      return await BridgePlatform.instance.postStatus(
        ip: _discoveredMasterIp,
        port: kBridgePort,
        orderId: orderId,
        newStatus: status,
      );
    } catch (e) {
      debugPrint('[LocalKitchenBridge] Send status error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    stopOfflineOrderPolling();
    super.dispose();
  }
}
