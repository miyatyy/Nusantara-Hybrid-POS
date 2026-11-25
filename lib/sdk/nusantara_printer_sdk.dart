import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_printer_helper.dart';
import '../models/receipt_calculation.dart';
import '../models/cashier_shift.dart';
import '../models/transaction_model.dart';

class DiscoveredNetworkPrinter {
  final String ip;
  final int port;
  final String name;
  final int latencyMs;

  const DiscoveredNetworkPrinter({
    required this.ip,
    this.port = 9100,
    this.name = 'Kitchen ESC/POS Wi-Fi Printer',
    this.latencyMs = 0,
  });

  int get pingMs => latencyMs;
}

class BluetoothPrinterDevice {
  final String name;
  final String address;

  const BluetoothPrinterDevice({
    required this.name,
    required this.address,
  });

  factory BluetoothPrinterDevice.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothPrinterDevice(
      name: map['name']?.toString() ?? 'Unknown Printer',
      address: map['address']?.toString() ?? '',
    );
  }
}

class EscPosBuilder {
  final List<int> _bytes = [];
  final int paperWidthMm;

  EscPosBuilder({this.paperWidthMm = 58});

  int get maxColumns => paperWidthMm == 80 ? 48 : 32;

  List<int> get bytes => List.unmodifiable(_bytes);

  /// Sanitizes text for standard ASCII ESC/POS thermal printers.
  /// Replaces Unicode punctuation with safe ASCII equivalents first, then strips
  /// any non-ASCII characters (codeUnit > 126, such as emojis) using [RegExp].
  static String sanitizeForEscPos(String input) {
    if (input.isEmpty) return '';

    String cleaned = input
        .replaceAll('•', '-')
        .replaceAll('\u2022', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");

    // Strip any remaining non-ASCII characters (e.g., emojis > 126 or non-printable chars)
    cleaned = cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    return cleaned;
  }

  void init() {
    _bytes.addAll([0x1B, 0x40]); // ESC @
  }

  void alignLeft() {
    _bytes.addAll([0x1B, 0x61, 0x00]); // ESC a 0
  }

  void alignCenter() {
    _bytes.addAll([0x1B, 0x61, 0x01]); // ESC a 1
  }

  void alignRight() {
    _bytes.addAll([0x1B, 0x61, 0x02]); // ESC a 2
  }

  void setBold(bool enable) {
    _bytes.addAll([0x1B, 0x45, enable ? 0x01 : 0x00]); // ESC E
  }

  void setDoubleSize(bool enable) {
    _bytes.addAll([0x1D, 0x21, enable ? 0x11 : 0x00]); // GS !
  }

  void text(String rawText) {
    final sanitized = sanitizeForEscPos(rawText);
    try {
      _bytes.addAll(ascii.encode(sanitized));
    } catch (_) {
      // Fallback safe byte encoding
      for (final codeUnit in sanitized.codeUnits) {
        if (codeUnit >= 0x20 && codeUnit <= 0x7E) {
          _bytes.add(codeUnit);
        }
      }
    }
  }

  void textLn(String rawText) {
    text(rawText);
    _bytes.add(0x0A); // LF
  }

  void lineFeed([int lines = 1]) {
    for (int i = 0; i < lines; i++) {
      _bytes.add(0x0A);
    }
  }

  void divider([String char = '-']) {
    final cleanChar = char.isEmpty ? '-' : char.substring(0, 1);
    final line = cleanChar * maxColumns;
    textLn(line);
  }

  void row(String left, String right) {
    final cleanLeft = sanitizeForEscPos(left);
    final cleanRight = sanitizeForEscPos(right);

    final totalWidth = maxColumns;
    final rightWidth = cleanRight.length;
    final leftWidth = totalWidth - rightWidth - 1;

    String leftPart = cleanLeft;
    if (leftPart.length > leftWidth && leftWidth > 0) {
      leftPart = leftPart.substring(0, leftWidth);
    }

    final spaceCount = totalWidth - (leftPart.length + cleanRight.length);
    final spaces = ' ' * (spaceCount > 0 ? spaceCount : 1);
    textLn('$leftPart$spaces$cleanRight');
  }

  void cutPaper() {
    lineFeed(3);
    _bytes.addAll([0x1D, 0x56, 0x41, 0x03]); // GS V A 3 (feed and partial cut)
  }

  /// Prints standard ESC/POS QR Code using GS ( k command sequences
  void qrCode(String data, {int moduleSize = 7}) {
    if (data.isEmpty) return;
    final dataBytes = utf8.encode(data);
    final len = dataBytes.length + 3;
    final pL = len % 256;
    final pH = len ~/ 256;

    // 1. Select Model 2: GS ( k 4 0 49 65 50 0
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // 2. Set Module Size: GS ( k 3 0 49 67 n (1-16)
    final clampedSize = moduleSize.clamp(1, 16);
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, clampedSize]);

    // 3. Error Correction Level M (15%): GS ( k 3 0 49 69 49
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

    // 4. Store Data: GS ( k pL pH 49 80 48 data
    _bytes.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    _bytes.addAll(dataBytes);

    // 5. Print Symbol: GS ( k 3 0 49 81 48
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    _bytes.add(0x0A); // LF
  }
}

class NusantaraPrinterSDK extends ChangeNotifier {
  static final NusantaraPrinterSDK _instance = NusantaraPrinterSDK._internal();
  factory NusantaraPrinterSDK() => _instance;
  NusantaraPrinterSDK._internal();

  static const MethodChannel _channel = MethodChannel('com.miya.nusantara_hybrid_pos/thermal_printer');

  static const String _kSelectedPrinterName = 'printer_selected_name';
  static const String _kSelectedPrinterAddress = 'printer_selected_address';
  static const String _kPaperWidthMm = 'printer_paper_width_mm';
  static const String _kKitchenPrinterIp = 'printer_kitchen_ip';
  static const String _kKitchenPrinterPort = 'printer_kitchen_port';
  static const String _kKitchenAutoPrint = 'printer_kitchen_auto_print';
  static const String _kPrintedKitchenOrderIds = 'printed_kitchen_order_ids';

  String _selectedPrinterName = '';
  String _selectedPrinterAddress = '';
  int _paperWidthMm = 58; // 58 or 80
  String _kitchenPrinterIp = '';
  int _kitchenPrinterPort = 9100;
  bool _kitchenAutoPrintEnabled = true;

  String get selectedPrinterName => _selectedPrinterName;
  String get selectedPrinterAddress => _selectedPrinterAddress;
  int get paperWidthMm => _paperWidthMm;
  bool get hasPrinterSelected => _selectedPrinterAddress.isNotEmpty;

  String get kitchenPrinterIp => _kitchenPrinterIp;
  String get kitchenWifiPrinterIp => _kitchenPrinterIp;
  int get kitchenPrinterPort => _kitchenPrinterPort;
  bool get kitchenAutoPrintEnabled => _kitchenAutoPrintEnabled;
  bool get hasKitchenPrinterSelected => _kitchenPrinterIp.trim().isNotEmpty;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedPrinterName = prefs.getString(_kSelectedPrinterName) ?? '';
      _selectedPrinterAddress = prefs.getString(_kSelectedPrinterAddress) ?? '';
      _paperWidthMm = prefs.getInt(_kPaperWidthMm) ?? 58;
      _kitchenPrinterIp = prefs.getString(_kKitchenPrinterIp) ?? '';
      _kitchenPrinterPort = prefs.getInt(_kKitchenPrinterPort) ?? 9100;
      _kitchenAutoPrintEnabled = prefs.getBool(_kKitchenAutoPrint) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveKitchenPrinterConfig({
    required String ip,
    int port = 9100,
    bool autoPrint = true,
  }) async {
    _kitchenPrinterIp = ip.trim();
    _kitchenPrinterPort = port;
    _kitchenAutoPrintEnabled = autoPrint;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKitchenPrinterIp, _kitchenPrinterIp);
      await prefs.setInt(_kKitchenPrinterPort, _kitchenPrinterPort);
      await prefs.setBool(_kKitchenAutoPrint, _kitchenAutoPrintEnabled);
    } catch (_) {}
  }

  Future<void> saveKitchenWifiPrinter({
    required String ip,
    bool autoPrint = true,
  }) async {
    await saveKitchenPrinterConfig(ip: ip, autoPrint: autoPrint);
  }

  Future<void> clearPrintedKitchenOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrintedKitchenOrderIds);
    } catch (_) {}
  }

  Future<bool> checkAndRequestPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkAndRequestPermissions');
      return res ?? false;
    } catch (e) {
      debugPrint('[NusantaraPrinterSDK] Perm error: $e');
      return false;
    }
  }

  Future<List<BluetoothPrinterDevice>> getPairedPrinters() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('getPairedDevices');
      if (res == null) return [];
      final rawDevices = res.map((d) => BluetoothPrinterDevice.fromMap(d as Map)).toList();

      final List<BluetoothPrinterDevice> list = [];
      for (final dev in rawDevices) {
        if (dev.name.endsWith('_LE') || dev.name.endsWith(' LE') || dev.name.contains('_LE_')) {
          list.add(BluetoothPrinterDevice(
            name: '${dev.name} (Use non-LE Classic device)',
            address: dev.address,
          ));
        } else {
          list.add(dev);
        }
      }
      return list;
    } catch (e) {
      debugPrint('[NusantaraPrinterSDK] getPairedDevices error: $e');
      return [];
    }
  }

  Future<void> saveSelectedPrinter({
    required String name,
    required String address,
    required int paperWidthMm,
  }) async {
    _selectedPrinterName = name;
    _selectedPrinterAddress = address;
    _paperWidthMm = paperWidthMm;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelectedPrinterName, name);
      await prefs.setString(_kSelectedPrinterAddress, address);
      await prefs.setInt(_kPaperWidthMm, paperWidthMm);
    } catch (_) {}
  }

  /// Builds ESC/POS binary commands for full receipt
  List<int> buildReceiptBytes({
    required ReceiptCalculation calculation,
    required String storeName,
    required String storeTagline,
    required String storeAddress,
    required String storePhone,
    required String receiptFooter,
    required String orderId,
    bool isOffline = false,
    String? localIp,
  }) {
    final builder = EscPosBuilder(paperWidthMm: _paperWidthMm);
    builder.init();

    // 1. Store Header
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn(storeName.toUpperCase());
    builder.setDoubleSize(false);

    if (storeTagline.isNotEmpty) {
      builder.setBold(false);
      builder.textLn(storeTagline);
    }
    if (storeAddress.isNotEmpty) {
      builder.textLn(storeAddress);
    }
    if (storePhone.isNotEmpty) {
      builder.textLn('Telp: $storePhone');
    }

    builder.divider('=');

    // 2. Sequential Queue Number & Order Mode (High Contrast & Double Size)
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn('QUEUE: ${calculation.queueNumber}');
    builder.setDoubleSize(false);
    final isTakeAway = calculation.orderMode.toUpperCase().contains('TAKE') ||
        calculation.orderMode.toUpperCase().contains('BUNGKUS');
    builder.textLn(isTakeAway ? 'TAKE AWAY (BUNGKUS)' : 'MAKAN DI TEMPAT (DINE IN)');
    builder.setBold(false);
    builder.divider('=');

    // 3. Metadata
    builder.alignLeft();
    builder.row('Order ID:', orderId);
    builder.row('Date    :', calculation.timestamp.toString().substring(0, 16));
    builder.row('Cashier :', calculation.cashierName);
    builder.row('Shift   :', '${calculation.shiftLabel} (${calculation.shiftHours})');
    builder.row('Type    :', calculation.orderMode);
    builder.row(
      'Status  :',
      isOffline ? 'OFFLINE (Stock Deducted)' : 'ONLINE (Cloud Synced)',
    );

    builder.divider('-');

    // 3. Line Items
    for (final item in calculation.items) {
      final left = '${item.quantity}x ${item.menuItem.name}';
      final right = calculation.formatCurrency(item.totalPrice);
      builder.row(left, right);
      if (item.notes.isNotEmpty) {
        builder.textLn('   Note: ${item.notes}');
      }
    }

    builder.divider('-');

    // 4. Totals Breakdown
    builder.row('Subtotal:', calculation.formattedSubtotal);
    if (calculation.serviceAmount > 0) {
      builder.row(
        'Service (${calculation.servicePercent.toStringAsFixed(0)}%):',
        calculation.formattedService,
      );
    }
    builder.row(
      'Tax (${calculation.taxPercent.toStringAsFixed(0)}%):',
      calculation.formattedTax,
    );

    builder.divider('-');

    // 5. Grand Total (Bold)
    builder.setBold(true);
    builder.row('GRAND TOTAL:', calculation.formattedGrandTotal);
    builder.setBold(false);

    // 6. Payment & Change
    builder.row('Payment      :', calculation.paymentMethod);
    if (calculation.paymentMethod.contains('Cash') || calculation.paymentMethod.contains('Tunai')) {
      builder.row('Cash Paid    :', calculation.formattedAmountPaid);
      builder.setBold(true);
      builder.row('CHANGE       :', calculation.formattedChange);
      builder.setBold(false);
    }

    builder.divider('=');

    // 7. Footer
    builder.alignCenter();
    builder.textLn(receiptFooter);
    builder.textLn('Nusantara Hybrid POS - #BuildHybridAI');
    builder.textLn('*** PAID - STOCK DEDUCTED ***');

    // 7b. Prominent Live Kitchen Order Tracking QR Code
    final trackerUrl = calculation.buildTrackerUrl(orderId, isOffline: isOffline, localIp: localIp);
    builder.lineFeed(1);
    builder.alignCenter();
    builder.setBold(true);
    builder.textLn('SCAN QR: LIVE STATUS & ORDER ALARM');
    builder.setBold(false);
    builder.qrCode(trackerUrl, moduleSize: _paperWidthMm == 80 ? 8 : 6);
    builder.textLn('Track Live Kitchen & Ready Alerts');

    // 8. Feed & Cut
    builder.cutPaper();

    return builder.bytes;
  }

  /// Sends ESC/POS byte commands directly to the paired Bluetooth printer via SPP RFCOMM
  Future<bool> printTransactionReceipt({
    required ReceiptCalculation calculation,
    required String storeName,
    required String storeTagline,
    required String storeAddress,
    required String storePhone,
    required String receiptFooter,
    required String orderId,
    bool isOffline = false,
    String? localIp,
  }) async {
    if (!hasPrinterSelected || _selectedPrinterAddress.isEmpty) {
      throw Exception(
        'Belum ada printer Bluetooth yang dipilih. Silakan pilih printer thermal non-LE Classic di menu Pengaturan (Store & POS Settings).',
      );
    }

    final bytes = buildReceiptBytes(
      calculation: calculation,
      storeName: storeName,
      storeTagline: storeTagline,
      storeAddress: storeAddress,
      storePhone: storePhone,
      receiptFooter: receiptFooter,
      orderId: orderId,
      isOffline: isOffline,
      localIp: localIp,
    );

    try {
      final res = await _channel.invokeMethod<bool>('printBytes', {
        'address': _selectedPrinterAddress,
        'bytes': Uint8List.fromList(bytes),
      });

      if (res != true) {
        throw Exception(
          'Printer Bluetooth tidak merespons pengiriman data. Pastikan printer dalam keadaan ON dan gunakan profil Classic SPP (bukan _LE).',
        );
      }
      return true;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal mencetak struk Bluetooth (${e.code}).');
    }
  }

  /// Sends a test receipt to verify connection and paper width
  Future<bool> printTestReceipt({required String storeName}) async {
    if (!hasPrinterSelected || _selectedPrinterAddress.isEmpty) {
      throw Exception(
        'Pilih printer Bluetooth non-LE Classic terlebih dahulu di Pengaturan.',
      );
    }

    final builder = EscPosBuilder(paperWidthMm: _paperWidthMm);
    builder.init();
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn(storeName.toUpperCase());
    builder.setDoubleSize(false);
    builder.textLn('BLUETOOTH ESC/POS TEST PAGE');
    builder.divider('=');
    builder.alignLeft();
    builder.row('Paper Width :', '$_paperWidthMm mm');
    builder.row('Max Columns :', '${builder.maxColumns} chars');
    builder.row('SDK Engine  :', 'Native Kotlin SPP');
    builder.row('Status      :', 'CONNECTED OK');
    builder.divider('-');
    builder.alignCenter();
    builder.textLn('12345678901234567890123456789012');
    builder.textLn('Testing ESC/POS Native Driver');
    builder.cutPaper();

    try {
      final res = await _channel.invokeMethod<bool>('printBytes', {
        'address': _selectedPrinterAddress,
        'bytes': Uint8List.fromList(builder.bytes),
      });

      if (res != true) {
        throw Exception(
          'Printer Bluetooth tidak merespons test print. Pastikan printer dalam keadaan ON dan gunakan profil non-LE Classic.',
        );
      }
      return true;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal mencetak test print (${e.code}).');
    }
  }

  /// Generates a plain-text ESC/POS simulation for judges to preview in UI
  String generateEscPosTextPreview({
    required ReceiptCalculation calculation,
    required String storeName,
    required String storeTagline,
    required String storeAddress,
    required String storePhone,
    required String receiptFooter,
    required String orderId,
    bool isOffline = false,
    String? localIp,
  }) {
    final width = _paperWidthMm == 80 ? 48 : 32;
    final buffer = StringBuffer();

    String center(String text) {
      if (text.length >= width) return text.substring(0, width);
      final pad = (width - text.length) ~/ 2;
      return ' ' * pad + text;
    }

    String row(String left, String right) {
      final space = width - left.length - right.length;
      if (space <= 0) return '$left $right';
      return '$left${' ' * space}$right';
    }

    buffer.writeln(center(storeName.toUpperCase()));
    if (storeTagline.isNotEmpty) buffer.writeln(center(storeTagline));
    if (storeAddress.isNotEmpty) buffer.writeln(center(storeAddress));
    if (storePhone.isNotEmpty) buffer.writeln(center('Telp: $storePhone'));
    buffer.writeln('=' * width);
    buffer.writeln(center('QUEUE: ${calculation.queueNumber}'));
    final isTakeAway = calculation.orderMode.toUpperCase().contains('TAKE') ||
        calculation.orderMode.toUpperCase().contains('BUNGKUS');
    buffer.writeln(center(isTakeAway ? 'TAKE AWAY' : 'DINE IN'));
    buffer.writeln('=' * width);
    buffer.writeln(row('Order ID:', orderId));
    buffer.writeln(row('Date    :', calculation.timestamp.toString().substring(0, 16)));
    buffer.writeln(row('Cashier :', calculation.cashierName));
    buffer.writeln(row('Shift   :', '${calculation.shiftLabel} (${calculation.shiftHours})'));
    buffer.writeln(row('Type    :', calculation.orderMode));
    buffer.writeln(row('Status  :', isOffline ? "OFFLINE (Stock Deducted)" : "ONLINE (Cloud Synced)"));
    buffer.writeln('-' * width);

    for (final item in calculation.items) {
      buffer.writeln(row('${item.quantity}x ${item.menuItem.name}', calculation.formatCurrency(item.totalPrice)));
      if (item.notes.isNotEmpty) {
        buffer.writeln('   Note: ${item.notes}');
      }
    }

    buffer.writeln('-' * width);
    buffer.writeln(row('Subtotal:', calculation.formattedSubtotal));
    if (calculation.serviceAmount > 0) {
      buffer.writeln(row('Service (${calculation.servicePercent.toStringAsFixed(0)}%):', calculation.formattedService));
    }
    buffer.writeln(row('Tax (${calculation.taxPercent.toStringAsFixed(0)}%):', calculation.formattedTax));
    buffer.writeln('-' * width);
    buffer.writeln(row('GRAND TOTAL:', calculation.formattedGrandTotal));
    buffer.writeln(row('Payment      :', calculation.paymentMethod));
    if (calculation.paymentMethod.contains('Cash') || calculation.paymentMethod.contains('Tunai')) {
      buffer.writeln(row('Cash Paid    :', calculation.formattedAmountPaid));
      buffer.writeln(row('CHANGE       :', calculation.formattedChange));
    }
    buffer.writeln('=' * width);
    buffer.writeln(center(receiptFooter));
    buffer.writeln(center('*** PAID - STOCK DEDUCTED ***'));
    buffer.writeln('-' * width);
    final trackerUrl = calculation.buildTrackerUrl(orderId, isOffline: isOffline, localIp: localIp);
    buffer.writeln(center('SCAN QR: LIVE STATUS & ORDER ALARM'));
    buffer.writeln(center('[ QR CODE LIVE TRACKER ]'));
    buffer.writeln(center(trackerUrl));
    buffer.writeln(center('Track Live Kitchen & Ready Alerts'));
    buffer.writeln('=' * width);
    buffer.writeln(center('[ESC/POS Paper Feed & Cut]'));

    return buffer.toString();
  }

  /// Builds ESC/POS binary commands for Cashier Shift Handover Z-Report
  List<int> buildShiftHandoverZReportBytes({
    required CashierShiftSession session,
    required String storeName,
    String storeTagline = 'POS & Kitchen Cloud System',
  }) {
    final builder = EscPosBuilder(paperWidthMm: _paperWidthMm);
    builder.init();

    // 1. Store Header & Title
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn(storeName.toUpperCase());
    builder.setDoubleSize(false);
    if (storeTagline.isNotEmpty) {
      builder.textLn(storeTagline);
    }
    builder.setBold(true);
    builder.textLn('SHIFT HANDOVER REPORT');
    builder.textLn('( Z - R E P O R T )');
    builder.setBold(false);
    builder.divider('=');

    // 2. Shift & Cashier Meta
    builder.alignLeft();
    builder.row('Shift ID    :', session.id);
    builder.row('Out Cashier :', session.cashierName);
    builder.row('Role        :', session.role);
    builder.row('Shift       :', '${session.shiftLabel} (${session.shiftHours})');
    builder.row('Start       :', session.startTime.toString().substring(0, 16));
    final endStr = session.endTime != null
        ? session.endTime!.toString().substring(0, 16)
        : DateTime.now().toString().substring(0, 16);
    builder.row('End         :', endStr);
    if (session.nextCashierName != null && session.nextCashierName!.isNotEmpty) {
      builder.row('In Cashier  :', session.nextCashierName!);
    }
    builder.divider('-');

    // 3. Sales & Volume Metrics
    builder.row('Total Orders:', '${session.totalOrders} Orders');
    builder.row('Gross Sales :', ReceiptCalculation.formatRupiah(session.grossSales));
    builder.row('Cash Sales  :', ReceiptCalculation.formatRupiah(session.cashSales));
    builder.row('QRIS/Card   :', ReceiptCalculation.formatRupiah(session.nonCashSales));
    builder.divider('-');

    // 4. Cash Drawer Reconciliation
    builder.row('Opening Cash:', ReceiptCalculation.formatRupiah(session.openingCash));
    builder.row('+ Cash Sales:', ReceiptCalculation.formatRupiah(session.cashSales));
    builder.setBold(true);
    final expected = session.expectedCash ?? (session.openingCash + session.cashSales);
    builder.row('EXPECTED    :', ReceiptCalculation.formatRupiah(expected));
    builder.setBold(false);

    final actual = session.closingCash ?? expected;
    builder.row('Actual Cash :', ReceiptCalculation.formatRupiah(actual));

    final variance = session.variance ?? (actual - expected);
    String varStatus = 'BALANCED';
    if (variance < 0) {
      varStatus = 'SHORT';
    } else if (variance > 0) {
      varStatus = 'SURPLUS';
    }
    builder.setBold(true);
    builder.row('VARIANCE    :', '${ReceiptCalculation.formatRupiah(variance)} ($varStatus)');
    builder.setBold(false);

    // 5. Handover Notes if present
    if (session.handoverNotes.trim().isNotEmpty) {
      builder.divider('-');
      builder.textLn('Handover Notes:');
      builder.textLn(session.handoverNotes.trim());
    }

    // 6. Signatures
    builder.divider('=');
    builder.alignCenter();
    builder.textLn('Handover Signatures:');
    builder.lineFeed(1);
    builder.row('( Out Cashier )', '( In Cashier )');
    builder.lineFeed(2);
    builder.row(session.cashierName, session.nextCashierName ?? 'Shift Receiver');
    builder.divider('-');
    builder.textLn('Nusantara Hybrid POS - #BuildHybridAI');
    builder.textLn('*** SHIFT OFFICIALLY CLOSED ***');
    builder.cutPaper();

    return builder.bytes;
  }

  /// Builds ESC/POS binary commands for ZReportData (58mm and 80mm paper widths)
  List<int> buildZReportBytes({
    required ZReportData report,
    String storeTagline = 'POS & Kitchen Cloud System',
  }) {
    final builder = EscPosBuilder(paperWidthMm: _paperWidthMm);
    builder.init();

    // 1. Store Header & Title
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn(report.storeName.toUpperCase());
    builder.setDoubleSize(false);
    if (storeTagline.isNotEmpty) {
      builder.textLn(storeTagline);
    }
    builder.setBold(true);
    builder.textLn('SHIFT HANDOVER REPORT');
    builder.textLn('( Z - R E P O R T )');
    builder.setBold(false);
    builder.divider('=');

    // 2. Shift & Cashier Metadata
    builder.alignLeft();
    builder.row('Report ID   :', report.reportId);
    builder.row('Out Cashier :', report.cashierName);
    builder.row('Role        :', report.role);
    builder.row('Shift       :', '${report.shiftLabel} (${report.shiftHours})');
    builder.row('Start       :', report.startTime.toString().substring(0, 16));
    builder.row('End         :', report.endTime.toString().substring(0, 16));
    if (report.nextCashierName != null && report.nextCashierName!.isNotEmpty) {
      builder.row('In Cashier  :', report.nextCashierName!);
    }
    builder.divider('-');

    // 3. Orders Breakdown & Sales Volume
    builder.row('Total Orders:', '${report.totalOrders} Orders');
    builder.row('Online/Cloud:', '${report.onlineOrderCount} Orders');
    builder.row('Offline JSON:', '${report.offlineOrderCount} Orders');
    builder.divider('-');

    // 4. Financial Totals
    builder.row('Gross Sales :', ReceiptCalculation.formatRupiah(report.grossSales));
    builder.row('Tax & Svc   :', ReceiptCalculation.formatRupiah(report.taxAndServiceTotal));
    builder.row('Cash Sales  :', ReceiptCalculation.formatRupiah(report.cashSales));
    builder.row('QRIS/Card   :', ReceiptCalculation.formatRupiah(report.nonCashSales));
    builder.divider('-');

    // 5. Cash Drawer Reconciliation
    builder.row('Opening Cash:', ReceiptCalculation.formatRupiah(report.openingCash));
    builder.row('+ Cash Sales:', ReceiptCalculation.formatRupiah(report.cashSales));
    builder.setBold(true);
    builder.row('EXPECTED    :', ReceiptCalculation.formatRupiah(report.expectedCash));
    builder.setBold(false);

    builder.row('Actual Cash :', ReceiptCalculation.formatRupiah(report.actualCash));

    final variance = report.variance;
    String varStatus = 'BALANCED';
    if (variance < 0) {
      varStatus = 'SHORT';
    } else if (variance > 0) {
      varStatus = 'SURPLUS';
    }
    builder.setBold(true);
    builder.row('VARIANCE    :', '${ReceiptCalculation.formatRupiah(variance)} ($varStatus)');
    builder.setBold(false);

    // 6. AI Shift Handover Summary
    if (report.aiSummary.trim().isNotEmpty) {
      builder.divider('-');
      builder.textLn('AI Summary & Notes:');
      builder.textLn(report.aiSummary.trim());
    }

    // 7. Signatures
    builder.divider('=');
    builder.alignCenter();
    builder.textLn('Handover Signatures:');
    builder.lineFeed(1);
    builder.row('( Out Cashier )', '( In Cashier )');
    builder.lineFeed(2);
    builder.row(report.cashierName, report.nextCashierName ?? 'Shift Receiver');
    builder.divider('-');
    builder.textLn('Nusantara Hybrid POS - #BuildHybridAI');
    builder.textLn('*** SHIFT RESMI DITUTUP (100% OFFLINE / ONLINE) ***');
    builder.cutPaper();

    return builder.bytes;
  }

  /// Prints the ZReportData directly to the selected Bluetooth printer via native SPP RFCOMM socket
  Future<bool> printZReport(
    ZReportData report, {
    String storeTagline = 'POS & Kitchen Cloud System',
  }) async {
    if (!hasPrinterSelected || _selectedPrinterAddress.isEmpty) {
      throw Exception(
        'Belum ada printer Bluetooth yang dipilih. Silakan pilih printer thermal di menu Pengaturan.',
      );
    }

    final bytes = buildZReportBytes(
      report: report,
      storeTagline: storeTagline,
    );

    try {
      final res = await _channel.invokeMethod<bool>('printBytes', {
        'address': _selectedPrinterAddress,
        'bytes': Uint8List.fromList(bytes),
      });

      if (res != true) {
        throw Exception(
          'Printer Bluetooth tidak merespons pengiriman data. Pastikan printer dalam keadaan ON.',
        );
      }
      return true;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal mencetak Z-Report Bluetooth (${e.code}).');
    }
  }

  /// Prints the Cashier Shift Handover Z-Report directly to the selected Bluetooth printer
  Future<bool> printShiftHandoverReport({
    required CashierShiftSession session,
    required String storeName,
    String storeTagline = 'POS & Kitchen Cloud System',
  }) async {
    if (!hasPrinterSelected || _selectedPrinterAddress.isEmpty) {
      throw Exception(
        'Belum ada printer Bluetooth yang dipilih. Silakan pilih printer thermal di menu Pengaturan.',
      );
    }

    final bytes = buildShiftHandoverZReportBytes(
      session: session,
      storeName: storeName,
      storeTagline: storeTagline,
    );

    try {
      final res = await _channel.invokeMethod<bool>('printBytes', {
        'address': _selectedPrinterAddress,
        'bytes': Uint8List.fromList(bytes),
      });

      if (res != true) {
        throw Exception(
          'Printer Bluetooth tidak merespons pengiriman data. Pastikan printer dalam keadaan ON.',
        );
      }
      return true;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Gagal mencetak Z-Report Bluetooth (${e.code}).');
    }
  }

  /// Scan local subnet for Kitchen raw ESC/POS printers listening on TCP port 9100
  Future<List<DiscoveredNetworkPrinter>> scanKitchenWifiPrinters({String? customSubnet}) async {
    if (kIsWeb) return [];

    try {
      final rawList = await NetworkPrinterPlatform.instance.scanSubnet(_kitchenPrinterPort);
      return rawList.map((p) {
        final ip = p['ip']?.toString() ?? '';
        final port = (p['port'] as int?) ?? _kitchenPrinterPort;
        final latency = (p['latencyMs'] as int?) ?? 0;
        return DiscoveredNetworkPrinter(
          ip: ip,
          port: port,
          name: 'ESC/POS Thermal Printer ($ip)',
          latencyMs: latency,
        );
      }).toList();
    } catch (e) {
      debugPrint('[NusantaraPrinterSDK] Wi-Fi printer scan error: $e');
      return [];
    }
  }

  /// Sends raw ESC/POS bytes directly over TCP socket to port 9100
  Future<bool> printRawToNetworkPrinter({
    required String ip,
    required List<int> bytes,
    int port = 9100,
  }) async {
    if (kIsWeb || ip.trim().isEmpty) return false;

    try {
      return await NetworkPrinterPlatform.instance.sendRawBytes(ip.trim(), port, bytes);
    } catch (e) {
      debugPrint('[NusantaraPrinterSDK] Network printer error ($ip:$port): $e');
      return false;
    }
  }

  /// Builds ESC/POS binary commands for Kitchen Order Ticket (KOT)
  List<int> buildKitchenOrderTicketBytes(PosTransaction order) {
    final builder = EscPosBuilder(paperWidthMm: _paperWidthMm);
    builder.init();

    // 1. Large Bold Header
    builder.alignCenter();
    builder.setBold(true);
    builder.setDoubleSize(true);
    builder.textLn('*** KITCHEN TICKET (KOT) ***');
    builder.lineFeed(1);
    builder.textLn('QUEUE: ${order.queueNumber}');
    builder.setDoubleSize(false);

    final isTakeAway = order.orderMode.toUpperCase().contains('TAKE') ||
        order.orderMode.toUpperCase().contains('BUNGKUS');
    builder.textLn(isTakeAway ? '[ TAKE AWAY ]' : '[ DINE IN ]');
    builder.divider('=');

    // 2. Metadata
    builder.alignLeft();
    builder.row('Order ID :', order.receiptId);
    builder.row('Time     :', order.timestamp.toString().substring(0, 16));
    builder.row('Cashier  :', order.cashierName);
    builder.divider('-');

    // 3. Large Items & Notes for Chefs
    builder.setBold(true);
    for (final item in order.items) {
      builder.textLn('${item.quantity}x ${item.menuItem.name}');
      if (item.notes.isNotEmpty) {
        builder.setBold(false);
        builder.textLn('   * NOTES: ${item.notes.toUpperCase()}');
        builder.setBold(true);
      }
    }
    builder.setBold(false);

    builder.divider('=');
    builder.alignCenter();
    builder.textLn('Prepare & tap Ready for Pickup');
    builder.cutPaper();

    return builder.bytes;
  }

  final Set<String> _sessionAutoPrintedIds = {};

  /// Automatically prints Kitchen Order Ticket to Wi-Fi IP (or Bluetooth fallback) once per order.
  Future<bool> printKitchenOrderTicket(
    PosTransaction order, {
    bool forceManual = false,
  }) async {
    final keyReceipt = order.receiptId.trim();
    final keyId = order.id.trim();
    if (!forceManual) {
      final alreadyPrinted = (keyReceipt.isNotEmpty && _sessionAutoPrintedIds.contains(keyReceipt)) ||
          (keyId.isNotEmpty && _sessionAutoPrintedIds.contains(keyId));
      if (alreadyPrinted) return false;
      if (keyReceipt.isNotEmpty) _sessionAutoPrintedIds.add(keyReceipt);
      if (keyId.isNotEmpty) _sessionAutoPrintedIds.add(keyId);
    }

    final bytes = buildKitchenOrderTicketBytes(order);
    bool printed = false;

    // 1. Print to Kitchen Wi-Fi Printer if configured
    if (hasKitchenPrinterSelected) {
      final ok = await printRawToNetworkPrinter(
        ip: _kitchenPrinterIp,
        bytes: bytes,
        port: _kitchenPrinterPort,
      );
      if (ok) printed = true;
    }

    // 2. Print to paired Bluetooth printer only as fallback if Wi-Fi did not print
    if (!printed && hasPrinterSelected) {
      try {
        final res = await _channel.invokeMethod<bool>('printBytes', {
          'address': _selectedPrinterAddress,
          'bytes': Uint8List.fromList(bytes),
        });
        if (res == true) printed = true;
      } catch (_) {}
    }

    if (printed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final printedList = prefs.getStringList(_kPrintedKitchenOrderIds) ?? [];
        if (!printedList.contains(order.receiptId)) {
          printedList.add(order.receiptId);
          await prefs.setStringList(_kPrintedKitchenOrderIds, printedList);
        }
      } catch (_) {}
    }

    return printed;
  }
}
