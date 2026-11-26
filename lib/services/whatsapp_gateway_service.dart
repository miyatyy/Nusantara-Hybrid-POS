import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr/qr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import 'connectivity_service.dart';
import 'customer_directory_service.dart';
import 'email_auth_service.dart';

enum WhatsAppProvider {
  fonnte,
  wabaOfficial,
}

class FonntePairingResult {
  final bool success;
  final Uint8List? qrImageBytes;
  final String? pairingCode;
  final String message;
  final bool alreadyConnected;

  const FonntePairingResult({
    required this.success,
    this.qrImageBytes,
    this.pairingCode,
    required this.message,
    this.alreadyConnected = false,
  });
}

class FonnteDeviceStatus {
  final bool success;
  final bool isConnected;
  final String deviceNumber;
  final String deviceName;
  final String message;

  const FonnteDeviceStatus({
    required this.success,
    required this.isConnected,
    this.deviceNumber = '',
    this.deviceName = '',
    required this.message,
  });
}

class WhatsAppMessagePayload {
  final String id;
  final String targetPhone;
  final String messageText;
  final String type; // 'ORDER_CONFIRMATION', 'ORDER_READY', 'PROMO_BLAST'
  final DateTime createdAt;

  const WhatsAppMessagePayload({
    required this.id,
    required this.targetPhone,
    required this.messageText,
    required this.type,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'targetPhone': targetPhone,
        'messageText': messageText,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WhatsAppMessagePayload.fromMap(Map<String, dynamic> map) {
    return WhatsAppMessagePayload(
      id: map['id']?.toString() ?? '',
      targetPhone: map['targetPhone']?.toString() ?? '',
      messageText: map['messageText']?.toString() ?? '',
      type: map['type']?.toString() ?? 'GENERIC',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Dual WhatsApp Gateway Service for Nusantara Hybrid POS.
/// Supports:
/// 1. Provider A: Fonnte (https://api.fonnte.com/send) for easy testing/hackathon demos.
/// 2. Provider B: Meta WABA Official (https://graph.facebook.com/v21.0/{phoneNumberId}/messages)
/// 3. Offline Outbox: Queues messages locally during internet blackouts and auto-drains upon reconnect.
/// 4. CRM: Records customer loyalty data to Firestore `customers/{phone}`.
class WhatsAppGatewayService extends ChangeNotifier {
  static final WhatsAppGatewayService _instance = WhatsAppGatewayService._internal();
  factory WhatsAppGatewayService() => _instance;
  WhatsAppGatewayService._internal();

  static const String _kWaProvider = 'settings_wa_provider';
  static const String _kFonnteToken = 'settings_wa_fonnte_token';
  static const String _kWabaToken = 'settings_wa_waba_token';
  static const String _kWabaPhoneId = 'settings_wa_waba_phone_id';
  static const String _kAutoSendReceipt = 'settings_wa_auto_send_receipt';
  static const String _kAutoSendReady = 'settings_wa_auto_send_ready';
  static const String _kOfflineWaOutbox = 'offline_wa_outbox_json';

  WhatsAppProvider _provider = WhatsAppProvider.fonnte;
  String _fonnteToken = const String.fromEnvironment('FONNTE_TOKEN', defaultValue: '');
  String _wabaToken = const String.fromEnvironment('WABA_ACCESS_TOKEN', defaultValue: '');
  String _wabaPhoneId = const String.fromEnvironment('WABA_PHONE_ID', defaultValue: '');
  bool _autoSendReceipt = true;
  bool _autoSendReady = true;
  String _lastError = '';

  final List<WhatsAppMessagePayload> _outbox = [];

  WhatsAppProvider get provider => _provider;
  String get fonnteToken => _fonnteToken;
  String get wabaToken => _wabaToken;
  String get wabaPhoneId => _wabaPhoneId;
  bool get autoSendReceipt => _autoSendReceipt;
  bool get autoSendReady => _autoSendReady;
  String get lastError => _lastError;
  bool get hasConfiguredGateway =>
      (_provider == WhatsAppProvider.wabaOfficial && _wabaToken.isNotEmpty && _wabaPhoneId.isNotEmpty) ||
      (_provider == WhatsAppProvider.fonnte && _fonnteToken.isNotEmpty);
  List<WhatsAppMessagePayload> get outbox => List.unmodifiable(_outbox);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pStr = prefs.getString(_kWaProvider) ?? 'fonnte';
      _provider = pStr == 'waba' ? WhatsAppProvider.wabaOfficial : WhatsAppProvider.fonnte;
      _fonnteToken = prefs.getString(_kFonnteToken) ?? _fonnteToken;
      _wabaToken = prefs.getString(_kWabaToken) ?? '';
      _wabaPhoneId = prefs.getString(_kWabaPhoneId) ?? '';
      _autoSendReceipt = prefs.getBool(_kAutoSendReceipt) ?? true;
      _autoSendReady = prefs.getBool(_kAutoSendReady) ?? true;

      // Load pending outbox
      final rawOutbox = prefs.getString(_kOfflineWaOutbox);
      if (rawOutbox != null && rawOutbox.isNotEmpty) {
        final List<dynamic> list = jsonDecode(rawOutbox);
        _outbox.clear();
        for (final item in list) {
          _outbox.add(WhatsAppMessagePayload.fromMap(item as Map<String, dynamic>));
        }
      }
      notifyListeners();

      // Listen to connectivity to auto-drain outbox
      ConnectivityService().isOnlineNotifier.addListener(() {
        if (ConnectivityService().isOnline) {
          drainOutbox();
        }
      });
    } catch (e) {
      debugPrint('[WhatsAppGatewayService] init error: $e');
    }
  }

  Future<void> saveSettings({
    required WhatsAppProvider provider,
    required String fonnteToken,
    required String wabaToken,
    required String wabaPhoneId,
    required bool autoSendReceipt,
    required bool autoSendReady,
  }) async {
    _provider = provider;
    _fonnteToken = fonnteToken.trim();
    _wabaToken = wabaToken.trim();
    _wabaPhoneId = wabaPhoneId.trim();
    _autoSendReceipt = autoSendReceipt;
    _autoSendReady = autoSendReady;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kWaProvider, provider == WhatsAppProvider.wabaOfficial ? 'waba' : 'fonnte');
      await prefs.setString(_kFonnteToken, _fonnteToken);
      await prefs.setString(_kWabaToken, _wabaToken);
      await prefs.setString(_kWabaPhoneId, _wabaPhoneId);
      await prefs.setBool(_kAutoSendReceipt, _autoSendReceipt);
      await prefs.setBool(_kAutoSendReady, _autoSendReady);
    } catch (_) {}
  }

  /// Normalizes Indonesian phone numbers into standard international format (e.g. 0812345678 -> 62812345678)
  static String formatPhoneNumber(String rawPhone) {
    String clean = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('0')) {
      clean = '62${clean.substring(1)}';
    } else if (clean.startsWith('8')) {
      clean = '62$clean';
    }
    return clean;
  }

  /// Builds a scannable QR Code image URL for the order tracker
  static String buildQrImageUrl(String trackerUrl) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=360x360&data=${Uri.encodeComponent(trackerUrl)}';
  }

  /// Generates crisp high-contrast PNG bytes of the Order Tracker QR Code for direct WhatsApp sharing
  static Future<Uint8List?> generateQrPngBytes(String data, {int size = 420}) async {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final double totalSize = size.toDouble();
      const double padding = 32.0;
      final double qrSize = totalSize - (padding * 2);

      // Pure white background with quiet zone
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalSize, totalSize),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      final modulePaint = Paint()
        ..color = const Color(0xFF0F172A)
        ..isAntiAlias = false
        ..style = PaintingStyle.fill;

      final moduleCount = qrImage.moduleCount;
      final pixelSize = qrSize / moduleCount;

      for (int r = 0; r < moduleCount; r++) {
        for (int c = 0; c < moduleCount; c++) {
          if (qrImage.isDark(r, c)) {
            canvas.drawRect(
              Rect.fromLTWH(
                padding + (c * pixelSize),
                padding + (r * pixelSize),
                pixelSize + 0.5,
                pixelSize + 0.5,
              ),
              modulePaint,
            );
          }
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(size, size);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[WhatsAppGatewayService] QR PNG generation error: $e');
      return null;
    }
  }

  static String buildOrderConfirmationMessage({
    required PosTransaction order,
    required String storeName,
    String customerName = 'Customer',
  }) {
    final isTakeAway = order.orderMode.toUpperCase().contains('TAKE') ||
        order.orderMode.toUpperCase().contains('BUNGKUS');
    final modeLabel = isTakeAway ? 'Take Away' : 'Dine In';

    final itemsSummary = order.items.isNotEmpty
        ? order.items
            .map((i) => '• ${i.quantity}x ${i.menuItem.name}${i.notes.isNotEmpty ? ' (${i.notes})' : ''}')
            .join('\n')
        : '• POS Order (${order.receiptId})';

    final trackerUrl = order.trackerUrl;
    final statusBadge = order.kitchenStatus == 'ready'
        ? '🔔 READY FOR PICKUP AT COUNTER!'
        : (order.kitchenStatus == 'cooking'
            ? '🍳 COOKING IN KITCHEN'
            : '⏳ PREPARING IN KITCHEN');

    return '''
Hello $customerName, thank you for ordering at *$storeName*!

*QUEUE NUMBER: ${order.queueNumber}*
Kitchen Status: $statusBadge
Order Type: $modeLabel
Receipt ID: ${order.receiptId}

*Order Details:*
$itemsSummary

*Total Bill:* Rp ${order.total.toStringAsFixed(0)} (${order.paymentMethod})

📱 *TRACK COOKING PROGRESS & PICKUP ALERT:*
Click the link or scan the QR image above to track your order in real time:
$trackerUrl

We will notify you as soon as your meal is ready. Thank you for waiting! 😊
''';
  }

  static String buildOrderCookingMessage({
    required PosTransaction order,
    required String storeName,
    String customerName = 'Customer',
  }) {
    final itemsSummary = order.items.isNotEmpty
        ? '\n*Your Order:*\n${order.items.map((i) => '• ${i.quantity}x ${i.menuItem.name}').join('\n')}\n'
        : '';

    return '''
🍳 *YOUR ORDER IS BEING COOKED!* 🍳

Hello $customerName, your order at *$storeName* is now being prepared by our chef!

*QUEUE NUMBER: ${order.queueNumber}*
Type: ${order.orderMode}
$itemsSummary
Estimated ready time: ~${order.estimatedPrepMinutes} min. We will automatically send a WhatsApp alert as soon as your order is ready for pickup! 😊
''';
  }

  static String buildOrderReadyMessage({
    required PosTransaction order,
    required String storeName,
    String customerName = 'Customer',
  }) {
    final itemsSummary = order.items.isNotEmpty
        ? '\n*Order Items:*\n${order.items.map((i) => '• ${i.quantity}x ${i.menuItem.name}').join('\n')}\n'
        : '';

    return '''
🔔 *ORDER READY FOR PICKUP!* 🔔

Hello $customerName, your order at *$storeName* is freshly prepared and ready!

*QUEUE NUMBER: ${order.queueNumber}*
Type: ${order.orderMode}
$itemsSummary
Please proceed to the pickup counter and simply show or mention your *Queue Number ${order.queueNumber}* to our staff. Enjoy your meal! 🍽️
''';
  }

  /// Opens WhatsApp directly on the device to the customer's number.
  /// For order confirmation, attaches the QR Code PNG + Live Tracker link.
  /// For "Siap Diambil" ready alarm, sends a clean text-only notification with the Queue Number (no QR image).
  Future<bool> openDirectWhatsAppWithQr({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    String customerName = 'Pelanggan',
    bool isReadyAlarm = false,
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 9) return false;

    final message = isReadyAlarm
        ? buildOrderReadyMessage(order: order, storeName: storeName, customerName: customerName)
        : buildOrderConfirmationMessage(order: order, storeName: storeName, customerName: customerName);

    final qrBytes = isReadyAlarm ? null : await generateQrPngBytes(order.trackerUrl);

    if (!kIsWeb) {
      try {
        const channel = MethodChannel('com.miya.nusantara_hybrid_pos/thermal_printer');
        final res = await channel.invokeMethod<bool>('openWhatsAppWithQr', {
          'phone': cleanPhone,
          'message': message,
          'qrPngBytes': qrBytes,
        });
        return res == true;
      } catch (e) {
        debugPrint('[WhatsAppGatewayService] openDirectWhatsAppWithQr error: $e');
      }
    }
    return false;
  }

  /// Sends Order Confirmation receipt & live tracker link + QR image to Customer via WhatsApp Gateway
  Future<bool> sendOrderConfirmation({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    String customerName = 'Pelanggan',
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 10) return false;

    // Save/update customer loyalty record in Firestore
    _saveCustomerProfile(cleanPhone, customerName, order.total);

    final message = buildOrderConfirmationMessage(
      order: order,
      storeName: storeName,
      customerName: customerName,
    );

    return sendMessage(
      targetPhone: cleanPhone,
      messageText: message,
      type: 'ORDER_CONFIRMATION',
      imageUrl: buildQrImageUrl(order.trackerUrl),
    );
  }

  /// Sends "Pesanan Siap Diambil" notification (Queue Number only, no QR image) to the buyer
  Future<bool> sendOrderReadyAlert({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    String customerName = 'Pelanggan',
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 10) return false;

    final message = buildOrderReadyMessage(
      order: order,
      storeName: storeName,
      customerName: customerName,
    );

    return sendMessage(
      targetPhone: cleanPhone,
      messageText: message,
      type: 'ORDER_READY',
    );
  }

  /// Sends "Pesanan Sedang Dimasak" automated alert via Fonnte/Gateway
  Future<bool> sendOrderCookingAlert({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    String customerName = 'Pelanggan',
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 10) return false;

    final message = buildOrderCookingMessage(
      order: order,
      storeName: storeName,
      customerName: customerName,
    );

    return sendMessage(
      targetPhone: cleanPhone,
      messageText: message,
      type: 'ORDER_COOKING',
    );
  }

  /// Sends automated background WhatsApp alarm via Fonnte from Kitchen Kanban (NO manual WA opening).
  /// Supports `cooking` (Cooking) and `ready` (Ready for Pickup) per queue number.
  Future<String> dispatchKitchenStatusViaFonnte({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    required String status, // 'cooking' or 'ready'
    String customerName = 'Customer',
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 9) return 'INVALID_PHONE';

    final isCooking = status == 'cooking';
    final message = isCooking
        ? buildOrderCookingMessage(order: order, storeName: storeName, customerName: customerName)
        : buildOrderReadyMessage(order: order, storeName: storeName, customerName: customerName);

    final type = isCooking ? 'ORDER_COOKING' : 'ORDER_READY';

    if (!hasConfiguredGateway) {
      await _queueMessage(WhatsAppMessagePayload(
        id: 'wa_${DateTime.now().millisecondsSinceEpoch}',
        targetPhone: cleanPhone,
        messageText: message,
        type: type,
        createdAt: DateTime.now(),
      ));
      return 'QUEUED_NO_TOKEN';
    }

    // Attempt direct live API delivery first (even if ConnectivityService is stale),
    // and fall back to offline outbox only if the network request fails.
    bool ok = false;
    try {
      if (_provider == WhatsAppProvider.wabaOfficial && _wabaToken.isNotEmpty && _wabaPhoneId.isNotEmpty) {
        ok = await _sendViaWaba(cleanPhone, message);
      } else {
        ok = await _sendViaFonnte(cleanPhone, message);
      }
    } catch (e) {
      _lastError = e.toString();
      ok = false;
    }

    if (!ok) {
      await _queueMessage(WhatsAppMessagePayload(
        id: 'wa_${DateTime.now().millisecondsSinceEpoch}',
        targetPhone: cleanPhone,
        messageText: message,
        type: type,
        createdAt: DateTime.now(),
      ));
    }

    try {
      EmailAuthService.tenantCollection('wa_logs').add({
        'phone': cleanPhone,
        'queueNumber': order.queueNumber,
        'orderId': order.id,
        'status': status,
        'sent': ok,
        'error': ok ? '' : _lastError,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    return ok ? 'SENT_FONNTE' : 'QUEUED_RETRY';
  }

  /// Automatically dispatches real-time "Pesanan Siap Diambil" WhatsApp notification:
  /// 1. If Fonnte/WABA API is configured, sends silently in the background via API.
  /// 2. If API is not configured or fails, automatically opens direct WhatsApp + QR PNG to the customer's number.
  Future<String> dispatchOrderReadyNotification({
    required String customerPhone,
    required PosTransaction order,
    required String storeName,
    String customerName = 'Pelanggan',
  }) async {
    final cleanPhone = formatPhoneNumber(customerPhone);
    if (cleanPhone.length < 9) return 'INVALID_PHONE';

    if (hasConfiguredGateway) {
      final apiOk = await sendOrderReadyAlert(
        customerPhone: cleanPhone,
        order: order,
        storeName: storeName,
        customerName: customerName,
      );
      if (apiOk) return 'SENT_API';
    }

    final directOk = await openDirectWhatsAppWithQr(
      customerPhone: cleanPhone,
      order: order,
      storeName: storeName,
      customerName: customerName,
      isReadyAlarm: true,
    );
    return directOk ? 'OPENED_WA' : 'FAILED';
  }

  /// Triggers a native Android heads-up system notification (status bar + sound + vibration)
  static Future<void> triggerLocalReadyNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    try {
      const channel = MethodChannel('com.miya.nusantara_hybrid_pos/thermal_printer');
      await channel.invokeMethod('showOrderReadyNotification', {
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('[WhatsAppGatewayService] Local notification error: $e');
    }
  }

  /// Sends message via configured provider or queues in offline outbox
  Future<bool> sendMessage({
    required String targetPhone,
    required String messageText,
    String type = 'GENERIC',
    String? imageUrl,
  }) async {
    final isOnline = ConnectivityService().isOnline;

    if (!isOnline) {
      // Queue offline
      await _queueMessage(WhatsAppMessagePayload(
        id: 'wa_${DateTime.now().millisecondsSinceEpoch}',
        targetPhone: targetPhone,
        messageText: messageText,
        type: type,
        createdAt: DateTime.now(),
      ));
      return true;
    }

    try {
      if (_provider == WhatsAppProvider.wabaOfficial && _wabaToken.isNotEmpty && _wabaPhoneId.isNotEmpty) {
        return await _sendViaWaba(targetPhone, messageText);
      } else {
        return await _sendViaFonnte(targetPhone, messageText, imageUrl: imageUrl);
      }
    } catch (e) {
      debugPrint('[WhatsAppGatewayService] Send failed, queuing to offline outbox: $e');
      await _queueMessage(WhatsAppMessagePayload(
        id: 'wa_${DateTime.now().millisecondsSinceEpoch}',
        targetPhone: targetPhone,
        messageText: messageText,
        type: type,
        createdAt: DateTime.now(),
      ));
      return false;
    }
  }

  Future<bool> _sendViaFonnte(String phone, String message, {String? imageUrl}) async {
    final url = Uri.parse('https://api.fonnte.com/send');
    final body = <String, String>{
      'target': phone,
      'message': message,
    };
    if (imageUrl != null && imageUrl.isNotEmpty) {
      body['url'] = imageUrl;
    }

    final response = await http.post(
      url,
      headers: {
        'Authorization': _fonnteToken,
      },
      body: body,
    ).timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['status'] == true) {
          _lastError = '';
          debugPrint('[WhatsAppGatewayService] Sent via Fonnte successfully to $phone');
          return true;
        }
        _lastError = decoded['reason']?.toString() ?? response.body;
        debugPrint('[WhatsAppGatewayService] Fonnte rejected: $_lastError');
        return false;
      } catch (_) {
        _lastError = '';
        return true;
      }
    } else {
      _lastError = 'HTTP ${response.statusCode}: ${response.body}';
      debugPrint('[WhatsAppGatewayService] Fonnte error: $_lastError');
      return false;
    }
  }

  Future<bool> _sendViaWaba(String phone, String message) async {
    final url = Uri.parse('https://graph.facebook.com/v21.0/$_wabaPhoneId/messages');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_wabaToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messaging_product': 'whatsapp',
        'to': phone,
        'type': 'text',
        'text': {'body': message},
      }),
    ).timeout(const Duration(seconds: 6));

    if (response.statusCode == 200 || response.statusCode == 201) {
      debugPrint('[WhatsAppGatewayService] Sent via Meta WABA successfully to $phone');
      return true;
    } else {
      debugPrint('[WhatsAppGatewayService] WABA error: ${response.statusCode} ${response.body}');
      return false;
    }
  }

  Future<void> _queueMessage(WhatsAppMessagePayload payload) async {
    _outbox.add(payload);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _outbox.map((p) => p.toMap()).toList();
      await prefs.setString(_kOfflineWaOutbox, jsonEncode(list));
    } catch (_) {}
  }

  /// Drains offline queue upon reconnect
  Future<void> drainOutbox() async {
    if (_outbox.isEmpty || !ConnectivityService().isOnline) return;

    final toSend = List<WhatsAppMessagePayload>.from(_outbox);
    for (final item in toSend) {
      bool sent = false;
      try {
        if (_provider == WhatsAppProvider.wabaOfficial && _wabaToken.isNotEmpty) {
          sent = await _sendViaWaba(item.targetPhone, item.messageText);
        } else {
          sent = await _sendViaFonnte(item.targetPhone, item.messageText);
        }
      } catch (_) {}

      if (sent) {
        _outbox.removeWhere((p) => p.id == item.id);
      }
    }

    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _outbox.map((p) => p.toMap()).toList();
      await prefs.setString(_kOfflineWaOutbox, jsonEncode(list));
    } catch (_) {}
  }

  /// Record/Update Customer locally first AND mirror to tenant-isolated Firestore `tenants/{tenantId}/customers/{phone}`
  void _saveCustomerProfile(String cleanPhone, String name, double orderTotal) {
    CustomerDirectoryService().recordCustomerOrder(
      phone: cleanPhone,
      name: name,
      orderTotal: orderTotal,
    );
  }

  /// Checks Fonnte device connection status via `POST https://api.fonnte.com/device`.
  Future<FonnteDeviceStatus> getFonnteDeviceStatus() async {
    if (_fonnteToken.isEmpty) {
      return const FonnteDeviceStatus(
        success: false,
        isConnected: false,
        message: 'Please enter and save a valid Fonnte Device Token first.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.fonnte.com/device'),
            headers: {'Authorization': _fonnteToken},
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final statusOk = data['status'] == true;
      final deviceStatus = (data['device_status'] ?? data['status_device'] ?? '')
          .toString()
          .toLowerCase();
      final isConnected = deviceStatus == 'connect' ||
          deviceStatus == 'connected' ||
          data['connected'] == true;
      final deviceNum = (data['device'] ?? data['number'] ?? '').toString();
      final deviceName = (data['name'] ?? '').toString();

      if (statusOk) {
        return FonnteDeviceStatus(
          success: true,
          isConnected: isConnected,
          deviceNumber: deviceNum,
          deviceName: deviceName,
          message: isConnected
              ? 'Connected${deviceNum.isNotEmpty ? " ($deviceNum)" : ""}'
              : 'Disconnected — scan QR or use Pairing Code below',
        );
      }
      return FonnteDeviceStatus(
        success: false,
        isConnected: false,
        message: data['reason']?.toString() ?? 'Failed to fetch Fonnte device status.',
      );
    } catch (e) {
      return FonnteDeviceStatus(
        success: false,
        isConnected: false,
        message: 'Connection error: $e',
      );
    }
  }

  /// Requests a Fonnte QR code (`type: 'qr'`) or 8-digit pairing code (`type: 'code'`)
  /// via `POST https://api.fonnte.com/qr`.
  Future<FonntePairingResult> requestFonntePairing({
    required String type,
    String whatsapp = '',
  }) async {
    if (_fonnteToken.isEmpty) {
      return const FonntePairingResult(
        success: false,
        message: 'Please enter and save a valid Fonnte Device Token first.',
      );
    }

    final cleanPhone = whatsapp.trim().isNotEmpty ? formatPhoneNumber(whatsapp) : '';
    if (type == 'code' && cleanPhone.length < 9) {
      return const FonntePairingResult(
        success: false,
        message: 'Enter a valid WhatsApp number (e.g. 0812xxx or 62812xxx) to generate a Pairing Code.',
      );
    }

    try {
      final body = <String, String>{'type': type};
      if (cleanPhone.isNotEmpty) {
        body['whatsapp'] = cleanPhone;
      }

      final response = await http
          .post(
            Uri.parse('https://api.fonnte.com/qr'),
            headers: {'Authorization': _fonnteToken},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reason = (data['reason'] ?? '').toString();
      final reasonLower = reason.toLowerCase();

      if (reasonLower.contains('already connect') || reasonLower.contains('connected')) {
        return const FonntePairingResult(
          success: true,
          alreadyConnected: true,
          message: 'WhatsApp device is already connected on Fonnte!',
        );
      }

      final qrBase64 = (data['url'] ?? '').toString().trim();
      if (qrBase64.isNotEmpty) {
        final cleaned = qrBase64.contains(',') ? qrBase64.split(',').last : qrBase64;
        final bytes = base64Decode(cleaned);
        return FonntePairingResult(
          success: true,
          qrImageBytes: bytes,
          message: 'Scan this QR code in WhatsApp -> Linked Devices -> Link a Device.',
        );
      }

      final code = (data['code'] ?? '').toString().trim();
      if (code.isNotEmpty) {
        return FonntePairingResult(
          success: true,
          pairingCode: code,
          message: 'Enter this pairing code in WhatsApp -> Linked Devices -> Link with phone number.',
        );
      }

      return FonntePairingResult(
        success: false,
        message: reason.isNotEmpty ? reason : 'Unable to generate Fonnte QR / Pairing Code.',
      );
    } catch (e) {
      return FonntePairingResult(
        success: false,
        message: 'Failed to contact Fonnte API: $e',
      );
    }
  }

  /// Disconnects the currently paired Fonnte WhatsApp session (`POST https://api.fonnte.com/disconnect`).
  Future<bool> disconnectFonnteDevice() async {
    if (_fonnteToken.isEmpty) {
      return false;
    }
    try {
      final response = await http
          .post(
            Uri.parse('https://api.fonnte.com/disconnect'),
            headers: {'Authorization': _fonnteToken},
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['status'] == true;
    } catch (_) {
      return false;
    }
  }
}
