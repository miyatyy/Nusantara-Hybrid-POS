import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/order_item.dart';
import 'settings_service.dart';

class MidtransSnapResponse {
  final String orderId;
  final String token;
  final String redirectUrl;
  final bool isSimulated;
  final String? errorMessage;
  final String? qrString;

  const MidtransSnapResponse({
    required this.orderId,
    required this.token,
    required this.redirectUrl,
    this.isSimulated = false,
    this.errorMessage,
    this.qrString,
  });
}

class MidtransService {
  static final MidtransService _instance = MidtransService._internal();
  factory MidtransService() => _instance;
  MidtransService._internal();

  // Read compile-time environment variable first: --dart-define=MIDTRANS_SERVER_KEY=SB-Mid-server-xxxx
  static const String _envServerKey = String.fromEnvironment(
    'MIDTRANS_SERVER_KEY',
    defaultValue: '',
  );

  /// Effective Server Key: Priority = Settings (local override) -> Env Flag -> Empty
  String get activeServerKey {
    final local = SettingsService().effectiveMidtransServerKey;
    if (local.isNotEmpty) return local;
    return _envServerKey;
  }

  bool get isConfigured => activeServerKey.trim().isNotEmpty;

  /// Creates a Midtrans Snap transaction via Sandbox API using built-in HttpClient
  Future<MidtransSnapResponse> createSnapTransaction({
    required String orderId,
    required double grossAmount,
    required List<OrderItem> items,
  }) async {
    final key = activeServerKey;

    // If no server key configured, use seamless Sandbox simulation for offline/local testing
    if (key.isEmpty) {
      debugPrint('[Midtrans] Server key not configured. Using Sandbox Simulation Mode.');
      return MidtransSnapResponse(
        orderId: orderId,
        token: 'snap-token-sandbox-$orderId',
        redirectUrl: 'https://app.sandbox.midtrans.com/snap/v2/vtweb/mock-$orderId',
        isSimulated: true,
        qrString: '00020101021226600016ID.CO.MIDTRANS.WWW01189360099887766554430214$orderId'
            '52045812530336054${grossAmount.round()}5802ID5919NUSANTARA POS CAFE6009YOGYAKARTA6304ABCD',
      );
    }

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse('https://app.sandbox.midtrans.com/snap/v1/transactions');
      final request = await client.postUrl(uri);

      // Midtrans Basic Auth requires ServerKey + ':' base64 encoded
      final basicAuth = base64Encode(utf8.encode('$key:'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicAuth');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final itemDetails = items.map((it) {
        final rawName = it.menuItem.name;
        final truncatedName = rawName.length > 50 ? rawName.substring(0, 50) : rawName;
        return {
          'id': it.menuItem.id,
          'price': it.menuItem.price.round(),
          'quantity': it.quantity,
          'name': truncatedName,
        };
      }).toList();

      final payload = {
        'transaction_details': {
          'order_id': orderId,
          'gross_amount': grossAmount.round(),
        },
        'item_details': itemDetails,
        'enabled_payments': [
          'qris',
          'gopay',
          'shopeepay',
          'bca_va',
          'credit_card',
        ],
        'expiry': {
          'unit': 'minutes',
          'duration': SettingsService().qrisExpiryMinutes,
        },
      };

      final payloadBytes = utf8.encode(jsonEncode(payload));
      request.contentLength = payloadBytes.length;
      request.add(payloadBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final token = json['token'] as String? ?? 'snap-token-$orderId';
        final redirectUrl = json['redirect_url'] as String? ?? '';
        debugPrint('[Midtrans] Live Snap Token generated: $token');
        return MidtransSnapResponse(
          orderId: orderId,
          token: token,
          redirectUrl: redirectUrl,
          isSimulated: false,
          qrString: '00020101021226600016ID.CO.MIDTRANS.WWW01189360099887766554430214$orderId'
              '52045812530336054${grossAmount.round()}5802ID5919NUSANTARA POS CAFE6009YOGYAKARTA6304ABCD',
        );
      } else {
        debugPrint('[Midtrans] Snap API returned status ${response.statusCode}: $responseBody');
        return MidtransSnapResponse(
          orderId: orderId,
          token: 'snap-token-fallback-$orderId',
          redirectUrl: 'https://app.sandbox.midtrans.com/snap/v2/vtweb/fallback-$orderId',
          isSimulated: true,
          errorMessage: 'Midtrans API error (${response.statusCode}): $responseBody',
          qrString: '00020101021226600016ID.CO.MIDTRANS.WWW01189360099887766554430214$orderId'
              '52045812530336054${grossAmount.round()}5802ID5919NUSANTARA POS CAFE6009YOGYAKARTA6304ABCD',
        );
      }
    } catch (e) {
      debugPrint('[Midtrans] Network exception during Snap create: $e');
      return MidtransSnapResponse(
        orderId: orderId,
        token: 'snap-token-sim-$orderId',
        redirectUrl: 'https://app.sandbox.midtrans.com/snap/v2/vtweb/sim-$orderId',
        isSimulated: true,
        errorMessage: 'Network exception: $e',
        qrString: '00020101021226600016ID.CO.MIDTRANS.WWW01189360099887766554430214$orderId'
            '52045812530336054${grossAmount.round()}5802ID5919NUSANTARA POS CAFE6009YOGYAKARTA6304ABCD',
      );
    } finally {
      client?.close();
    }
  }

  /// Checks transaction status of an order from Midtrans Sandbox v2 API
  Future<Map<String, dynamic>> checkTransactionStatus(String orderId) async {
    final key = activeServerKey;
    if (key.isEmpty) {
      return {
        'status_code': '200',
        'transaction_status': 'settlement',
        'fraud_status': 'accept',
        'order_id': orderId,
        'payment_type': 'qris',
        'is_simulated': true,
      };
    }

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse('https://api.sandbox.midtrans.com/v2/$orderId/status');
      final request = await client.getUrl(uri);

      final basicAuth = base64Encode(utf8.encode('$key:'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicAuth');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      } else {
        return {
          'status_code': '${response.statusCode}',
          'transaction_status': 'pending',
          'message': responseBody,
        };
      }
    } catch (e) {
      return {
        'status_code': '500',
        'transaction_status': 'unknown',
        'error': e.toString(),
      };
    } finally {
      client?.close();
    }
  }
}
