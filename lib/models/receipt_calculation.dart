import 'dart:math';
import 'package:intl/intl.dart';
import 'order_item.dart';
import 'transaction_model.dart';
import '../firebase_options.dart';
import '../services/email_auth_service.dart';

class ReceiptCalculation {
  final List<OrderItem> items;
  final double taxPercent;
  final double servicePercent;
  final int subtotal;
  final int taxAmount;
  final int serviceAmount;
  final int grandTotal;
  final int amountPaid;
  final int changeAmount;
  final String paymentMethod;
  final String orderMode; // 'Dine In' vs 'Take Away'
  final String orderNotes;
  final DateTime timestamp;
  final String cashierName;
  final String shiftLabel;
  final String shiftHours;
  final String queueNumber; // Sequential daily queue number, e.g. '#001'
  final String trackingToken; // 16-character secret tracking token
  final String customerPhone;
  final String customerName;

  ReceiptCalculation({
    required this.items,
    required this.taxPercent,
    required this.servicePercent,
    required this.subtotal,
    required this.taxAmount,
    required this.serviceAmount,
    required this.grandTotal,
    required this.amountPaid,
    required this.changeAmount,
    required this.paymentMethod,
    required this.orderMode,
    required this.orderNotes,
    required this.timestamp,
    this.cashierName = 'Nurmiyaty',
    this.shiftLabel = 'Morning Shift',
    this.shiftHours = '07:00 - 15:00',
    this.queueNumber = '#001',
    this.customerPhone = '',
    this.customerName = 'Pelanggan',
    String? trackingToken,
  }) : trackingToken = (trackingToken != null && trackingToken.isNotEmpty)
            ? trackingToken
            : PosTransaction.generateTrackingToken();

  /// Constructs the isolated single-customer tracking URL with secret token and tenant isolation
  String buildTrackerUrl(String orderId, {bool isOffline = false, String? localIp}) {
    final q = queueNumber.replaceAll('#', '');
    final tid = EmailAuthService().tenantId;
    if (isOffline && localIp != null && localIp.isNotEmpty) {
      return 'http://$localIp:8765/track?order=$orderId&tenant=$tid&token=$trackingToken&queue=$q&eta=10';
    }
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return 'https://$projectId.web.app/?trackOrder=$orderId&tenant=$tid&token=$trackingToken&queue=$q&eta=10';
  }

  bool get isPaidSufficient => amountPaid >= grandTotal;
  int get shortage => max(0, grandTotal - amountPaid);

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  String formatCurrency(num amount) => _currencyFormatter.format(amount);
  static String formatRupiah(num amount) => _currencyFormatter.format(amount);

  String get formattedSubtotal => _currencyFormatter.format(subtotal);
  String get formattedTax => _currencyFormatter.format(taxAmount);
  String get formattedTaxAmount => _currencyFormatter.format(taxAmount);
  String get formattedService => _currencyFormatter.format(serviceAmount);
  String get formattedServiceAmount => _currencyFormatter.format(serviceAmount);
  String get formattedGrandTotal => _currencyFormatter.format(grandTotal);
  String get formattedAmountPaid => _currencyFormatter.format(amountPaid);
  String get formattedChange => _currencyFormatter.format(changeAmount);

  /// Factory constructor that computes all values strictly using integer Rupiah rounding (.round())
  /// so floating-point errors (e.g. 0.0000000000001) never occur.
  factory ReceiptCalculation.compute({
    required List<OrderItem> items,
    required double taxPercent,
    required double servicePercent,
    String? rawAmountPaidText,
    String? rawCashInput,
    String paymentMethod = 'Cash',
    String orderMode = 'Dine In',
    String orderNotes = '',
    String cashierName = 'Nurmiyaty',
    String shiftLabel = 'Morning Shift',
    String shiftHours = '07:00 - 15:00',
    String queueNumber = '#001',
    String customerPhone = '',
    String customerName = 'Pelanggan',
    String? trackingToken,
    DateTime? timestamp,
  }) {
    // 1. subtotal: exact sum of item.price * item.quantity rounded cleanly to Rupiah
    final int subtotal = items.fold<int>(
      0,
      (sum, item) => sum + (item.menuItem.price * item.quantity).round(),
    );

    // 2. taxAmount: (subtotal * (taxPercent / 100)).round()
    final int taxAmount = (subtotal * (taxPercent / 100.0)).round();

    // 3. serviceAmount: (subtotal * (servicePercent / 100)).round()
    final int serviceAmount = (subtotal * (servicePercent / 100.0)).round();

    // 4. grandTotal: subtotal + taxAmount + serviceAmount
    final int grandTotal = subtotal + taxAmount + serviceAmount;

    // 5. amountPaid: parse digits safely for Cash, or grandTotal for QRIS / Card
    int amountPaid;
    final isCash = paymentMethod == 'Cash' ||
        paymentMethod.startsWith('Tunai') ||
        paymentMethod.contains('Cash');

    final cashText = rawCashInput ?? rawAmountPaidText ?? '';

    if (isCash) {
      amountPaid = parseCashInput(cashText);
    } else {
      amountPaid = grandTotal;
    }

    // 6. changeAmount: strictly max(0, amountPaid - grandTotal) when amountPaid >= grandTotal
    final int changeAmount = (amountPaid >= grandTotal) ? (amountPaid - grandTotal) : 0;

    return ReceiptCalculation(
      items: List.unmodifiable(items),
      taxPercent: taxPercent,
      servicePercent: servicePercent,
      subtotal: subtotal,
      taxAmount: taxAmount,
      serviceAmount: serviceAmount,
      grandTotal: grandTotal,
      amountPaid: amountPaid,
      changeAmount: changeAmount,
      paymentMethod: paymentMethod,
      orderMode: orderMode,
      orderNotes: orderNotes,
      cashierName: cashierName,
      shiftLabel: shiftLabel,
      shiftHours: shiftHours,
      queueNumber: queueNumber,
      customerPhone: customerPhone,
      customerName: customerName,
      trackingToken: trackingToken ?? PosTransaction.generateTrackingToken(),
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Safe Rupiah text parser: strips "Rp", spaces, handles decimals with shorthand ("1.5jt", "2,5k", "50rb"),
  /// and strips thousand separator dots/commas ("100.000" -> 100000).
  static int parseCashInput(String input) {
    if (input.trim().isEmpty) return 0;
    String clean = input.trim().toLowerCase().replaceAll('rp', '').replaceAll(' ', '');

    // Handle "jt" / "juta" (million) with decimal support (e.g. 1.5jt or 1,5jt)
    if (clean.endsWith('jt') || clean.endsWith('juta')) {
      final numStr = clean
          .replaceAll('juta', '')
          .replaceAll('jt', '')
          .replaceAll(',', '.');
      final val = double.tryParse(numStr) ?? 0.0;
      return (val * 1000000).round();
    }

    // Handle "k" or "rb" / "ribu" (thousand) with decimal support (e.g. 2.5k or 50rb)
    if (clean.endsWith('k') || clean.endsWith('rb') || clean.endsWith('ribu')) {
      final numStr = clean
          .replaceAll('ribu', '')
          .replaceAll('rb', '')
          .replaceAll('k', '')
          .replaceAll(',', '.');
      final val = double.tryParse(numStr) ?? 0.0;
      return (val * 1000).round();
    }

    // Standard raw number with thousand separators (e.g. 100.000 or 100,000)
    clean = clean.replaceAll('.', '').replaceAll(',', '');
    return int.tryParse(clean) ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((i) => i.toMap()).toList(),
      'taxPercent': taxPercent,
      'servicePercent': servicePercent,
      'subtotal': subtotal,
      'taxAmount': taxAmount,
      'serviceAmount': serviceAmount,
      'grandTotal': grandTotal,
      'amountPaid': amountPaid,
      'changeAmount': changeAmount,
      'paymentMethod': paymentMethod,
      'orderMode': orderMode,
      'orderNotes': orderNotes,
      'cashierName': cashierName,
      'shiftLabel': shiftLabel,
      'shiftHours': shiftHours,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
