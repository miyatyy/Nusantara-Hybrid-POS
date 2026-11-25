import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/raw_material.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/transaction_model.dart';
import '../models/procurement_log.dart';
import '../models/expense_model.dart';
import 'email_auth_service.dart';
import 'offline_outbox_service.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference get _rawMaterialsRef => EmailAuthService.tenantCollection('raw_materials');
  CollectionReference get _menuItemsRef => EmailAuthService.tenantCollection('menu_items');
  CollectionReference get _transactionsRef => EmailAuthService.tenantCollection('transactions');
  CollectionReference get _procurementRef => EmailAuthService.tenantCollection('procurement_logs');
  CollectionReference get _expensesRef => EmailAuthService.tenantCollection('expenses');

  // Helper to resolve verified default food & beverage images by keyword and category
  static String resolveDefaultImageUrl(String name, String category) {
    final n = name.toLowerCase();
    final c = category.toLowerCase();

    if (n.contains('aren') || n.contains('kopi') || n.contains('latte') || n.contains('coffee')) {
      return 'https://images.unsplash.com/photo-1517256064527-09c73fc73e38?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('espresso')) {
      return 'https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('matcha')) {
      return 'https://images.unsplash.com/photo-1536256263959-770b48d82b0a?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('teh') || n.contains('tea')) {
      return 'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('ayam') || n.contains('chicken') || n.contains('matah')) {
      return 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('nasgor') || n.contains('goreng') || n.contains('rice')) {
      return 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('croissant') || n.contains('bakery') || n.contains('roti')) {
      return 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=600&auto=format&fit=crop&q=80';
    } else if (n.contains('pisang') || n.contains('fritter') || n.contains('snack')) {
      return 'https://images.unsplash.com/photo-1528751014936-863e6e7a319c?w=600&auto=format&fit=crop&q=80';
    } else if (c.contains('paket') || n.contains('paket') || n.contains('combo') || n.contains('bundle')) {
      return 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=600&auto=format&fit=crop&q=80';
    } else if (c.contains('minuman') || c.contains('drink')) {
      return 'https://images.unsplash.com/photo-1497636577773-f1231844b336?w=600&auto=format&fit=crop&q=80';
    } else if (c.contains('cemilan') || c.contains('snack')) {
      return 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=600&auto=format&fit=crop&q=80';
    } else {
      return 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&auto=format&fit=crop&q=80';
    }
  }

  // Stream of raw materials
  Stream<List<RawMaterial>> streamRawMaterials() {
    return _rawMaterialsRef.snapshots().map((snap) {
      return snap.docs
          .map((doc) => RawMaterial.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Stream of menu items with automatic patch for missing image URLs
  Stream<List<MenuItem>> streamMenuItems() {
    return _menuItemsRef.snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        var item = MenuItem.fromMap(data, doc.id);

        // Auto-patch existing documents if imageUrl is missing or empty
        if (item.imageUrl.isEmpty) {
          final patchedUrl = resolveDefaultImageUrl(item.name, item.category);
          item = item.copyWith(imageUrl: patchedUrl);
          // Persist back to Firestore asynchronously
          _menuItemsRef.doc(doc.id).update({'imageUrl': patchedUrl}).catchError((_) {});
        }

        return item;
      }).toList();
    });
  }

  // Stream of transactions
  Stream<List<PosTransaction>> streamTransactions() {
    return _transactionsRef
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => PosTransaction.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Stream of procurement logs
  Stream<List<ProcurementLog>> streamProcurementLogs() {
    return _procurementRef
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => ProcurementLog.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Stream of business expenses
  Stream<List<ExpenseModel>> streamExpenses() {
    return _expensesRef
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => ExpenseModel.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  // Add new business expense
  Future<void> addExpense(ExpenseModel expense) async {
    final docRef = expense.id.isNotEmpty
        ? _expensesRef.doc(expense.id)
        : _expensesRef.doc();
    final data = ExpenseModel(
      id: docRef.id,
      title: expense.title,
      category: expense.category,
      amount: expense.amount,
      timestamp: expense.timestamp,
      loggedBy: expense.loggedBy,
      referenceId: expense.referenceId,
    ).toMap();
    await docRef.set(data, SetOptions(merge: true));
  }

  // Deduct raw materials recipe stock atomically on POS checkout
  Future<String> checkoutOrder({
    required List<OrderItem> items,
    required double subtotal,
    required double tax,
    required double total,
    required String paymentMethod,
    required double cashReceived,
    required double changeAmount,
    required String aiSource,
    double serviceAmount = 0.0,
    String orderMode = 'Dine In',
    String orderNotes = '',
    String cashierName = 'Nurmiyaty',
    String shiftLabel = 'Morning Shift',
    String shiftHours = '07:00 - 15:00',
    bool isOffline = false,
    String queueNumber = '#001',
    String customerPhone = '',
    String customerName = 'Pelanggan',
    String? customOrderId,
    String? trackingToken,
  }) async {
    // 1. Record transaction
    final newTxRef = customOrderId != null && customOrderId.isNotEmpty
        ? _transactionsRef.doc(customOrderId)
        : _transactionsRef.doc();
    final orderId = newTxRef.id;

    final prepMinutes = (items.fold<int>(0, (acc, it) => acc + it.quantity) * 3 + 4).clamp(5, 30);
    final effectiveToken = (trackingToken != null && trackingToken.isNotEmpty)
        ? trackingToken
        : PosTransaction.generateTrackingToken();

    final txData = {
      'id': orderId,
      'timestamp': DateTime.now().toIso8601String(),
      'items': items.map((i) => i.toMap()).toList(),
      'subtotal': subtotal.round(),
      'tax': tax.round(),
      'serviceAmount': serviceAmount.round(),
      'total': total.round(),
      'grandTotal': total.round(),
      'paymentMethod': paymentMethod,
      'cashReceived': cashReceived.round(),
      'amountPaid': cashReceived.round(),
      'changeAmount': changeAmount.round(),
      'aiSource': aiSource,
      'orderMode': orderMode,
      'orderNotes': orderNotes,
      'cashierName': cashierName,
      'shiftLabel': shiftLabel,
      'shiftHours': shiftHours,
      'queueNumber': queueNumber,
      'customerPhone': customerPhone,
      'customerName': customerName,
      'kitchenStatus': 'preparing',
      'estimatedPrepMinutes': prepMinutes,
      'trackingToken': effectiveToken,
      'isOffline': isOffline,
    };
    // 1. Write the transaction document to Firestore with high priority
    try {
      await newTxRef.set(txData).timeout(const Duration(milliseconds: 2500));
    } catch (e) {
      debugPrint('Firestore checkout document applied locally/offline outbox: $e');
      OfflineOutboxService().queueOfflineTransaction(txData);
    }

    if (isOffline) {
      OfflineOutboxService().queueOfflineTransaction(txData);
    }

    // 2. Aggregate raw material deductions across items
    final Map<String, double> deductions = {};
    for (final orderItem in items) {
      final recipe = orderItem.menuItem.recipe;
      recipe.forEach((matId, qtyPerPortion) {
        final totalNeeded = qtyPerPortion * orderItem.quantity;
        deductions[matId] = (deductions[matId] ?? 0.0) + totalNeeded;
      });
    }

    // 3. Apply FieldValue.increment(-deduction) to each raw material safely
    if (deductions.isNotEmpty) {
      try {
        final stockBatch = _db.batch();
        deductions.forEach((matId, qty) {
          final matRef = _rawMaterialsRef.doc(matId);
          stockBatch.update(matRef, {
            'currentStock': FieldValue.increment(-qty),
          });
        });
        await stockBatch.commit().timeout(const Duration(milliseconds: 2000));
      } catch (e) {
        debugPrint('Raw material inventory deduction notice: $e');
      }
    }

    return orderId;
  }

  /// Updates the customer WhatsApp number on an existing order in Firestore.
  Future<void> updateOrderCustomerPhone(String orderId, String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    try {
      await _transactionsRef
          .doc(orderId)
          .update({'customerPhone': clean}).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // Update kitchen status ('preparing', 'cooking', 'ready', 'completed')
  Future<void> updateKitchenStatus(String orderId, String newStatus) async {
    try {
      final updateData = <String, dynamic>{
        'kitchenStatus': newStatus,
      };
      if (newStatus == 'ready') {
        updateData['readyAt'] = DateTime.now().toIso8601String();
      }
      if (newStatus == 'completed') {
        updateData['completedAt'] = DateTime.now().toIso8601String();
      }
      await _transactionsRef.doc(orderId).update(updateData);
    } catch (e) {
      debugPrint('Failed to update kitchen status: $e');
    }
  }

  // Update manual availability override on Firestore document
  Future<void> updateMenuAvailabilityOverride({
    required String menuItemId,
    required bool isManualSoldOut,
    required bool forceManualReady,
  }) async {
    if (menuItemId.trim().isEmpty) return;
    await _menuItemsRef.doc(menuItemId.trim()).set({
      'isManualSoldOut': isManualSoldOut,
      'forceManualReady': forceManualReady,
      'isAvailable': !isManualSoldOut,
    }, SetOptions(merge: true)).catchError((e) {
      debugPrint('Failed to update availability override: $e');
    });
  }

  // Add or update menu item (e.g. 1-Click "Publish Bundle to POS")
  Future<void> saveMenuItem(MenuItem item) async {
    final docRef = item.id.isNotEmpty ? _menuItemsRef.doc(item.id) : _menuItemsRef.doc();
    String effectiveImageUrl = item.imageUrl;
    if (effectiveImageUrl.isEmpty) {
      effectiveImageUrl = resolveDefaultImageUrl(item.name, item.category);
    }
    final data = item.copyWith(id: docRef.id, imageUrl: effectiveImageUrl).toMap();
    await docRef.set(data, SetOptions(merge: true));
  }

  // Delete menu item
  Future<void> deleteMenuItem(String id) async {
    await _menuItemsRef.doc(id).delete();
  }

  // Add raw material
  Future<void> saveRawMaterial(RawMaterial material) async {
    final docRef = material.id.isNotEmpty
        ? _rawMaterialsRef.doc(material.id)
        : _rawMaterialsRef.doc();
    final data = material.copyWith(id: docRef.id).toMap();
    await docRef.set(data, SetOptions(merge: true));
  }

  // Log supplier restock and increment raw material stock
  Future<void> logProcurementRestock({
    required String rawMaterialId,
    required String rawMaterialName,
    required double quantityAdded,
    required String unit,
    required double costTotal,
    required String supplier,
  }) async {
    final batch = _db.batch();
    final logRef = _procurementRef.doc();

    final log = ProcurementLog(
      id: logRef.id,
      rawMaterialId: rawMaterialId,
      rawMaterialName: rawMaterialName,
      quantityAdded: quantityAdded,
      unit: unit,
      costTotal: costTotal,
      supplier: supplier,
      timestamp: DateTime.now(),
    );
    batch.set(logRef, log.toMap());

    final matRef = _rawMaterialsRef.doc(rawMaterialId);
    batch.update(matRef, {
      'currentStock': FieldValue.increment(quantityAdded),
    });

    // Automatically record procurement restock as an Expense
    final expRef = _expensesRef.doc();
    final expense = ExpenseModel(
      id: expRef.id,
      title: 'Restock $rawMaterialName ($quantityAdded $unit)',
      category: 'Restock',
      amount: costTotal,
      timestamp: DateTime.now(),
      loggedBy: 'Procurement ($supplier)',
      referenceId: logRef.id,
    );
    batch.set(expRef, expense.toMap());

    await batch.commit();
  }

  // Seed initial demo data if collections are empty
  // Public Static Seed Lists for instant cold-start and offline catalog display
  static const List<RawMaterial> defaultSeedRawMaterials = [
    RawMaterial(
      id: 'raw_espresso',
      name: 'Biji Kopi House Blend (Arabika/Robusta)',
      category: 'Kopi',
      currentStock: 2500,
      unit: 'g',
      minSafetyStock: 500,
      costPerUnit: 250,
    ),
    RawMaterial(
      id: 'raw_milk',
      name: 'Susu Fresh Milk Pasteurisasi',
      category: 'Dairy',
      currentStock: 8000,
      unit: 'ml',
      minSafetyStock: 2000,
      costPerUnit: 25,
    ),
    RawMaterial(
      id: 'raw_palm_sugar',
      name: 'Sirup Gula Aren Organik',
      category: 'Pemanis',
      currentStock: 3000,
      unit: 'ml',
      minSafetyStock: 800,
      costPerUnit: 40,
    ),
    RawMaterial(
      id: 'raw_matcha',
      name: 'Bubuk Matcha Kyoto Asli',
      category: 'Teh',
      currentStock: 900,
      unit: 'g',
      minSafetyStock: 200,
      costPerUnit: 450,
    ),
    RawMaterial(
      id: 'raw_tea_leaves',
      name: 'Daun Teh Hitam Premium Melati',
      category: 'Teh',
      currentStock: 1500,
      unit: 'g',
      minSafetyStock: 300,
      costPerUnit: 80,
    ),
    RawMaterial(
      id: 'raw_croissant_dough',
      name: 'Butter Croissant Raw Dough',
      category: 'Bakery',
      currentStock: 30,
      unit: 'pcs',
      minSafetyStock: 8,
      costPerUnit: 12000,
    ),
    RawMaterial(
      id: 'raw_rice',
      name: 'Beras Pandan Wangi Cianjur',
      category: 'Dapur',
      currentStock: 10000,
      unit: 'g',
      minSafetyStock: 2500,
      costPerUnit: 18,
    ),
    RawMaterial(
      id: 'raw_chicken',
      name: 'Daging Ayam Fillet Dada',
      category: 'Dapur',
      currentStock: 4500,
      unit: 'g',
      minSafetyStock: 1000,
      costPerUnit: 65,
    ),
    RawMaterial(
      id: 'raw_sambal',
      name: 'Bumbu Sambal Matah Bali',
      category: 'Dapur',
      currentStock: 1500,
      unit: 'g',
      minSafetyStock: 300,
      costPerUnit: 55,
    ),
    RawMaterial(
      id: 'raw_banana',
      name: 'Pisang Kepok Kuning',
      category: 'Cemilan',
      currentStock: 45,
      unit: 'pcs',
      minSafetyStock: 12,
      costPerUnit: 2500,
    ),
  ];

  static const List<MenuItem> defaultSeedMenuItems = [
    MenuItem(
      id: 'menu_kopi_aren',
      name: 'Kopi Susu Gula Aren',
      nameEn: 'Palm Sugar Iced Latte',
      category: 'Minuman',
      price: 22000,
      description: 'Espresso bold with velvety fresh milk and organic palm sugar.',
      recipe: {'raw_espresso': 18, 'raw_milk': 120, 'raw_palm_sugar': 25},
      iconEmoji: '☕',
      popularityScore: 98,
      imageUrl: 'https://images.unsplash.com/photo-1517256064527-09c73fc73e38?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_espresso',
      name: 'Espresso Double Shot',
      nameEn: 'Double Espresso',
      category: 'Minuman',
      price: 18000,
      description: 'Rich and aromatic double extraction espresso.',
      recipe: {'raw_espresso': 20},
      iconEmoji: '☕',
      popularityScore: 75,
      imageUrl: 'https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_matcha_latte',
      name: 'Kyoto Matcha Latte',
      nameEn: 'Kyoto Matcha Latte',
      category: 'Minuman',
      price: 26000,
      description: 'Authentic ceremonial grade matcha with steamed milk.',
      recipe: {'raw_matcha': 15, 'raw_milk': 150},
      iconEmoji: '🍵',
      popularityScore: 88,
      imageUrl: 'https://images.unsplash.com/photo-1536256263959-770b48d82b0a?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_iced_tea',
      name: 'Es Teh Melati Nusantara',
      nameEn: 'Iced Jasmine Tea',
      category: 'Minuman',
      price: 12000,
      description: 'Traditional slow-brewed fragrant jasmine iced tea.',
      recipe: {'raw_tea_leaves': 10},
      iconEmoji: '🧋',
      popularityScore: 92,
      imageUrl: 'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_ayam_matah',
      name: 'Nasi Ayam Sambal Matah',
      nameEn: 'Rice with Balinese Crispy Chicken',
      category: 'Makanan',
      price: 36000,
      description: 'Fragrant steamed rice, crispy spiced chicken, fresh shallot lemongrass sambal.',
      recipe: {'raw_rice': 150, 'raw_chicken': 120, 'raw_sambal': 30},
      iconEmoji: '🍛',
      popularityScore: 95,
      imageUrl: 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_nasgor_spesial',
      name: 'Nasi Goreng Nusantara Special',
      nameEn: 'Nusantara Fried Rice Special',
      category: 'Makanan',
      price: 32000,
      description: 'Wok-tossed Indonesian fried rice with shredded chicken and pickles.',
      recipe: {'raw_rice': 180, 'raw_chicken': 80},
      iconEmoji: '🍳',
      popularityScore: 89,
      imageUrl: 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_croissant',
      name: 'Butter Croissant Crispy',
      nameEn: 'Crispy Butter Croissant',
      category: 'Cemilan',
      price: 24000,
      description: 'Golden flaky French butter pastry baked fresh daily.',
      recipe: {'raw_croissant_dough': 1},
      iconEmoji: '🥐',
      popularityScore: 84,
      imageUrl: 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'menu_pisang_goreng',
      name: 'Pisang Goreng Madu Wijen',
      nameEn: 'Caramelized Honey Banana Fritters',
      category: 'Cemilan',
      price: 18000,
      description: 'Crispy sweet banana fritters glazed with blossom honey and toasted sesame.',
      recipe: {'raw_banana': 2},
      iconEmoji: '🍌',
      popularityScore: 82,
      imageUrl: 'https://images.unsplash.com/photo-1528751014936-863e6e7a319c?w=600&auto=format&fit=crop&q=80',
    ),
    MenuItem(
      id: 'bundle_sarapan',
      name: 'Paket Semangat Pagi (Kopi Aren + Croissant)',
      nameEn: 'Morning Combo (Palm Sugar Latte + Croissant)',
      category: 'Paket',
      price: 39000,
      description: 'Special breakfast combo: 1 Palm Sugar Latte and 1 flaky Butter Croissant.',
      recipe: {
        'raw_espresso': 18,
        'raw_milk': 120,
        'raw_palm_sugar': 25,
        'raw_croissant_dough': 1,
      },
      iconEmoji: '⭐',
      popularityScore: 97,
      imageUrl: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=600&auto=format&fit=crop&q=80',
    ),
  ];

  Future<void> seedInitialDataIfEmpty() async {
    try {
      // Check and seed initial expenses if empty
      await _seedInitialExpensesIfEmpty();

      final rawSnap = await _rawMaterialsRef.limit(1).get();
      if (rawSnap.docs.isNotEmpty) {
        debugPrint('Firestore already seeded. Checking for missing imageUrl fields...');
        // Auto-patch any existing menu items missing imageUrl
        final menuDocs = await _menuItemsRef.get();
        final batch = _db.batch();
        bool needsCommit = false;
        for (final doc in menuDocs.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['imageUrl'] == null || data['imageUrl'].toString().isEmpty) {
            final name = data['name']?.toString() ?? '';
            final cat = data['category']?.toString() ?? '';
            final url = resolveDefaultImageUrl(name, cat);
            batch.update(doc.reference, {'imageUrl': url});
            needsCommit = true;
          }
        }
        if (needsCommit) {
          await batch.commit();
          debugPrint('Successfully patched missing imageUrl on existing Firestore documents.');
        }
        return;
      }

      debugPrint('Seeding initial Nusantara Hybrid POS data with food/drink photography...');
      final batch = _db.batch();

      // 1. Raw materials
      for (final r in defaultSeedRawMaterials) {
        batch.set(_rawMaterialsRef.doc(r.id), r.toMap());
      }

      // 2. Menu Items with verified high-quality food photography
      for (final m in defaultSeedMenuItems) {
        batch.set(_menuItemsRef.doc(m.id), m.toMap());
      }

      // 3. Six past realistic transactions
      final now = DateTime.now();
      final sampleTxs = [
        PosTransaction(
          id: 'TX-1001',
          timestamp: now.subtract(const Duration(hours: 5)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[0], quantity: 2), // 2 Kopi Aren
            OrderItem(menuItem: defaultSeedMenuItems[6], quantity: 1), // 1 Croissant
          ],
          subtotal: 68000,
          tax: 6800,
          total: 74800,
          paymentMethod: 'QRIS',
          cashReceived: 74800,
          changeAmount: 0,
          aiSource: 'IN_CLOUD',
        ),
        PosTransaction(
          id: 'TX-1002',
          timestamp: now.subtract(const Duration(hours: 4, minutes: 15)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[4], quantity: 2), // 2 Nasi Ayam Matah
            OrderItem(menuItem: defaultSeedMenuItems[3], quantity: 2), // 2 Teh Melati
          ],
          subtotal: 96000,
          tax: 9600,
          total: 105600,
          paymentMethod: 'Cash',
          cashReceived: 110000,
          changeAmount: 4400,
          aiSource: 'ON_DEVICE',
        ),
        PosTransaction(
          id: 'TX-1003',
          timestamp: now.subtract(const Duration(hours: 3)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[8], quantity: 1), // 1 Paket Sarapan
            OrderItem(menuItem: defaultSeedMenuItems[2], quantity: 1), // 1 Matcha Latte
          ],
          subtotal: 65000,
          tax: 6500,
          total: 71500,
          paymentMethod: 'Card',
          cashReceived: 71500,
          changeAmount: 0,
          aiSource: 'ON_DEVICE',
        ),
        PosTransaction(
          id: 'TX-1004',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 30)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[0], quantity: 3), // 3 Kopi Aren
            OrderItem(menuItem: defaultSeedMenuItems[7], quantity: 2), // 2 Pisang Goreng
          ],
          subtotal: 102000,
          tax: 10200,
          total: 112200,
          paymentMethod: 'QRIS',
          cashReceived: 112200,
          changeAmount: 0,
          aiSource: 'IN_CLOUD',
        ),
        PosTransaction(
          id: 'TX-1005',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 45)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[5], quantity: 1), // 1 Nasgor Spesial
            OrderItem(menuItem: defaultSeedMenuItems[0], quantity: 1), // 1 Kopi Aren
          ],
          subtotal: 54000,
          tax: 5400,
          total: 59400,
          paymentMethod: 'Cash',
          cashReceived: 60000,
          changeAmount: 600,
          aiSource: 'MANUAL',
        ),
        PosTransaction(
          id: 'TX-1006',
          timestamp: now.subtract(const Duration(minutes: 40)),
          items: [
            OrderItem(menuItem: defaultSeedMenuItems[8], quantity: 2), // 2 Paket Sarapan
          ],
          subtotal: 78000,
          tax: 7800,
          total: 85800,
          paymentMethod: 'QRIS',
          cashReceived: 85800,
          changeAmount: 0,
          aiSource: 'ON_DEVICE',
        ),
      ];

      for (final tx in sampleTxs) {
        batch.set(_transactionsRef.doc(tx.id), tx.toMap());
      }

      await batch.commit();
      debugPrint('Firestore seed complete with 10 raw materials, 9 menus with photos, and 6 transactions.');
    } catch (e) {
      debugPrint('Firestore seeding error: $e');
    }
  }

  // Seed sample expenses across daily, weekly, and monthly ranges if empty
  Future<void> _seedInitialExpensesIfEmpty() async {
    try {
      final snap = await _expensesRef.limit(1).get();
      if (snap.docs.isNotEmpty) return;

      final now = DateTime.now();
      final sampleExpenses = [
        ExpenseModel(
          id: 'EXP-101',
          title: 'Restock Biji Kopi Arabika 2kg',
          category: 'Restock',
          amount: 350000,
          timestamp: now.subtract(const Duration(hours: 8)),
          loggedBy: 'Nurmiyaty',
        ),
        ExpenseModel(
          id: 'EXP-102',
          title: 'Susu Fresh Milk Pasteurisasi 10L',
          category: 'Restock',
          amount: 180000,
          timestamp: now.subtract(const Duration(days: 1, hours: 2)),
          loggedBy: 'Rina Sari',
        ),
        ExpenseModel(
          id: 'EXP-103',
          title: 'Paper Cup & Sedotan Ramah Lingkungan',
          category: 'Packaging',
          amount: 120000,
          timestamp: now.subtract(const Duration(days: 2, hours: 4)),
          loggedBy: 'Nurmiyaty',
        ),
        ExpenseModel(
          id: 'EXP-104',
          title: 'Gas LPG & Galon Air Minum',
          category: 'Operational',
          amount: 85000,
          timestamp: now.subtract(const Duration(days: 4)),
          loggedBy: 'Budi Santoso',
        ),
        ExpenseModel(
          id: 'EXP-105',
          title: 'Restock Bubuk Matcha & Sirup Gula Aren',
          category: 'Restock',
          amount: 420000,
          timestamp: now.subtract(const Duration(days: 9)),
          loggedBy: 'Nurmiyaty',
        ),
        ExpenseModel(
          id: 'EXP-106',
          title: 'Tagihan Listrik & WiFi IndiHome',
          category: 'Operational',
          amount: 450000,
          timestamp: now.subtract(const Duration(days: 15)),
          loggedBy: 'Nurmiyaty',
        ),
        ExpenseModel(
          id: 'EXP-107',
          title: 'Gaji Mingguan Barista & Staff',
          category: 'Wages',
          amount: 1250000,
          timestamp: now.subtract(const Duration(days: 22)),
          loggedBy: 'Owner',
        ),
        ExpenseModel(
          id: 'EXP-108',
          title: 'Restock Bahan Dapur & Daging Ayam',
          category: 'Restock',
          amount: 580000,
          timestamp: now.subtract(const Duration(days: 35)),
          loggedBy: 'Rina Sari',
        ),
        ExpenseModel(
          id: 'EXP-109',
          title: 'Maintenance Mesin Kopi Espresso',
          category: 'Other',
          amount: 250000,
          timestamp: now.subtract(const Duration(days: 50)),
          loggedBy: 'Owner',
        ),
        ExpenseModel(
          id: 'EXP-110',
          title: 'Gaji Bulanan Staff Periode Lalu',
          category: 'Wages',
          amount: 1500000,
          timestamp: now.subtract(const Duration(days: 75)),
          loggedBy: 'Owner',
        ),
      ];

      final batch = _db.batch();
      for (final exp in sampleExpenses) {
        batch.set(_expensesRef.doc(exp.id), exp.toMap());
      }
      await batch.commit();
      debugPrint('[FirestoreService] Seeded 10 sample expense records for Daily, Weekly, and Monthly financial charts.');
    } catch (e) {
      debugPrint('[FirestoreService] Error seeding sample expenses: $e');
    }
  }
}
