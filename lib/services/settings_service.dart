import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_auth_service.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // Keys
  static const String _kMenuOverrides = 'menu_availability_overrides';
  static const String _kStoreName = 'settings_store_name';
  static const String _kStoreTagline = 'settings_store_tagline';
  static const String _kStoreAddress = 'settings_store_address';
  static const String _kStorePhone = 'settings_store_phone';
  static const String _kReceiptFooter = 'settings_receipt_footer';
  static const String _kTaxRate = 'settings_tax_rate';
  static const String _kServiceChargeRate = 'settings_service_charge_rate';
  static const String _kAutoDeduct = 'settings_auto_deduct';
  static const String _kAiStockGuard = 'settings_ai_stock_guard';
  static const String _kEnableCash = 'settings_enable_cash';
  static const String _kEnableQris = 'settings_enable_qris';
  static const String _kEnableCard = 'settings_enable_card';
  static const String _kQrisExpiryMinutes = 'settings_qris_expiry_minutes';
  static const String _kLocalMidtransKey = 'settings_local_midtrans_key';
  static const String _kAiMode = 'settings_ai_mode';

  // State variables with defaults
  String _storeName = 'Nusantara POS Café';
  String _storeTagline = 'Official Hackathon Demo Store';
  String _storeAddress = 'Jl. Malioboro No. 45, Yogyakarta';
  String _storePhone = '+62 812-3456-7890';
  String _receiptFooter = 'Thank You & Please Come Again!';
  double _taxRate = 10.0; // 10% PB1
  double _serviceChargeRate = 5.0; // 5% Service charge
  bool _autoDeductEnabled = true;
  bool _aiStockGuardEnabled = true;
  bool _enableCash = true;
  bool _enableMidtransQris = true;
  bool _enableMidtransCard = true;
  int _qrisExpiryMinutes = 15; // 5, 10, or 15 minutes
  String _localMidtransKey = '';
  String _aiMode = 'preferOnDevice'; // 'preferOnDevice' vs 'onlyInCloud'

  // Getters
  String get storeName => _storeName;
  String get storeTagline => _storeTagline;
  String get storeAddress => _storeAddress;
  String get storePhone => _storePhone;
  String get receiptFooter => _receiptFooter;
  double get taxRate => _taxRate;
  double get serviceChargeRate => _serviceChargeRate;
  bool get autoDeductEnabled => _autoDeductEnabled;
  bool get aiStockGuardEnabled => _aiStockGuardEnabled;
  bool get enableCash => _enableCash;
  bool get enableMidtransQris => _enableMidtransQris;
  bool get enableMidtransCard => _enableMidtransCard;
  int get qrisExpiryMinutes => _qrisExpiryMinutes;
  String get localMidtransKey => _localMidtransKey;
  String get aiMode => _aiMode;

  /// Effective Midtrans Server Key: checks compile-time environment variable first,
  /// then falls back to locally entered Sandbox key in Settings (never saved to Git).
  String get effectiveMidtransServerKey {
    const envKey = String.fromEnvironment('MIDTRANS_SERVER_KEY', defaultValue: '');
    if (envKey.trim().isNotEmpty) return envKey.trim();
    return _localMidtransKey.trim();
  }

  bool get hasMidtransKey => effectiveMidtransServerKey.isNotEmpty;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storeName = prefs.getString(_kStoreName) ?? _storeName;
      _storeTagline = prefs.getString(_kStoreTagline) ?? _storeTagline;
      _storeAddress = prefs.getString(_kStoreAddress) ?? _storeAddress;
      _storePhone = prefs.getString(_kStorePhone) ?? _storePhone;
      _receiptFooter = prefs.getString(_kReceiptFooter) ?? _receiptFooter;
      _taxRate = prefs.getDouble(_kTaxRate) ?? _taxRate;
      _serviceChargeRate = prefs.getDouble(_kServiceChargeRate) ?? _serviceChargeRate;
      _autoDeductEnabled = prefs.getBool(_kAutoDeduct) ?? _autoDeductEnabled;
      _aiStockGuardEnabled = prefs.getBool(_kAiStockGuard) ?? _aiStockGuardEnabled;
      _enableCash = prefs.getBool(_kEnableCash) ?? _enableCash;
      _enableMidtransQris = prefs.getBool(_kEnableQris) ?? _enableMidtransQris;
      _enableMidtransCard = prefs.getBool(_kEnableCard) ?? _enableMidtransCard;
      _qrisExpiryMinutes = prefs.getInt(_kQrisExpiryMinutes) ?? _qrisExpiryMinutes;
      _localMidtransKey = prefs.getString(_kLocalMidtransKey) ?? _localMidtransKey;
      _aiMode = prefs.getString(_kAiMode) ?? _aiMode;
      notifyListeners();

      // Background sync with Cloud Firestore settings document
      FirebaseFirestore.instance
          .collection('settings')
          .doc('store_profile')
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          bool changed = false;
          if (data['storeName'] != null && data['storeName'].toString().isNotEmpty) {
            _storeName = data['storeName'].toString();
            changed = true;
          }
          if (data['storeTagline'] != null) {
            _storeTagline = data['storeTagline'].toString();
            changed = true;
          }
          if (data['storeAddress'] != null) {
            _storeAddress = data['storeAddress'].toString();
            changed = true;
          }
          if (data['storePhone'] != null) {
            _storePhone = data['storePhone'].toString();
            changed = true;
          }
          if (data['receiptFooter'] != null) {
            _receiptFooter = data['receiptFooter'].toString();
            changed = true;
          }
          if (data['taxRate'] != null) {
            _taxRate = (data['taxRate'] as num).toDouble();
            changed = true;
          }
          if (data['serviceChargeRate'] != null) {
            _serviceChargeRate = (data['serviceChargeRate'] as num).toDouble();
            changed = true;
          }
          if (changed) {
            notifyListeners();
          }
        }
      }, onError: (_) {});
    } catch (e) {
      debugPrint('[SettingsService] Init error: $e');
    }
  }

  Future<void> updateStoreProfile({
    required String storeName,
    required String storeTagline,
    required String storeAddress,
    required String storePhone,
    required String receiptFooter,
    required double taxRate,
    required double serviceChargeRate,
  }) async {
    _storeName = storeName;
    _storeTagline = storeTagline;
    _storeAddress = storeAddress;
    _storePhone = storePhone;
    _receiptFooter = receiptFooter;
    _taxRate = taxRate;
    _serviceChargeRate = serviceChargeRate;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStoreName, _storeName);
      await prefs.setString(_kStoreTagline, _storeTagline);
      await prefs.setString(_kStoreAddress, _storeAddress);
      await prefs.setString(_kStorePhone, _storePhone);
      await prefs.setString(_kReceiptFooter, _receiptFooter);
      await prefs.setDouble(_kTaxRate, _taxRate);
      await prefs.setDouble(_kServiceChargeRate, _serviceChargeRate);

      // Also persist to Cloud Firestore asynchronously
      FirebaseFirestore.instance
          .collection('settings')
          .doc('store_profile')
          .set({
        'storeName': _storeName,
        'storeTagline': _storeTagline,
        'storeAddress': _storeAddress,
        'storePhone': _storePhone,
        'receiptFooter': _receiptFooter,
        'taxRate': _taxRate,
        'serviceChargeRate': _serviceChargeRate,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});

      // Sync real store name to tenant record in Web Admin Portal
      EmailAuthService().syncStoreNameToTenant(_storeName);
    } catch (_) {}
  }

  Future<void> setAutoDeduct(bool val) async {
    _autoDeductEnabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoDeduct, val);
  }

  Future<void> setAiStockGuard(bool val) async {
    _aiStockGuardEnabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAiStockGuard, val);
  }

  Future<void> setPaymentChannels({
    required bool cash,
    required bool qris,
    required bool card,
  }) async {
    _enableCash = cash;
    _enableMidtransQris = qris;
    _enableMidtransCard = card;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnableCash, cash);
    await prefs.setBool(_kEnableQris, qris);
    await prefs.setBool(_kEnableCard, card);

    // Sync to Cloud Firestore asynchronously
    FirebaseFirestore.instance
        .collection('settings')
        .doc('payment_channels')
        .set({
      'enableCash': cash,
      'enableQris': qris,
      'enableCard': card,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((_) {});
  }

  Future<void> setQrisExpiryMinutes(int minutes) async {
    _qrisExpiryMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kQrisExpiryMinutes, minutes);
  }

  Future<void> setLocalMidtransKey(String key) async {
    _localMidtransKey = key.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalMidtransKey, _localMidtransKey);
  }

  Future<void> setAiMode(String mode) async {
    _aiMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiMode, mode);
  }

  static const String _kDailyQueueCounter = 'daily_queue_counter';
  static const String _kDailyQueueDate = 'daily_queue_date';

  /// Generates the next sequential queue number (e.g. '#001', '#002', ...)
  /// Resets back to '#001' when date changes.
  Future<String> getNextQueueNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastDate = prefs.getString(_kDailyQueueDate) ?? '';
    int current = prefs.getInt(_kDailyQueueCounter) ?? 0;

    if (lastDate != todayStr) {
      current = 1;
    } else {
      current += 1;
    }

    await prefs.setString(_kDailyQueueDate, todayStr);
    await prefs.setInt(_kDailyQueueCounter, current);
    return '#${current.toString().padLeft(3, '0')}';
  }

  /// Peeks current or next queue number without incrementing
  Future<String> peekNextQueueNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastDate = prefs.getString(_kDailyQueueDate) ?? '';
    int current = prefs.getInt(_kDailyQueueCounter) ?? 0;
    if (lastDate != todayStr) current = 0;
    return '#${(current + 1).toString().padLeft(3, '0')}';
  }

  /// Resets daily queue counter manually
  Future<void> resetQueueNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await prefs.setString(_kDailyQueueDate, todayStr);
    await prefs.setInt(_kDailyQueueCounter, 0);
  }

  /// Load all local menu availability overrides from SharedPreferences
  Future<Map<String, Map<String, bool>>> getMenuAvailabilityOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMenuOverrides);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, Map<String, bool>> result = {};
      decoded.forEach((key, val) {
        if (val is Map) {
          result[key] = {
            'isManualSoldOut': val['isManualSoldOut'] == true,
            'forceManualReady': val['forceManualReady'] == true,
          };
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Save menu availability override to SharedPreferences
  Future<void> setMenuAvailabilityOverride({
    required String menuItemId,
    required bool isManualSoldOut,
    required bool forceManualReady,
  }) async {
    final current = await getMenuAvailabilityOverrides();
    current[menuItemId] = {
      'isManualSoldOut': isManualSoldOut,
      'forceManualReady': forceManualReady,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMenuOverrides, jsonEncode(current));
    notifyListeners();
  }

  /// Clear menu override for an item to restore automatic stock/BOM computation
  Future<void> clearMenuAvailabilityOverride(String menuItemId) async {
    final current = await getMenuAvailabilityOverrides();
    current.remove(menuItemId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMenuOverrides, jsonEncode(current));
    notifyListeners();
  }
}
