import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'email_auth_service.dart';
import 'whatsapp_gateway_service.dart';

/// Manages persistent single-sign-on (SSO) session for Role 4: Pembeli (Customer Tracker & Loyalty).
/// Ensures customers only ever log in ONCE; sessions are automatically saved and restored
/// across role switches, restarts, and offline operation with ZERO UI flicker.
class CustomerSessionService extends ChangeNotifier {
  static final CustomerSessionService _instance = CustomerSessionService._internal();
  factory CustomerSessionService() => _instance;
  CustomerSessionService._internal();

  static const String _kLoggedInPhone = 'customer_logged_in_phone';
  static const String _kLoggedInName = 'customer_logged_in_name';
  static const String _kHasLoggedOut = 'customer_has_logged_out';

  // Synchronous in-memory cache to guarantee zero delay/flashing on widget construction
  static String cachedPhone = '081234567890';
  static String cachedName = 'Budi Santoso';
  static bool hasExplicitlyLoggedOut = false;
  static bool _initialized = false;

  String get phone => cachedPhone;
  String get name => cachedName;
  bool get isLoggedIn => !hasExplicitlyLoggedOut && cachedPhone.isNotEmpty;

  int totalOrders = 0;
  double totalSpend = 0.0;
  bool promoOptIn = true;

  /// Loads saved customer session or initializes a healthy pre-authenticated profile on first launch
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLoggedOut = prefs.getBool(_kHasLoggedOut) ?? false;
      final savedPhone = prefs.getString(_kLoggedInPhone);
      final savedName = prefs.getString(_kLoggedInName);

      if (savedLoggedOut) {
        hasExplicitlyLoggedOut = true;
      } else if (savedPhone != null && savedPhone.isNotEmpty) {
        cachedPhone = savedPhone;
        cachedName = (savedName != null && savedName.isNotEmpty) ? savedName : 'Budi Santoso';
        hasExplicitlyLoggedOut = false;
      } else {
        // Auto-seed ready default customer account so customer role is logged in 1-time by default
        cachedPhone = '081234567890';
        cachedName = 'Budi Santoso';
        hasExplicitlyLoggedOut = false;
        await prefs.setString(_kLoggedInPhone, cachedPhone);
        await prefs.setString(_kLoggedInName, cachedName);
        await prefs.setBool(_kHasLoggedOut, false);
      }
      notifyListeners();

      if (isLoggedIn) {
        fetchCustomerData(cachedPhone);
      }
    } catch (e) {
      debugPrint('[CustomerSession] Init error: $e');
    }
  }

  /// Logs in customer, saves to persistent storage, and syncs profile to Firestore
  Future<void> login({required String phone, required String name}) async {
    final cleanPhone = WhatsAppGatewayService.formatPhoneNumber(phone.trim());
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'Pelanggan';

    cachedPhone = cleanPhone;
    cachedName = cleanName;
    hasExplicitlyLoggedOut = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLoggedInPhone, cleanPhone);
      await prefs.setString(_kLoggedInName, cleanName);
      await prefs.setBool(_kHasLoggedOut, false);
    } catch (_) {}

    notifyListeners();

    // Persist to Cloud Firestore in background (tenant-scoped)
    try {
      EmailAuthService.tenantCollection('customers').doc(cleanPhone).set({
        'phone': cleanPhone,
        'name': cleanName,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'promoOptIn': true,
      }, SetOptions(merge: true));
    } catch (_) {}

    fetchCustomerData(cleanPhone);
  }

  /// Updates profile information (name or phone) and auto-saves immediately
  Future<void> updateProfile({required String newName, String? newPhone}) async {
    if (newName.trim().isNotEmpty) {
      cachedName = newName.trim();
    }
    if (newPhone != null && newPhone.trim().isNotEmpty) {
      cachedPhone = WhatsAppGatewayService.formatPhoneNumber(newPhone.trim());
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLoggedInPhone, cachedPhone);
      await prefs.setString(_kLoggedInName, cachedName);
      await prefs.setBool(_kHasLoggedOut, false);
    } catch (_) {}

    notifyListeners();

    try {
      EmailAuthService.tenantCollection('customers').doc(cachedPhone).set({
        'phone': cachedPhone,
        'name': cachedName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Explicit customer logout
  Future<void> logout() async {
    hasExplicitlyLoggedOut = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHasLoggedOut, true);
    } catch (_) {}
    notifyListeners();
  }

  /// Fetches loyalty metrics from Firestore
  void fetchCustomerData(String phone) {
    try {
      EmailAuthService.tenantCollection('customers').doc(phone).get().then((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          totalOrders = (data['totalOrders'] as num?)?.toInt() ?? totalOrders;
          totalSpend = (data['totalSpend'] as num?)?.toDouble() ?? totalSpend;
          promoOptIn = data['promoOptIn'] == true;
          if (data['name'] != null && data['name'].toString().isNotEmpty) {
            cachedName = data['name'].toString();
          }
          notifyListeners();
        }
      }).catchError((_) {});
    } catch (_) {}
  }
}
