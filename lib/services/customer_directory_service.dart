import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'email_auth_service.dart';

class CustomerProfileRecord {
  final String phone;
  final String name;
  final int totalOrders;
  final double totalSpend;
  final bool promoOptIn;
  final String lastOrderAt;

  const CustomerProfileRecord({
    required this.phone,
    required this.name,
    this.totalOrders = 0,
    this.totalSpend = 0.0,
    this.promoOptIn = true,
    this.lastOrderAt = '',
  });

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'name': name,
        'totalOrders': totalOrders,
        'totalSpend': totalSpend,
        'promoOptIn': promoOptIn,
        'lastOrderAt': lastOrderAt,
      };

  factory CustomerProfileRecord.fromMap(Map<String, dynamic> map) {
    return CustomerProfileRecord(
      phone: map['phone']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Pelanggan',
      totalOrders: (map['totalOrders'] as num?)?.toInt() ?? 0,
      totalSpend: (map['totalSpend'] as num?)?.toDouble() ?? 0.0,
      promoOptIn: map['promoOptIn'] != false,
      lastOrderAt: map['lastOrderAt']?.toString() ?? '',
    );
  }
}

/// Local-First Customer Database with automatic & on-demand Cloud Firebase Backup.
/// All customer records are stored locally per email tenant in SharedPreferences,
/// and mirrored to Cloud Firestore `/tenants/{tenantId}/customers` when online.
class CustomerDirectoryService extends ChangeNotifier {
  static final CustomerDirectoryService _instance = CustomerDirectoryService._internal();
  factory CustomerDirectoryService() => _instance;
  CustomerDirectoryService._internal();

  static const String _kLocalCustomersKey = 'local_customers_directory_v1';

  final Map<String, CustomerProfileRecord> _customers = {};
  bool _initialized = false;

  List<CustomerProfileRecord> get customers => _customers.values.toList();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await reloadForTenant();
  }

  Future<void> reloadForTenant() async {
    _customers.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(EmailAuthService.scopedKey(_kLocalCustomersKey));
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final rec = CustomerProfileRecord.fromMap(item);
            if (rec.phone.isNotEmpty) _customers[rec.phone] = rec;
          } else if (item is Map) {
            final rec = CustomerProfileRecord.fromMap(Map<String, dynamic>.from(item));
            if (rec.phone.isNotEmpty) _customers[rec.phone] = rec;
          }
        }
      }
    } catch (e) {
      debugPrint('[CustomerDirectory] Load error: $e');
    }
    notifyListeners();
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _customers.values.map((c) => c.toMap()).toList();
      await prefs.setString(EmailAuthService.scopedKey(_kLocalCustomersKey), jsonEncode(list));
    } catch (e) {
      debugPrint('[CustomerDirectory] Save error: $e');
    }
  }

  /// Saves/updates customer locally first, then backs up to Cloud Firestore if online.
  Future<void> recordCustomerOrder({
    required String phone,
    required String name,
    required double orderTotal,
    bool syncToCloud = true,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length < 9) return;

    final existing = _customers[cleanPhone];
    final resolvedName = (name.trim().isNotEmpty && name.trim() != 'Pelanggan')
        ? name.trim()
        : (existing?.name ?? 'Pelanggan');

    final updated = CustomerProfileRecord(
      phone: cleanPhone,
      name: resolvedName,
      totalOrders: (existing?.totalOrders ?? 0) + 1,
      totalSpend: (existing?.totalSpend ?? 0.0) + orderTotal,
      promoOptIn: existing?.promoOptIn ?? true,
      lastOrderAt: DateTime.now().toIso8601String(),
    );

    _customers[cleanPhone] = updated;
    await _saveToLocal();
    notifyListeners();

    if (syncToCloud && ConnectivityService().isOnline) {
      try {
        await EmailAuthService.tenantCollection('customers').doc(cleanPhone).set({
          ...updated.toMap(),
          'lastOrderAtServer': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Replaces/merges local customers from a cloud restore snapshot.
  Future<void> mergeFromCloud(List<CustomerProfileRecord> cloudList) async {
    for (final rec in cloudList) {
      if (rec.phone.isNotEmpty) {
        _customers[rec.phone] = rec;
      }
    }
    await _saveToLocal();
    notifyListeners();
  }
}
