import 'dart:math' as math;
import 'order_item.dart';
import 'menu_item.dart';
import '../firebase_options.dart';
import '../services/email_auth_service.dart';

class PosTransaction {
  final String id;
  final DateTime timestamp;
  final List<OrderItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final double serviceAmount;
  final String paymentMethod; // 'Cash', 'QRIS', 'Card'
  final double cashReceived;
  final double changeAmount;
  final String aiSource; // 'ON_DEVICE', 'IN_CLOUD', 'MANUAL'
  final String cashierName;
  final String shiftLabel;
  final String shiftHours;
  final String queueNumber;
  final String orderMode;
  final String orderNotes;
  final String customerPhone;
  final String customerName;
  final bool isOffline;
  final String kitchenStatus; // 'preparing', 'cooking', 'ready', 'completed'
  final int estimatedPrepMinutes;
  final String trackingToken; // 16-char secret token for single-customer isolation
  final DateTime? readyAt; // Timestamp when marked ready (auto-locks after 15 mins)

  PosTransaction({
    required this.id,
    required this.timestamp,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.serviceAmount = 0.0,
    required this.paymentMethod,
    required this.cashReceived,
    required this.changeAmount,
    this.aiSource = 'MANUAL',
    this.cashierName = 'Nurmiyaty',
    this.shiftLabel = 'Morning Shift',
    this.shiftHours = '07:00 - 15:00',
    this.queueNumber = '#001',
    this.orderMode = 'Dine In',
    this.orderNotes = '',
    this.customerPhone = '',
    this.customerName = 'Pelanggan',
    this.isOffline = false,
    this.kitchenStatus = 'preparing',
    this.estimatedPrepMinutes = 10,
    String? trackingToken,
    this.readyAt,
  }) : trackingToken = (trackingToken != null && trackingToken.isNotEmpty)
            ? trackingToken
            : generateTrackingToken();

  String get receiptId => id;

  /// Builds deep link tracking URL for customers
  String get trackerUrl => buildTrackerUrl();

  /// Builds tracking URL: if offline and [localIp] is provided, points to local HTTP master server on port 8765
  String buildTrackerUrl({bool isOffline = false, String? localIp}) {
    final cleanQueue = queueNumber.replaceAll('#', '');
    final tid = EmailAuthService().tenantId;
    if (isOffline && localIp != null && localIp.isNotEmpty) {
      return 'http://$localIp:8765/track?order=$id&tenant=$tid&token=$trackingToken&queue=$cleanQueue&eta=$estimatedPrepMinutes';
    }
    try {
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      return 'https://$projectId.web.app/?trackOrder=$id&tenant=$tid&token=$trackingToken&queue=$cleanQueue&eta=$estimatedPrepMinutes';
    } catch (_) {
      return 'https://nusantara-hybrid-pos.web.app/?trackOrder=$id&tenant=$tid&token=$trackingToken&queue=$cleanQueue&eta=$estimatedPrepMinutes';
    }
  }

  /// Generates a cryptographically secure 16-character alphanumeric tracking token
  static String generateTrackingToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random.secure();
    return List.generate(16, (i) => chars[rnd.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'items': items.map((i) => i.toMap()).toList(),
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'serviceAmount': serviceAmount,
      'paymentMethod': paymentMethod,
      'cashReceived': cashReceived,
      'changeAmount': changeAmount,
      'aiSource': aiSource,
      'cashierName': cashierName,
      'shiftLabel': shiftLabel,
      'shiftHours': shiftHours,
      'queueNumber': queueNumber,
      'orderMode': orderMode,
      'orderNotes': orderNotes,
      'customerPhone': customerPhone,
      'customerName': customerName,
      'isOffline': isOffline,
      'kitchenStatus': kitchenStatus,
      'estimatedPrepMinutes': estimatedPrepMinutes,
      'trackingToken': trackingToken,
      'readyAt': readyAt?.toIso8601String(),
    };
  }

  factory PosTransaction.fromMap(Map<String, dynamic> map, String docId) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    final parsedItems = rawItems.map((raw) {
      if (raw is Map<String, dynamic>) {
        final category = raw['category']?.toString() ?? 'Minuman';
        final menuItemName = raw['menuItemName']?.toString() ?? raw['name']?.toString() ?? 'Menu Item';
        final menuItemId = raw['menuItemId']?.toString() ?? raw['id']?.toString() ?? '';
        final unitPrice = (raw['unitPrice'] as num?)?.toDouble() ?? (raw['price'] as num?)?.toDouble() ?? 0.0;
        final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
        final notes = raw['notes']?.toString() ?? '';
        final item = MenuItem(
          id: menuItemId,
          name: menuItemName,
          category: category,
          price: unitPrice,
          description: '',
        );
        return OrderItem(menuItem: item, quantity: qty, notes: notes);
      }
      return null;
    }).whereType<OrderItem>().toList();

    return PosTransaction(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      items: parsedItems,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      serviceAmount: (map['serviceAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['paymentMethod'] ?? 'Cash',
      cashReceived: (map['cashReceived'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (map['changeAmount'] as num?)?.toDouble() ?? 0.0,
      aiSource: map['aiSource'] ?? 'MANUAL',
      cashierName: map['cashierName']?.toString() ?? 'Nurmiyaty',
      shiftLabel: map['shiftLabel']?.toString() ?? 'Morning Shift',
      shiftHours: map['shiftHours']?.toString() ?? '07:00 - 15:00',
      queueNumber: map['queueNumber']?.toString() ?? '#001',
      orderMode: map['orderMode']?.toString() ?? 'Dine In',
      orderNotes: map['orderNotes']?.toString() ?? '',
      customerPhone: map['customerPhone']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? 'Customer',
      isOffline: map['isOffline'] == true,
      kitchenStatus: map['kitchenStatus']?.toString() ?? 'preparing',
      estimatedPrepMinutes: (map['estimatedPrepMinutes'] as num?)?.toInt() ??
          (parsedItems.fold<int>(0, (sum, it) => sum + it.quantity) * 3 + 4).clamp(5, 30),
      trackingToken: map['trackingToken']?.toString() ?? '',
      readyAt: map['readyAt'] != null ? DateTime.tryParse(map['readyAt'].toString()) : null,
    );
  }

  PosTransaction copyWith({
    String? id,
    DateTime? timestamp,
    List<OrderItem>? items,
    double? subtotal,
    double? tax,
    double? total,
    double? serviceAmount,
    String? paymentMethod,
    double? cashReceived,
    double? changeAmount,
    String? aiSource,
    String? cashierName,
    String? shiftLabel,
    String? shiftHours,
    String? queueNumber,
    String? orderMode,
    String? orderNotes,
    String? customerPhone,
    String? customerName,
    bool? isOffline,
    String? kitchenStatus,
    int? estimatedPrepMinutes,
    String? trackingToken,
    DateTime? readyAt,
  }) {
    return PosTransaction(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      serviceAmount: serviceAmount ?? this.serviceAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cashReceived: cashReceived ?? this.cashReceived,
      changeAmount: changeAmount ?? this.changeAmount,
      aiSource: aiSource ?? this.aiSource,
      cashierName: cashierName ?? this.cashierName,
      shiftLabel: shiftLabel ?? this.shiftLabel,
      shiftHours: shiftHours ?? this.shiftHours,
      queueNumber: queueNumber ?? this.queueNumber,
      orderMode: orderMode ?? this.orderMode,
      orderNotes: orderNotes ?? this.orderNotes,
      customerPhone: customerPhone ?? this.customerPhone,
      customerName: customerName ?? this.customerName,
      isOffline: isOffline ?? this.isOffline,
      kitchenStatus: kitchenStatus ?? this.kitchenStatus,
      estimatedPrepMinutes: estimatedPrepMinutes ?? this.estimatedPrepMinutes,
      trackingToken: trackingToken ?? this.trackingToken,
      readyAt: readyAt ?? this.readyAt,
    );
  }
}
