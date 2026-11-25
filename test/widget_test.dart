import 'package:flutter_test/flutter_test.dart';
import 'package:nusantara_hybrid_pos/services/localization_service.dart';
import 'package:nusantara_hybrid_pos/models/menu_item.dart';
import 'package:nusantara_hybrid_pos/models/order_item.dart';
import 'package:nusantara_hybrid_pos/models/raw_material.dart';
import 'package:nusantara_hybrid_pos/models/receipt_calculation.dart';
import 'package:nusantara_hybrid_pos/models/cashier_shift.dart';
import 'package:nusantara_hybrid_pos/models/expense_model.dart';
import 'package:nusantara_hybrid_pos/widgets/analytics_charts.dart';
import 'package:nusantara_hybrid_pos/sdk/nusantara_printer_sdk.dart';
import 'package:nusantara_hybrid_pos/utils/z_report_pdf_exporter.dart';
import 'package:nusantara_hybrid_pos/models/transaction_model.dart';
import 'package:nusantara_hybrid_pos/services/menu_availability_notifier.dart';
import 'package:nusantara_hybrid_pos/services/menu_catalog_service.dart';
import 'package:nusantara_hybrid_pos/services/settings_service.dart';
import 'package:nusantara_hybrid_pos/state/pos_state.dart';
import 'package:nusantara_hybrid_pos/services/ai_service.dart';
import 'package:nusantara_hybrid_pos/services/customer_session_service.dart';
import 'package:nusantara_hybrid_pos/services/whatsapp_gateway_service.dart';
import 'package:nusantara_hybrid_pos/services/email_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LocalizationService defaults to English and toggles properly', () {
    final loc = LocalizationService();
    expect(loc.currentLanguage.value, 'en');
    expect(loc.isEnglish, true);
    expect(loc.t('app_title'), 'Nusantara Hybrid POS');

    loc.setLanguage('id');
    expect(loc.currentLanguage.value, 'id');
    expect(loc.isIndonesian, true);
    expect(loc.t('nav_cashier'), 'Kasir POS');

    loc.setLanguage('en');
  });

  test('Recipe portion calculation computes available stock accurately', () {
    const rawStockMap = {
      'raw_espresso': RawMaterial(
        id: 'raw_espresso',
        name: 'Espresso',
        category: 'Kopi',
        currentStock: 180,
        unit: 'g',
        minSafetyStock: 20,
        costPerUnit: 200,
      ),
      'raw_milk': RawMaterial(
        id: 'raw_milk',
        name: 'Milk',
        category: 'Dairy',
        currentStock: 500,
        unit: 'ml',
        minSafetyStock: 100,
        costPerUnit: 25,
      ),
    };

    const item = MenuItem(
      id: 'menu_latte',
      name: 'Latte',
      category: 'Minuman',
      price: 25000,
      description: 'Latte',
      recipe: {'raw_espresso': 18, 'raw_milk': 100},
    );

    // 180g / 18g = 10 portions; 500ml / 100ml = 5 portions. Bottleneck = 5 portions.
    final available = item.calculateAvailablePortions(rawStockMap);
    expect(available, 5);

    final cogs = item.calculateCostOfGoods(rawStockMap);
    // (18 * 200) + (100 * 25) = 3600 + 2500 = 6100
    expect(cogs, 6100);
  });

  test('ReceiptCalculation integer Rupiah math and cash parsing', () {
    const item1 = MenuItem(
      id: 'm1',
      name: 'Kopi Susu Gula Aren',
      category: 'Minuman',
      price: 18000,
      description: '',
    );
    const item2 = MenuItem(
      id: 'm2',
      name: 'Croissant Butter',
      category: 'Cemilan',
      price: 22000,
      description: '',
    );

    final List<OrderItem> cart = [
      OrderItem(menuItem: item1, quantity: 2), // 36,000
      OrderItem(menuItem: item2, quantity: 1), // 22,000
    ];

    // Subtotal = 58,000. Tax = 10% (5,800). Service = 5% (2,900). Grand Total = 66,700.
    final calc = ReceiptCalculation.compute(
      items: cart,
      taxPercent: 10.0,
      servicePercent: 5.0,
      rawCashInput: '100k', // Should parse to 100,000
      paymentMethod: 'Cash',
      orderMode: 'Dine In',
      orderNotes: 'Less ice',
    );

    expect(calc.subtotal, 58000);
    expect(calc.taxAmount, 5800);
    expect(calc.serviceAmount, 2900);
    expect(calc.grandTotal, 66700);
    expect(calc.amountPaid, 100000);
    expect(calc.isPaidSufficient, true);
    expect(calc.changeAmount, 33300);
    expect(calc.shortage, 0);

    // Test shorthand cash parsers
    expect(ReceiptCalculation.parseCashInput('50rb'), 50000);
    expect(ReceiptCalculation.parseCashInput('1.5jt'), 1500000);
    expect(ReceiptCalculation.parseCashInput('Rp 75.000'), 75000);
    expect(ReceiptCalculation.parseCashInput('200K'), 200000);

    // Test shortage condition
    final shortageCalc = ReceiptCalculation.compute(
      items: cart,
      taxPercent: 10.0,
      servicePercent: 5.0,
      rawCashInput: '50000',
      paymentMethod: 'Cash',
    );
    expect(shortageCalc.isPaidSufficient, false);
    expect(shortageCalc.shortage, 16700);
    expect(shortageCalc.changeAmount, 0); // Change is strictly 0, never negative!
  });

  test('NusantaraPrinterSDK EscPosBuilder 58mm & 80mm column formatting', () {
    final builder58 = EscPosBuilder(paperWidthMm: 58);
    builder58.init();
    builder58.alignCenter();
    builder58.setBold(true);
    builder58.textLn('NUSANTARA POS');
    builder58.divider();
    builder58.row('Kopi Susu Aren x2', 'Rp 36.000');
    builder58.lineFeed(2);
    builder58.cutPaper();

    final bytes58 = builder58.bytes;
    expect(bytes58.isNotEmpty, true);

    final builder80 = EscPosBuilder(paperWidthMm: 80);
    builder80.init();
    builder80.alignCenter();
    builder80.textLn('NUSANTARA POS 80MM');
    builder80.row('Croissant Butter x1', 'Rp 22.000');
    final bytes80 = builder80.bytes;
    expect(bytes80.isNotEmpty, true);
  });

  test('EscPosBuilder.sanitizeForEscPos cleans bullets, em-dashes, curly quotes and emojis', () {
    const rawTagline = 'Nusantara Hybrid POS • #BuildHybridAI';
    expect(
      EscPosBuilder.sanitizeForEscPos(rawTagline),
      'Nusantara Hybrid POS - #BuildHybridAI',
    );

    const unicodeText = '“Spesial” — ‘Kopi Susu’ ☕';
    expect(
      EscPosBuilder.sanitizeForEscPos(unicodeText),
      '"Spesial" - \'Kopi Susu\' ',
    );

    // Verify builder handles it without throwing ArgumentError
    final builder = EscPosBuilder(paperWidthMm: 58);
    expect(() {
      builder.textLn(rawTagline);
      builder.textLn(unicodeText);
    }, returnsNormally);
  });

  test('CashierShiftSession metrics calculation and ESC/POS Z-Report formatting', () {
    final session = CashierShiftSession(
      id: 'SHIFT-TEST-01',
      cashierId: 'emp_1',
      cashierName: 'Nurmiyaty',
      role: 'Lead Cashier',
      shiftLabel: 'Morning Shift',
      shiftHours: '07:00 - 15:00',
      startTime: DateTime(2026, 11, 23, 7, 0),
      openingCash: 200000,
    );

    // Expected cash: 200,000 opening + 150,000 cash sales = 350,000
    // If counted cash is 350,000 -> variance = 0 (balanced)
    // If counted cash is 340,000 -> variance = -10,000 (shortage)
    final closed = session.copyWith(
      grossSales: 250000,
      cashSales: 150000,
      nonCashSales: 100000,
      expectedCash: 350000,
      closingCash: 350000,
      variance: 0,
      notes: 'Operasional lancar tanpa selisih',
      nextCashierName: 'Rina Sari',
    );

    expect(closed.handoverNotes, 'Operasional lancar tanpa selisih');
    expect(closed.variance, 0);

    final sdk = NusantaraPrinterSDK();
    final zBytes = sdk.buildShiftHandoverZReportBytes(
      session: closed,
      storeName: 'Kopi Nusantara',
    );
    expect(zBytes.isNotEmpty, true);
  });

  test('ExpenseModel and FinancialBucket calculate Net Profit and Margin correctly', () {
    final exp = ExpenseModel(
      id: 'EXP-TEST-01',
      title: 'Restock Biji Kopi',
      category: 'Restock',
      amount: 350000,
      timestamp: DateTime(2026, 11, 23, 10, 0),
      loggedBy: 'Nurmiyaty',
    );
    expect(exp.amount, 350000);
    expect(exp.toMap()['category'], 'Restock');

    final bucket = FinancialBucket(
      label: 'Monday',
      date: DateTime(2026, 11, 23),
      sales: 1000000,
      expenses: 350000,
    );
    // Net profit = 1,000,000 - 350,000 = 650,000
    expect(bucket.netProfit, 650000);
    // Margin = (650,000 / 1,000,000) * 100 = 65.0%
    expect(bucket.marginPercent, 65.0);
  });

  test('ZReportData model serialization, ESC/POS byte generation, and Offline JSON preservation', () {
    final now = DateTime(2026, 11, 23, 15, 0);
    final report = ZReportData(
      storeName: 'Nusantara Hybrid POS',
      reportId: 'ZRP-20261123-1500',
      cashierName: 'Nurmiyaty',
      role: 'Lead Cashier',
      shiftLabel: 'Morning Shift',
      shiftHours: '07:00 - 15:00',
      startTime: DateTime(2026, 11, 23, 7, 0),
      endTime: now,
      totalOrders: 15,
      onlineOrderCount: 12,
      offlineOrderCount: 3,
      grossSales: 450000,
      taxAndServiceTotal: 45000,
      cashSales: 300000,
      nonCashSales: 150000,
      openingCash: 200000,
      expectedCash: 500000, // 200,000 + 300,000
      actualCash: 500000,
      variance: 0,
      aiSummary: 'Shift pagi lancar, kas seimbang sempurna',
      nextCashierName: 'Rina Sari',
      createdAt: now,
      syncedToFirestore: false,
    );

    expect(report.isBalanced, true);
    expect(report.varianceStatus, 'BALANCED');

    final jsonStr = report.toJson();
    final restored = ZReportData.fromJson(jsonStr);
    expect(restored.reportId, 'ZRP-20261123-1500');
    expect(restored.onlineOrderCount, 12);
    expect(restored.offlineOrderCount, 3);
    expect(restored.syncedToFirestore, false);

    // Verify ESC/POS generation for ZReportData
    final sdk = NusantaraPrinterSDK();
    final zBytes = sdk.buildZReportBytes(report: report);
    expect(zBytes.isNotEmpty, true);
    // Should contain ESC @ init sequence
    expect(zBytes[0], 0x1B);
    expect(zBytes[1], 0x40);
  });

  test('ZReportPdfExporter generates valid PDF 1.4 byte buffer with %PDF-1.4 header', () async {
    final now = DateTime(2026, 11, 23, 15, 0);
    final report = ZReportData(
      storeName: 'Nusantara Hybrid POS',
      reportId: 'ZRP-20261123-1500',
      cashierName: 'Nurmiyaty',
      role: 'Lead Cashier',
      shiftLabel: 'Morning Shift',
      shiftHours: '07:00 - 15:00',
      startTime: DateTime(2026, 11, 23, 7, 0),
      endTime: now,
      totalOrders: 10,
      onlineOrderCount: 8,
      offlineOrderCount: 2,
      grossSales: 320000,
      taxAndServiceTotal: 32000,
      cashSales: 200000,
      nonCashSales: 120000,
      openingCash: 200000,
      expectedCash: 400000,
      actualCash: 400000,
      variance: 0,
      aiSummary: 'Shift operasional stabil.',
      nextCashierName: 'Budi Santoso',
      createdAt: now,
      syncedToFirestore: true,
    );

    final pdfBytes = await ZReportPdfExporter.generatePdfBytes(report: report);
    expect(pdfBytes.isNotEmpty, true);
    // Standard PDF files start with ASCII "%PDF"
    final headerStr = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(headerStr.startsWith('%PDF'), true);
  });

  test('EscPosBuilder generates correct native ESC/POS QR Code byte sequences', () {
    final builder = EscPosBuilder(paperWidthMm: 58);
    builder.init();
    builder.qrCode('https://nusantara-hybrid-pos.web.app/?trackOrder=TX-12345&queue=1&eta=10', moduleSize: 6);

    final bytes = builder.bytes;
    expect(bytes.isNotEmpty, true);

    // Verify ESC @
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);

    // Verify GS ( k sequence presence
    expect(bytes.contains(0x1D), true);
    expect(bytes.contains(0x28), true);
    expect(bytes.contains(0x6B), true);
  });

  test('RawMaterial minThreshold accurately triggers isLowStock alert', () {
    const raw = RawMaterial(
      id: 'raw_syrup',
      name: 'Pandan Syrup',
      category: 'Syrup',
      currentStock: 4.5,
      unit: 'bottle',
      minSafetyStock: 2.0,
      minThreshold: 5.0,
      costPerUnit: 25000,
    );

    // currentStock (4.5) <= minThreshold (5.0) -> isLowStock == true
    expect(raw.isLowStock, true);

    final restocked = raw.copyWith(currentStock: 12.0);
    expect(restocked.isLowStock, false);
  });

  test('Customer Order Tracker Token and URL isolation', () {
    final token = PosTransaction.generateTrackingToken();
    expect(token.length, 16);
    expect(RegExp(r'^[a-zA-Z0-9]{16}$').hasMatch(token), true);

    final calc = ReceiptCalculation(
      items: [],
      taxPercent: 10,
      servicePercent: 0,
      subtotal: 50000,
      taxAmount: 5000,
      serviceAmount: 0,
      grandTotal: 55000,
      amountPaid: 60000,
      changeAmount: 5000,
      paymentMethod: 'Midtrans QRIS',
      orderMode: 'Take Away',
      orderNotes: '',
      timestamp: DateTime.now(),
      queueNumber: '#007',
      trackingToken: 'abc123XYZ456test',
    );

    final url = calc.buildTrackerUrl('TX-999');
    expect(url.contains('https://nusantara-hybrid-pos.web.app/?trackOrder=TX-999'), true);
    expect(url.contains('token=abc123XYZ456test'), true);
    expect(url.contains('queue=007'), true);
  });

  test('MenuAvailabilityNotifier strict priority and real-time state propagation', () {
    final notifier = MenuAvailabilityNotifier();

    const emptyStockMap = <String, RawMaterial>{};
    const fullStockMap = {
      'raw_kopi': RawMaterial(
        id: 'raw_kopi',
        name: 'Kopi',
        category: 'Kopi',
        currentStock: 1000,
        unit: 'g',
        minSafetyStock: 10,
        costPerUnit: 100,
      ),
    };

    const item = MenuItem(
      id: 'menu_kopi_aren',
      name: 'Kopi Susu Gula Aren',
      category: 'Minuman',
      price: 20000,
      description: 'Test coffee',
      recipe: {'raw_kopi': 15},
    );

    // 1. Auto mode: with empty stock -> Sold Out
    expect(notifier.getOverride(item), MenuOverrideState.auto);
    expect(notifier.isItemSoldOut(item, emptyStockMap), true);
    expect(notifier.isItemReady(item, emptyStockMap), false);

    // With full stock -> Ready
    expect(notifier.isItemSoldOut(item, fullStockMap), false);
    expect(notifier.isItemReady(item, fullStockMap), true);

    // 2. Force Ready mode: Even with empty stock, item must be ready and available
    notifier.value = {'menu_kopi_aren': MenuOverrideState.forceReady};
    expect(notifier.getOverride(item), MenuOverrideState.forceReady);
    expect(notifier.isItemSoldOut(item, emptyStockMap), false);
    expect(notifier.isItemReady(item, emptyStockMap), true);

    // 3. Force Sold Out mode: Even with full stock, item must be sold out
    notifier.value = {'menu_kopi_aren': MenuOverrideState.forceSoldOut};
    expect(notifier.getOverride(item), MenuOverrideState.forceSoldOut);
    expect(notifier.isItemSoldOut(item, fullStockMap), true);
    expect(notifier.isItemReady(item, fullStockMap), false);

    // 4. Name fallback matching: check lowercase trimmed name match
    notifier.value = {'kopi susu gula aren': MenuOverrideState.forceReady};
    expect(notifier.getOverride(item), MenuOverrideState.forceReady);
    expect(notifier.isItemReady(item, emptyStockMap), true);

    // Reset
    notifier.value = {};
  });

  test('MenuCatalogService instant synchronous item mutations and name updates', () async {
    final catalog = MenuCatalogService();
    await catalog.init();

    final initialCount = catalog.items.length;
    expect(initialCount > 0, true);

    // 1. Add new item
    const newItem = MenuItem(
      id: 'menu_test_special',
      name: 'Nasi Bakar Cakalang',
      nameEn: 'Smoked Tuna Roasted Rice',
      category: 'Makanan',
      price: 35000,
      description: 'Aromatic roasted rice',
    );
    await catalog.saveMenuItem(newItem);
    expect(catalog.items.any((m) => m.id == 'menu_test_special'), true);
    final saved = catalog.items.firstWhere((m) => m.id == 'menu_test_special');
    expect(saved.name, 'Nasi Bakar Cakalang');

    // 2. Edit item name and price
    final editedItem = saved.copyWith(name: 'Nasi Bakar Cakalang Pedas Juara', price: 38000);
    await catalog.saveMenuItem(editedItem);
    final updated = catalog.items.firstWhere((m) => m.id == 'menu_test_special');
    expect(updated.name, 'Nasi Bakar Cakalang Pedas Juara');
    expect(updated.price, 38000);

    // 3. Delete item
    await catalog.deleteMenuItem('menu_test_special');
    expect(catalog.items.any((m) => m.id == 'menu_test_special'), false);
  });

  test('PosState reacts dynamically to SettingsService tax and service charge changes', () {
    final settings = SettingsService();
    final pos = PosState();
    pos.clearCart();

    const sampleItem = MenuItem(
      id: 'test_item',
      name: 'Test Coffee',
      category: 'Minuman',
      price: 50000,
      description: '',
    );
    pos.addToCart(sampleItem, quantity: 2); // Subtotal = 100,000

    expect(pos.subtotal, 100000.0);

    // Set initial rates: tax 10%, service 5%
    settings.updateStoreProfile(
      storeName: 'Test Nusantara Store',
      storeTagline: 'Test Tagline',
      storeAddress: 'Test Address',
      storePhone: '12345',
      receiptFooter: 'Test Footer',
      taxRate: 10.0,
      serviceChargeRate: 5.0,
    );

    // Service = 100,000 * 5% = 5,000
    expect(pos.serviceCharge, 5000.0);
    // Tax = (100,000 + 5,000) * 10% = 10,500
    expect(pos.tax, 10500.0);
    // Grand Total = 115,500
    expect(pos.total, 115500.0);

    // Change rates dynamically in Settings
    settings.updateStoreProfile(
      storeName: 'Nusantara POS Updated',
      storeTagline: 'Test Tagline',
      storeAddress: 'Test Address',
      storePhone: '12345',
      receiptFooter: 'Test Footer',
      taxRate: 11.0, // 11% PPN
      serviceChargeRate: 0.0, // 0% service
    );

    // Subtotal remains 100,000
    expect(pos.subtotal, 100000.0);
    // Service charge updates dynamically to 0
    expect(pos.serviceCharge, 0.0);
    // Tax updates dynamically to 100,000 * 11% = 11,000
    expect(pos.tax, 11000.0);
    // Grand total updates to 111,000
    expect(pos.total, 111000.0);

    pos.clearCart();
  });

  test('AiService natural order parser handles renamed and custom items with token matching', () async {
    final ai = AiService();

    const customItems = [
      MenuItem(
        id: 'menu_kopi_aren',
        name: 'Kopi Susu Gula Aren Super',
        category: 'Minuman',
        price: 22000,
        description: '',
      ),
      MenuItem(
        id: 'menu_bakery_croissant',
        name: 'Butter Croissant Premium French',
        category: 'Cemilan',
        price: 24000,
        description: '',
      ),
    ];

    final result = await ai.parseNaturalOrder(
      prompt: '2 kopi aren less ice, 1 croissant, cash 100k',
      menuItems: customItems,
      rawStockMap: {},
      mode: InferenceMode.onlyOnDevice,
    );

    expect(result.items.isNotEmpty, true);
    final coffee = result.items.firstWhere((i) => i.menuItem.id == 'menu_kopi_aren');
    expect(coffee.quantity, 2);
    expect(coffee.notes, 'Less ice');

    final croissant = result.items.firstWhere((i) => i.menuItem.id == 'menu_bakery_croissant');
    expect(croissant.quantity, 1);
    expect(result.cashReceived, 100000.0);
  });

  test('Receipt QR Tracker URL and PosTransaction schema with customer details', () {
    final calc = ReceiptCalculation(
      items: [],
      taxPercent: 10,
      servicePercent: 0,
      subtotal: 50000,
      taxAmount: 5000,
      serviceAmount: 0,
      grandTotal: 55000,
      amountPaid: 60000,
      changeAmount: 5000,
      paymentMethod: 'Cash',
      orderMode: 'Dine In',
      orderNotes: '',
      timestamp: DateTime.now(),
      queueNumber: '#015',
      customerPhone: '08123456789',
      customerName: 'Budi Santoso',
      trackingToken: 'tokenSecret12345',
    );

    // Online cloud URL
    final cloudUrl = calc.buildTrackerUrl('TX-20261124-001', isOffline: false);
    expect(cloudUrl.contains('https://nusantara-hybrid-pos.web.app/?trackOrder=TX-20261124-001'), true);
    expect(cloudUrl.contains('token=tokenSecret12345'), true);
    expect(cloudUrl.contains('queue=015'), true);

    // Offline LAN URL with local IP & tenant isolation
    final lanUrl = calc.buildTrackerUrl('TX-20261124-001', isOffline: true, localIp: '192.168.1.50');
    expect(lanUrl, 'http://192.168.1.50:8765/track?order=TX-20261124-001&tenant=default_store&token=tokenSecret12345&queue=015&eta=10');

    // PosTransaction map serialization & deserialization preserving customerPhone and customerName
    final tx = PosTransaction(
      id: 'TX-20261124-001',
      timestamp: DateTime(2026, 11, 24, 16, 0),
      items: [],
      subtotal: 50000,
      tax: 5000,
      total: 55000,
      paymentMethod: 'Cash',
      cashReceived: 60000,
      changeAmount: 5000,
      queueNumber: '#015',
      customerPhone: '08123456789',
      customerName: 'Budi Santoso',
      trackingToken: 'tokenSecret12345',
    );

    final map = tx.toMap();
    expect(map['customerPhone'], '08123456789');
    expect(map['customerName'], 'Budi Santoso');
    expect(map['trackingToken'], 'tokenSecret12345');
    expect(map['kitchenStatus'], 'preparing');

    final restored = PosTransaction.fromMap(map, 'TX-20261124-001');
    expect(restored.id, 'TX-20261124-001');
    expect(restored.customerPhone, '08123456789');
    expect(restored.customerName, 'Budi Santoso');
    expect(restored.trackingToken, 'tokenSecret12345');
  });

  test('CustomerSessionService 1-time login auto-save and state persistence', () async {
    final session = CustomerSessionService();
    // Default pre-authenticated auto-save state
    expect(session.isLoggedIn, true);
    expect(session.phone.isNotEmpty, true);
    expect(session.name.isNotEmpty, true);

    // Update profile
    await session.updateProfile(newName: 'Dewi Lestari', newPhone: '081987654321');
    expect(session.name, 'Dewi Lestari');
    expect(session.phone.contains('081987654321') || session.phone.contains('81987654321'), true);
    expect(session.isLoggedIn, true);

    // Explicit logout
    await session.logout();
    expect(session.isLoggedIn, false);

    // 1-time login auto-save again
    await session.login(phone: '081234567890', name: 'Budi Santoso');
    expect(session.isLoggedIn, true);
    expect(session.name, 'Budi Santoso');
  });

  test('WhatsAppGatewayService builds order alarm messages with live tracker URL and PNG QR', () async {
    final tx = PosTransaction(
      id: 'TX-WA-001',
      timestamp: DateTime(2026, 11, 25, 9, 0),
      items: const [],
      subtotal: 40000,
      tax: 4000,
      total: 44000,
      paymentMethod: 'Cash',
      cashReceived: 50000,
      changeAmount: 6000,
      queueNumber: '#008',
      customerPhone: '6281234567890',
      customerName: 'Siti',
      kitchenStatus: 'cooking',
      trackingToken: 'waToken123456789',
    );

    final confirmMsg = WhatsAppGatewayService.buildOrderConfirmationMessage(
      order: tx,
      storeName: 'Nusantara Café',
      customerName: 'Siti',
    );
    expect(confirmMsg.contains('#008'), true);
    expect(confirmMsg.contains('COOKING IN KITCHEN'), true);
    expect(confirmMsg.contains('https://nusantara-hybrid-pos.web.app/?trackOrder=TX-WA-001'), true);

    final cookingMsg = WhatsAppGatewayService.buildOrderCookingMessage(
      order: tx,
      storeName: 'Nusantara Café',
      customerName: 'Siti',
    );
    expect(cookingMsg.contains('BEING COOKED'), true);
    expect(cookingMsg.contains('#008'), true);

    final readyMsg = WhatsAppGatewayService.buildOrderReadyMessage(
      order: tx,
      storeName: 'Nusantara Café',
      customerName: 'Siti',
    );
    expect(readyMsg.contains('READY FOR PICKUP'), true);
    expect(readyMsg.contains('#008'), true);
    expect(readyMsg.contains('QR'), false);

    final qrBytes = await WhatsAppGatewayService.generateQrPngBytes(tx.trackerUrl);
    expect(qrBytes != null && qrBytes.length > 100, true);
    // PNG magic bytes: 0x89 0x50 0x4E 0x47
    expect(qrBytes![0], 0x89);
    expect(qrBytes[1], 0x50);
    expect(qrBytes[2], 0x4E);
    expect(qrBytes[3], 0x47);
  });

  test('EmailAuthService OTP generation, verification, and sender default mnurmiyaty2@gmail.com', () async {
    final auth = EmailAuthService();
    expect(auth.senderEmail, 'mnurmiyaty2@gmail.com');
    expect(EmailAuthService.isValidEmail('kasir@nusantara.id'), true);
    expect(EmailAuthService.isValidEmail('invalid-email'), false);

    final res = await auth.requestOtp(recipientEmail: 'kasir@nusantara.id');
    expect(res.success, true);
    expect(res.devPreviewCode != null && res.devPreviewCode!.length == 6, true);

    final wrongVerify = await auth.verifyOtp(email: 'kasir@nusantara.id', code: '000000');
    expect(wrongVerify, false);
    expect(auth.isLoggedIn, false);

    final okVerify = await auth.verifyOtp(
      email: 'kasir@nusantara.id',
      code: res.devPreviewCode!,
      name: 'Nurmiyaty',
    );
    expect(okVerify, true);
    expect(auth.isLoggedIn, true);
    expect(auth.loggedInEmail, 'kasir@nusantara.id');
    expect(auth.loggedInName, 'Nurmiyaty');
    expect(auth.tenantId, 'kasir_nusantara_id');
    expect(EmailAuthService.scopedKey('offline_transactions_json'), 'offline_transactions_json_kasir_nusantara_id');

    await auth.logout();
    expect(auth.isLoggedIn, false);
    expect(auth.tenantId, 'default_store');
  });
}
