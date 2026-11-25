import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'email_auth_service.dart';

class OfflineOutboxService extends ChangeNotifier {
  static final OfflineOutboxService _instance = OfflineOutboxService._internal();
  factory OfflineOutboxService() => _instance;
  OfflineOutboxService._internal();

  static const String _kOutboxKey = 'offline_transactions_json';

  final List<Map<String, dynamic>> _queue = [];
  bool _isSyncing = false;

  List<Map<String, dynamic>> get queue => List.unmodifiable(_queue);
  int get pendingCount => _queue.length;
  bool get hasPending => _queue.isNotEmpty;
  bool get isSyncing => _isSyncing;

  Future<void> init() async {
    await reloadForTenant();
    try {
      // Auto-sync whenever device reconnects to internet
      ConnectivityService().isOnlineNotifier.addListener(_onConnectivityChanged);

      // If already online at startup, attempt initial sync
      if (ConnectivityService().isOnline && hasPending) {
        syncPendingOutbox();
      }
    } catch (e) {
      debugPrint('[OfflineOutbox] Init error: $e');
    }
  }

  Future<void> reloadForTenant() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(EmailAuthService.scopedKey(_kOutboxKey));
      _queue.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _queue.add(item);
          } else if (item is Map) {
            _queue.add(Map<String, dynamic>.from(item));
          }
        }
      }
      notifyListeners();
      debugPrint('[OfflineOutbox] Loaded ${_queue.length} pending offline transactions for tenant ${EmailAuthService().tenantId}.');
    } catch (e) {
      debugPrint('[OfflineOutbox] Reload error: $e');
    }
  }

  void _onConnectivityChanged() {
    if (ConnectivityService().isOnline && hasPending && !_isSyncing) {
      debugPrint('[OfflineOutbox] Device back online. Triggering auto-sync...');
      syncPendingOutbox();
    }
  }

  /// Queues an offline transaction into SharedPreferences JSON queue
  Future<void> queueOfflineTransaction(Map<String, dynamic> txJson) async {
    try {
      _queue.add(txJson);
      await _persistQueue();
      notifyListeners();
      debugPrint('[OfflineOutbox] Queued transaction ${txJson['id']}. Queue size: ${_queue.length}');
    } catch (e) {
      debugPrint('[OfflineOutbox] Failed to queue transaction: $e');
    }
  }

  Future<void> _persistQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_queue);
    await prefs.setString(EmailAuthService.scopedKey(_kOutboxKey), encoded);
  }

  /// Flushes all pending transactions to Firestore
  Future<void> syncPendingOutbox() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final txCollection = EmailAuthService.tenantCollection('transactions');

      final itemsToSync = List<Map<String, dynamic>>.from(_queue);

      for (final tx in itemsToSync) {
        final docId = tx['id']?.toString() ?? txCollection.doc().id;
        final docRef = txCollection.doc(docId);

        final syncPayload = Map<String, dynamic>.from(tx);
        syncPayload['syncedFromOfflineJson'] = true;
        syncPayload['syncedAt'] = DateTime.now().toIso8601String();

        await docRef.set(syncPayload, SetOptions(merge: true));
        _queue.removeWhere((item) => item['id'] == docId);
      }

      await _persistQueue();
      debugPrint('[OfflineOutbox] Successfully synced all pending offline transactions.');
    } catch (e) {
      debugPrint('[OfflineOutbox] Error during sync: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Formatted JSON payload for hackathon judges to inspect in Settings
  String getFormattedJsonLog() {
    if (_queue.isEmpty) {
      return jsonEncode({
        'status': 'ALL_SYNCED',
        'pending_count': 0,
        'message': 'No offline transactions queued. All orders synchronized with Cloud Firestore.',
      });
    }
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_queue);
  }

  Future<void> clearQueue() async {
    _queue.clear();
    await _persistQueue();
    notifyListeners();
  }
}
