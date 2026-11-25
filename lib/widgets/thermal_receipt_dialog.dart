import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order_item.dart';
import '../models/receipt_calculation.dart';
import '../models/transaction_model.dart';
import '../sdk/nusantara_printer_sdk.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/local_kitchen_bridge.dart';
import '../services/firestore_service.dart';
import '../services/whatsapp_gateway_service.dart';
import '../services/customer_session_service.dart';
import '../theme/app_theme.dart';
import 'order_qr_code_widget.dart';
import '../screens/customer_order_tracker_screen.dart';

class ThermalReceiptDialog extends StatefulWidget {
  final String orderId;
  final DateTime timestamp;
  final List<OrderItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final String paymentMethod;
  final double cashReceived;
  final double changeAmount;
  final String aiSource;
  final bool isOffline;
  final ReceiptCalculation? calculation;

  const ThermalReceiptDialog({
    super.key,
    required this.orderId,
    required this.timestamp,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paymentMethod,
    required this.cashReceived,
    required this.changeAmount,
    required this.aiSource,
    this.isOffline = false,
    this.calculation,
  });

  @override
  State<ThermalReceiptDialog> createState() => _ThermalReceiptDialogState();
}

class _ThermalReceiptDialogState extends State<ThermalReceiptDialog> {
  final SettingsService _settings = SettingsService();
  final NusantaraPrinterSDK _printerSdk = NusantaraPrinterSDK();
  bool _isPrintingPdf = false;
  bool _isPrintingBluetooth = false;

  late ReceiptCalculation _effectiveCalc;

  @override
  void initState() {
    super.initState();
    _effectiveCalc = widget.calculation ??
        ReceiptCalculation.compute(
          items: widget.items,
          taxPercent: _settings.taxRate,
          servicePercent: _settings.serviceChargeRate,
          rawAmountPaidText: widget.cashReceived.round().toString(),
          paymentMethod: widget.paymentMethod,
          orderMode: 'Dine In',
          orderNotes: '',
          timestamp: widget.timestamp,
        );
  }

  String _generatePlainText() {
    return _printerSdk.generateEscPosTextPreview(
      calculation: _effectiveCalc,
      storeName: _settings.storeName,
      storeTagline: _settings.storeTagline,
      storeAddress: _settings.storeAddress,
      storePhone: _settings.storePhone,
      receiptFooter: _settings.receiptFooter,
      orderId: widget.orderId,
      isOffline: widget.isOffline,
      localIp: LocalKitchenBridge().localIp,
    );
  }

  PosTransaction _buildCurrentTransaction() {
    return PosTransaction(
      id: widget.orderId,
      timestamp: widget.timestamp,
      items: widget.items,
      subtotal: widget.subtotal,
      tax: widget.tax,
      total: widget.total,
      serviceAmount: _effectiveCalc.serviceAmount.toDouble(),
      paymentMethod: widget.paymentMethod,
      cashReceived: widget.cashReceived,
      changeAmount: widget.changeAmount,
      aiSource: widget.aiSource,
      queueNumber: _effectiveCalc.queueNumber,
      orderMode: _effectiveCalc.orderMode,
      orderNotes: _effectiveCalc.orderNotes,
      customerPhone: _effectiveCalc.customerPhone,
      customerName: _effectiveCalc.customerName,
      isOffline: widget.isOffline,
      kitchenStatus: 'preparing',
      estimatedPrepMinutes: 10,
      trackingToken: _effectiveCalc.trackingToken,
    );
  }

  void _openCustomerTracker() {
    HapticFeedback.lightImpact();
    final queueInt = int.tryParse(_effectiveCalc.queueNumber.replaceAll('#', '')) ?? 1;
    final tx = _buildCurrentTransaction();

    LocalKitchenBridge().registerLocalOrder(tx);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerOrderTrackerScreen(
          orderId: widget.orderId,
          trackingToken: _effectiveCalc.trackingToken,
          queueNumber: queueInt,
          initialEtaMinutes: 10,
          customerName: _effectiveCalc.customerName,
          initialTransaction: tx,
        ),
      ),
    );
  }

  Future<void> _sendWhatsAppAlarmWithQr() async {
    HapticFeedback.lightImpact();
    final tx = _buildCurrentTransaction();
    LocalKitchenBridge().registerLocalOrder(tx);

    String targetPhone = _effectiveCalc.customerPhone.trim();
    if (targetPhone.isEmpty) {
      final phoneCtrl = TextEditingController(
        text: CustomerSessionService().phone.isNotEmpty ? CustomerSessionService().phone : '081234567890',
      );
      final entered = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: Color(0xFF15803D)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Send Alert & QR via WhatsApp',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the customer\'s WhatsApp number to send the QR Code & live cooking tracker link:',
                style: TextStyle(fontSize: 12, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '081234567890',
                  prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF15803D)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send WA + QR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (entered == null || entered.isEmpty) return;
      targetPhone = entered;
      await LocalKitchenBridge().updateOrderCustomerPhone(widget.orderId, targetPhone);
      FirestoreService().updateOrderCustomerPhone(widget.orderId, targetPhone);
    }

    final storeName = _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara Hybrid POS';
    final ok = await WhatsAppGatewayService().openDirectWhatsAppWithQr(
      customerPhone: targetPhone,
      order: tx,
      storeName: storeName,
      customerName: _effectiveCalc.customerName,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF15803D) : AppTheme.roseRed,
          behavior: SnackBarBehavior.floating,
          content: Text(
            ok
                ? '✓ Opening WhatsApp to $targetPhone with QR Code & Live Order Tracker link!'
                : 'Failed to open WhatsApp. Ensure WhatsApp is installed on this device.',
          ),
        ),
      );
    }
  }

  // 1. Direct Bluetooth ESC/POS Print via Custom Native SDK
  Future<void> _handleBluetoothPrint() async {
    setState(() => _isPrintingBluetooth = true);

    try {
      if (!_printerSdk.hasPrinterSelected) {
        _showNoPrinterDialog();
        return;
      }

      final success = await _printerSdk.printTransactionReceipt(
        calculation: _effectiveCalc,
        storeName: _settings.storeName,
        storeTagline: _settings.storeTagline,
        storeAddress: _settings.storeAddress,
        storePhone: _settings.storePhone,
        receiptFooter: _settings.receiptFooter,
        orderId: widget.orderId,
        isOffline: widget.isOffline,
        localIp: LocalKitchenBridge().localIp,
      );

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            content: Text(tr('receipt_bt_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Printer Notice: $e'),
            action: SnackBarAction(
              label: 'Preview',
              textColor: Colors.white,
              onPressed: _showEscPosPreviewDialog,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrintingBluetooth = false);
      }
    }
  }

  void _showNoPrinterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('printer_sdk_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('printer_no_devices')),
            const SizedBox(height: 12),
            const Text(
              'You can inspect the raw ESC/POS text preview or print via Android Spooler (PDF/Roll80).',
              style: TextStyle(fontSize: 12, color: AppTheme.slateMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEscPosPreviewDialog();
            },
            child: Text(tr('receipt_preview_escpos')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 2. Raw ESC/POS Preview Modal for Judges
  void _showEscPosPreviewDialog() {
    final rawText = _generatePlainText();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.code_rounded, color: AppTheme.royalBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              tr('receipt_preview_escpos'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: Text(
              rawText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFE2E8F0),
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.royalBlue,
                  content: Text(tr('receipt_copied')),
                ),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: Text(tr('receipt_copy')),
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

  // 3. Fallback Offline Native Android Print Spooler (PDF / Roll 80mm)
  Future<void> _handleNativePrint() async {
    setState(() => _isPrintingPdf = true);

    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(widget.timestamp);

    try {
      await Printing.layoutPdf(
        name: 'Struk_${widget.orderId}',
        format: PdfPageFormat.roll80,
        onLayout: (PdfPageFormat format) async {
          final doc = pw.Document();
          final fontMono = pw.Font.courier();
          final fontMonoBold = pw.Font.courierBold();

          doc.addPage(
            pw.Page(
              pageFormat: format,
              margin: const pw.EdgeInsets.all(12),
              build: (pw.Context ctx) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text(
                        _settings.storeName.toUpperCase(),
                        style: pw.TextStyle(font: fontMonoBold, fontSize: 13),
                      ),
                    ),
                    pw.Center(
                      child: pw.Text(
                        _settings.storeTagline,
                        style: pw.TextStyle(font: fontMono, fontSize: 9),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    pw.Center(
                      child: pw.Text(
                        'QUEUE: ${_effectiveCalc.queueNumber}',
                        style: pw.TextStyle(font: fontMonoBold, fontSize: 13),
                      ),
                    ),
                    pw.Center(
                      child: pw.Text(
                        _effectiveCalc.orderMode.toUpperCase().contains('TAKE')
                            ? 'TAKE AWAY'
                            : 'DINE IN',
                        style: pw.TextStyle(font: fontMonoBold, fontSize: 10),
                      ),
                    ),
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    pw.Text('Order ID : ${widget.orderId}', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text('Date     : $dateStr', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text('Cashier  : ${_effectiveCalc.cashierName}', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text('Shift    : ${_effectiveCalc.shiftLabel} (${_effectiveCalc.shiftHours})', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text('Type     : ${_effectiveCalc.orderMode}', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text('AI Engine: ${widget.aiSource}', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                    pw.Text(
                      'Mode     : ${widget.isOffline ? "OFFLINE (Stock Deducted)" : "ONLINE (Cloud Synced)"}',
                      style: pw.TextStyle(font: fontMono, fontSize: 9),
                    ),
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    ..._effectiveCalc.items.map((it) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  '${it.quantity}x ${it.menuItem.name}',
                                  style: pw.TextStyle(font: fontMono, fontSize: 9),
                                ),
                              ),
                              pw.Text(
                                currency.format(it.totalPrice),
                                style: pw.TextStyle(font: fontMonoBold, fontSize: 9),
                              ),
                            ],
                          ),
                        )),
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Subtotal:', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                        pw.Text(_effectiveCalc.formattedSubtotal, style: pw.TextStyle(font: fontMono, fontSize: 9)),
                      ],
                    ),
                    if (_effectiveCalc.serviceAmount > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Service (${_effectiveCalc.servicePercent.toStringAsFixed(0)}%):',
                            style: pw.TextStyle(font: fontMono, fontSize: 9),
                          ),
                          pw.Text(_effectiveCalc.formattedService, style: pw.TextStyle(font: fontMono, fontSize: 9)),
                        ],
                      ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Tax (${_effectiveCalc.taxPercent.toStringAsFixed(0)}%):',
                          style: pw.TextStyle(font: fontMono, fontSize: 9),
                        ),
                        pw.Text(_effectiveCalc.formattedTax, style: pw.TextStyle(font: fontMono, fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('GRAND TOTAL:', style: pw.TextStyle(font: fontMonoBold, fontSize: 11)),
                        pw.Text(_effectiveCalc.formattedGrandTotal, style: pw.TextStyle(font: fontMonoBold, fontSize: 11)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Payment Method:', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                        pw.Text(_effectiveCalc.paymentMethod, style: pw.TextStyle(font: fontMono, fontSize: 9)),
                      ],
                    ),
                    if (_effectiveCalc.paymentMethod.contains('Cash') || _effectiveCalc.paymentMethod.contains('Tunai')) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Cash Paid:', style: pw.TextStyle(font: fontMono, fontSize: 9)),
                          pw.Text(_effectiveCalc.formattedAmountPaid, style: pw.TextStyle(font: fontMono, fontSize: 9)),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('CHANGE:', style: pw.TextStyle(font: fontMonoBold, fontSize: 10)),
                          pw.Text(_effectiveCalc.formattedChange, style: pw.TextStyle(font: fontMonoBold, fontSize: 10)),
                        ],
                      ),
                    ],
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    pw.Center(
                      child: pw.Text(
                        EscPosBuilder.sanitizeForEscPos(_settings.receiptFooter),
                        style: pw.TextStyle(font: fontMono, fontSize: 9),
                      ),
                    ),
                    pw.Center(
                      child: pw.Text(
                        '*** LUNAS - STOK OTOMATIS TERPOTONG ***',
                        style: pw.TextStyle(font: fontMonoBold, fontSize: 8),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                    pw.Center(
                      child: pw.Text(
                        'SCAN QR: CEK STATUS & ALARM PESANAN',
                        style: pw.TextStyle(font: fontMonoBold, fontSize: 8),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Center(
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: _effectiveCalc.buildTrackerUrl(
                          widget.orderId,
                          isOffline: widget.isOffline,
                          localIp: LocalKitchenBridge().localIp,
                        ),
                        width: 70,
                        height: 70,
                      ),
                    ),
                    pw.Center(
                      child: pw.Text(
                        'Pantau Live Dapur & Notifikasi Siap',
                        style: pw.TextStyle(font: fontMono, fontSize: 7),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
          return doc.save();
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.royalBlue,
            behavior: SnackBarBehavior.floating,
            content: Text(tr('receipt_printed')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Print notice: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrintingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(widget.timestamp);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF9), // Thermal paper tinted texture
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.royalBlue.withAlpha(35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Zigzag Receipt Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  color: AppTheme.royalBlue,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 30, color: AppTheme.brightYellow),
                    const SizedBox(height: 3),
                    Text(
                      _settings.storeName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      _settings.storeTagline,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Prominent Queue Number & Order Mode Header Box
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.royalBlue, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'ANTRIAN / QUEUE: ${_effectiveCalc.queueNumber}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.royalBlue,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _effectiveCalc.orderMode.toUpperCase().contains('TAKE')
                                ? 'TAKE AWAY (BUNGKUS)'
                                : 'MAKAN DI TEMPAT (DINE IN)',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Offline / Online Realtime Stock Deduction Badge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      decoration: BoxDecoration(
                        color: widget.isOffline ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.isOffline ? const Color(0xFFFDE68A) : const Color(0xFF86EFAC),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.isOffline ? Icons.offline_pin_rounded : Icons.check_circle_rounded,
                            size: 13,
                            color: widget.isOffline ? const Color(0xFFB45309) : const Color(0xFF15803D),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.isOffline
                                  ? 'OFFLINE: Tersimpan di Antrean JSON & Stok Terpotong'
                                  : 'ONLINE: Cloud Synced & Stok Terpotong Real-Time',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: widget.isOffline ? const Color(0xFFB45309) : const Color(0xFF15803D),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Metadata
                    _buildRowMono('Order ID:', widget.orderId),
                    _buildRowMono('Tanggal :', dateStr),
                    _buildRowMono('Kasir   :', _effectiveCalc.cashierName),
                    _buildRowMono('Shift   :', '${_effectiveCalc.shiftLabel} (${_effectiveCalc.shiftHours})'),
                    _buildRowMono('Tipe    :', _effectiveCalc.orderMode),
                    _buildRowMono(
                      'AI Engine:',
                      widget.aiSource == 'ON_DEVICE' ? 'Local: Gemini Nano' : 'Cloud: Gemini 3.8 Flash',
                    ),
                    const SizedBox(height: 6),
                    _buildDashedLine(),
                    const SizedBox(height: 6),

                    // Items
                    ..._effectiveCalc.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity}x ${item.menuItem.name}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.darkNavy,
                                    ),
                                  ),
                                ),
                                Text(
                                  currency.format(item.totalPrice),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (item.notes.isNotEmpty)
                              Text(
                                '  (${item.notes})',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 6),
                    _buildDashedLine(),
                    const SizedBox(height: 6),

                    // Summary
                    _buildRowMono('Subtotal:', _effectiveCalc.formattedSubtotal),
                    if (_effectiveCalc.serviceAmount > 0)
                      _buildRowMono(
                        'Service (${_effectiveCalc.servicePercent.toStringAsFixed(0)}%):',
                        _effectiveCalc.formattedService,
                      ),
                    _buildRowMono(
                      'Pajak PB1 (${_effectiveCalc.taxPercent.toStringAsFixed(0)}%):',
                      _effectiveCalc.formattedTax,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL:',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                        Text(
                          _effectiveCalc.formattedGrandTotal,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.royalBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildRowMono('Metode Bayar:', _effectiveCalc.paymentMethod),
                    if (_effectiveCalc.paymentMethod.contains('Cash') || _effectiveCalc.paymentMethod.contains('Tunai')) ...[
                      _buildRowMono('Tunai Diterima:', _effectiveCalc.formattedAmountPaid),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'KEMBALIAN:',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF15803D),
                            ),
                          ),
                          Text(
                            _effectiveCalc.formattedChange,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 8),
                    _buildDashedLine(),
                    const SizedBox(height: 6),
                    Text(
                      '${_settings.receiptFooter}\nNusantara Hybrid POS',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),

                    // Prominent Live Order Tracker QR Code Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.royalBlue.withAlpha(120), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.royalBlue.withAlpha(20),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppTheme.royalBlue),
                              SizedBox(width: 6),
                              Text(
                                'SCAN QR INI UNTUK PANTAU ESTIMASI',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.royalBlue,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            '& ALARM PESANAN SIAP',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFD97706),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _openCustomerTracker,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.royalBlue.withAlpha(40)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OrderQrCodeWidget(
                                    data: _effectiveCalc.buildTrackerUrl(
                                      widget.orderId,
                                      isOffline: widget.isOffline,
                                      localIp: LocalKitchenBridge().localIp,
                                    ),
                                    size: 160,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.lightBlueTint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.touch_app_rounded, size: 13, color: AppTheme.royalBlue),
                                        SizedBox(width: 4),
                                        Text(
                                          'Klik Barcode untuk Buka Pelacak',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.royalBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Pantau live proses masak & terima getar saat siap!',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slateMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              onPressed: _openCustomerTracker,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.royalBlue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.phone_android_rounded, size: 16, color: AppTheme.brightYellow),
                              label: const Text(
                                'Buka Layar Pelacak Pesanan (Customer Tracker)',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              onPressed: _sendWhatsAppAlarmWithQr,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF15803D),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.chat_rounded, size: 16, color: AppTheme.brightYellow),
                              label: const Text(
                                'Kirim Alarm & QR ke WA Pembeli',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // BUTTON 1: Custom Native Android Bluetooth ESC/POS Print
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _isPrintingBluetooth ? null : _handleBluetoothPrint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isPrintingBluetooth
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.bluetooth_connected_rounded, size: 18),
                        label: Text(
                          _isPrintingBluetooth ? 'Mencetak ke Bluetooth...' : tr('receipt_print_bt'),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // BUTTON 2: Offline Android Print Spooler (PDF / Thermal 80mm)
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _isPrintingPdf ? null : _handleNativePrint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.goldenAmber,
                          foregroundColor: AppTheme.darkNavy,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isPrintingPdf
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkNavy),
                              )
                            : const Icon(Icons.print_rounded, size: 18, color: AppTheme.darkNavy),
                        label: Text(
                          _isPrintingPdf ? tr('receipt_printing') : tr('receipt_print'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // BUTTON 3: Inspect Raw ESC/POS & Close Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showEscPosPreviewDialog,
                            icon: const Icon(Icons.code_rounded, size: 14),
                            label: Text(
                              tr('receipt_preview_escpos'),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.royalBlue,
                              side: const BorderSide(color: AppTheme.royalBlue),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.darkNavy,
                              side: const BorderSide(color: AppTheme.cardBorder),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(
                              tr('receipt_close'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRowMono(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppTheme.darkNavy),
          ),
          Text(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDashedLine() {
    return Row(
      children: List.generate(
        32,
        (index) => Expanded(
          child: Container(
            color: index % 2 == 0 ? Colors.grey.shade400 : Colors.transparent,
            height: 1,
          ),
        ),
      ),
    );
  }
}
