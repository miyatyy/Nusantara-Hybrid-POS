import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_smtp_helper.dart';

class OtpDispatchResult {
  final bool success;
  final bool sentViaGmail;
  final String? devPreviewCode;
  final String message;

  const OtpDispatchResult({
    required this.success,
    required this.sentViaGmail,
    this.devPreviewCode,
    required this.message,
  });
}

/// Manages unified Email + OTP authentication for all operational roles
/// (Kasir, Dapur Kanban, Pembeli, Hardware Hub, Store Operations).
/// Note: Layar Antrian (Queue Display) is intentionally exempt and remains public without login.
class EmailAuthService extends ChangeNotifier {
  static final EmailAuthService _instance = EmailAuthService._internal();
  factory EmailAuthService() => _instance;
  EmailAuthService._internal();

  static const String _kLoggedInEmail = 'pos_auth_logged_in_email';
  static const String _kLoggedInName = 'pos_auth_logged_in_name';
  static const String _kSenderEmail = 'pos_auth_sender_gmail';
  static const String _kGmailAppPassword = 'pos_auth_gmail_app_password';

  static const String defaultSenderEmail = 'mnurmiyaty2@gmail.com';

  String _loggedInEmail = '';
  String _loggedInName = '';
  String _senderEmail = defaultSenderEmail;
  String _gmailAppPassword = '';

  String? _pendingOtpEmail;
  String? _pendingOtpCode;
  DateTime? _pendingOtpExpiry;
  bool _initialized = false;

  String get loggedInEmail => _loggedInEmail;
  String get loggedInName => _loggedInName;
  String get senderEmail => _senderEmail;
  String get gmailAppPassword => _gmailAppPassword;
  bool get isLoggedIn => _loggedInEmail.isNotEmpty;
  bool get hasGmailAppPassword => _gmailAppPassword.replaceAll(' ', '').trim().length >= 16;

  /// Sanitized per-account tenant ID derived from logged-in email
  /// (e.g. `mnurmiyaty2@gmail.com` -> `mnurmiyaty2_gmail_com`).
  String get tenantId {
    if (_loggedInEmail.isEmpty) return 'default_store';
    return _loggedInEmail.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  /// Tenant-isolated Cloud Firestore collection under `tenants/{tenantId}/{collectionName}`.
  static CollectionReference<Map<String, dynamic>> tenantCollection(String collectionName) {
    final tid = EmailAuthService().tenantId;
    return FirebaseFirestore.instance.collection('tenants').doc(tid).collection(collectionName);
  }

  /// Tenant-scoped SharedPreferences key so local server & offline cache are isolated per account.
  static String scopedKey(String baseKey) {
    return '${baseKey}_${EmailAuthService().tenantId}';
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _loggedInEmail = prefs.getString(_kLoggedInEmail) ?? '';
      _loggedInName = prefs.getString(_kLoggedInName) ?? '';
      final savedSender = prefs.getString(_kSenderEmail);
      if (savedSender != null && savedSender.trim().isNotEmpty) {
        _senderEmail = savedSender.trim();
      }
      _gmailAppPassword = prefs.getString(_kGmailAppPassword) ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('[EmailAuthService] Init error: $e');
    }
  }

  Future<void> saveGmailConfig({
    required String senderEmail,
    required String appPassword,
  }) async {
    _senderEmail = senderEmail.trim().isNotEmpty ? senderEmail.trim() : defaultSenderEmail;
    _gmailAppPassword = appPassword.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSenderEmail, _senderEmail);
      await prefs.setString(_kGmailAppPassword, _gmailAppPassword);
    } catch (_) {}
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }

  /// Generates a 6-digit OTP and dispatches it via Gmail SMTP (`mnurmiyaty2@gmail.com`).
  Future<OtpDispatchResult> requestOtp({
    required String recipientEmail,
    String storeName = 'Nusantara Hybrid POS',
  }) async {
    final cleanEmail = recipientEmail.trim().toLowerCase();
    if (!isValidEmail(cleanEmail)) {
      return const OtpDispatchResult(
        success: false,
        sentViaGmail: false,
        message: 'Invalid email format.',
      );
    }

    final rnd = math.Random.secure();
    final code = (100000 + rnd.nextInt(900000)).toString();
    _pendingOtpEmail = cleanEmail;
    _pendingOtpCode = code;
    _pendingOtpExpiry = DateTime.now().add(const Duration(minutes: 5));

    if (hasGmailAppPassword) {
      final sent = await EmailSmtpHelper.sendGmailOtp(
        senderEmail: _senderEmail,
        appPassword: _gmailAppPassword,
        recipientEmail: cleanEmail,
        otpCode: code,
        storeName: storeName,
      );
      if (sent) {
        return OtpDispatchResult(
          success: true,
          sentViaGmail: true,
          message: 'OTP code sent from $_senderEmail to $cleanEmail. Please check Inbox/Spam.',
        );
      } else {
        return OtpDispatchResult(
          success: true,
          sentViaGmail: false,
          devPreviewCode: code,
          message: 'Failed to send via SMTP $_senderEmail (check 16-digit App Password / connection). Use preview code: $code',
        );
      }
    }

    // App Password not configured yet: return safe preview code so testing is never blocked
    return OtpDispatchResult(
      success: true,
      sentViaGmail: false,
      devPreviewCode: code,
      message: 'Gmail App Password for $_senderEmail is not set. Preview OTP Code: $code',
    );
  }

  /// Verifies 6-digit OTP and persists 1-time auto-save login session.
  Future<bool> verifyOtp({
    required String email,
    required String code,
    String name = '',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanCode = code.trim();

    if (_pendingOtpEmail != cleanEmail || _pendingOtpCode == null || _pendingOtpExpiry == null) {
      return false;
    }
    if (DateTime.now().isAfter(_pendingOtpExpiry!)) {
      return false;
    }
    if (_pendingOtpCode != cleanCode) {
      return false;
    }

    final resolvedName = name.trim().isNotEmpty
        ? name.trim()
        : cleanEmail.split('@').first;

    _loggedInEmail = cleanEmail;
    _loggedInName = resolvedName;
    _pendingOtpCode = null;
    _pendingOtpEmail = null;
    _pendingOtpExpiry = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLoggedInEmail, _loggedInEmail);
      await prefs.setString(_kLoggedInName, _loggedInName);
    } catch (_) {}

    // Register/update tenant metadata in Cloud Firestore for Web Admin Management Portal
    try {
      final docRef = FirebaseFirestore.instance.collection('tenants').doc(tenantId);
      final snap = await docRef.get().timeout(const Duration(seconds: 3));
      final nowIso = DateTime.now().toIso8601String();
      if (!snap.exists) {
        await docRef.set({
          'tenantId': tenantId,
          'ownerEmail': _loggedInEmail,
          'ownerName': _loggedInName,
          'storeName': 'Toko $_loggedInName',
          'status': 'ACTIVE',
          'plan': 'PRO',
          'createdAt': nowIso,
          'lastActiveAt': nowIso,
        });
      } else {
        await docRef.set({
          'ownerEmail': _loggedInEmail,
          'ownerName': _loggedInName,
          'lastActiveAt': nowIso,
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _loggedInEmail = '';
    _loggedInName = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLoggedInEmail);
      await prefs.remove(_kLoggedInName);
    } catch (_) {}
    notifyListeners();
  }
}
