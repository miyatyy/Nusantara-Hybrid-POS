import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/menu_item.dart';
import '../models/transaction_model.dart';
import 'customer_directory_service.dart';
import 'email_auth_service.dart';
import 'local_kitchen_bridge.dart';
import 'menu_catalog_service.dart';
import 'offline_outbox_service.dart';

class BackupResult {
  final bool success;
  final int menuCount;
  final int customerCount;
  final int orderCount;
  final String message;

  const BackupResult({
    required this.success,
    this.menuCount = 0,
    this.customerCount = 0,
    this.orderCount = 0,
    required this.message,
  });
}

/// Manages 1-tap Cloud Firebase Backup & Restore for Local-First POS Databases
/// (Menu Items, Customer Directory, and Offline/Local Transactions) per email tenant.
class CloudBackupService {
  static final CloudBackupService _instance = CloudBackupService._internal();
  factory CloudBackupService() => _instance;
  CloudBackupService._internal();

  /// Backs up all local Menu, Customer, and Order data to Cloud Firestore `/tenants/{tenantId}/...`
  Future<BackupResult> backupLocalToFirebase() async {
    try {
      final tid = EmailAuthService().tenantId;
      final db = FirebaseFirestore.instance;
      final tenantDoc = db.collection('tenants').doc(tid);

      final menus = MenuCatalogService().items;
      final customers = CustomerDirectoryService().customers;
      final orders = LocalKitchenBridge().localOrders;

      final batch = db.batch();

      for (final m in menus) {
        batch.set(tenantDoc.collection('menu_items').doc(m.id), m.toMap(), SetOptions(merge: true));
      }

      for (final c in customers) {
        batch.set(tenantDoc.collection('customers').doc(c.phone), c.toMap(), SetOptions(merge: true));
      }

      for (final o in orders) {
        batch.set(tenantDoc.collection('transactions').doc(o.id), o.toMap(), SetOptions(merge: true));
      }

      batch.set(tenantDoc, {
        'lastBackupAt': DateTime.now().toIso8601String(),
        'backupMenuCount': menus.length,
        'backupCustomerCount': customers.length,
        'backupOrderCount': orders.length,
      }, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 12));
      await OfflineOutboxService().syncPendingOutbox();

      return BackupResult(
        success: true,
        menuCount: menus.length,
        customerCount: customers.length,
        orderCount: orders.length,
        message: 'Firebase backup succeeded: ${menus.length} menu items, ${customers.length} customers, ${orders.length} orders!',
      );
    } catch (e) {
      debugPrint('[CloudBackupService] Backup error: $e');
      return BackupResult(
        success: false,
        message: 'Failed to back up to Cloud Firebase: $e',
      );
    }
  }

  /// Restores Menu, Customer, and Transaction data from Cloud Firestore `/tenants/{tenantId}/...` to Local Storage.
  Future<BackupResult> restoreFromFirebaseToLocal() async {
    try {
      final tid = EmailAuthService().tenantId;
      final tenantDoc = FirebaseFirestore.instance.collection('tenants').doc(tid);

      final snaps = await Future.wait([
        tenantDoc.collection('menu_items').get().timeout(const Duration(seconds: 10)),
        tenantDoc.collection('customers').get().timeout(const Duration(seconds: 10)),
        tenantDoc.collection('transactions').get().timeout(const Duration(seconds: 10)),
      ]);

      final menuDocs = snaps[0].docs;
      final custDocs = snaps[1].docs;
      final txDocs = snaps[2].docs;

      for (final doc in menuDocs) {
        final item = MenuItem.fromMap(doc.data(), doc.id);
        await MenuCatalogService().saveMenuItem(item);
      }

      final custList = custDocs.map((d) => CustomerProfileRecord.fromMap(d.data())).toList();
      await CustomerDirectoryService().mergeFromCloud(custList);

      for (final doc in txDocs) {
        final tx = PosTransaction.fromMap(doc.data(), doc.id);
        await LocalKitchenBridge().registerLocalOrder(tx);
      }

      return BackupResult(
        success: true,
        menuCount: menuDocs.length,
        customerCount: custDocs.length,
        orderCount: txDocs.length,
        message: 'Restore complete: ${menuDocs.length} menu items, ${custDocs.length} customers, ${txDocs.length} orders loaded locally!',
      );
    } catch (e) {
      debugPrint('[CloudBackupService] Restore error: $e');
      return BackupResult(
        success: false,
        message: 'Failed to restore from Cloud Firebase: $e',
      );
    }
  }
}
