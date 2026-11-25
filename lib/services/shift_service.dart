import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cashier_shift.dart';
import '../models/transaction_model.dart';
import 'connectivity_service.dart';
import 'email_auth_service.dart';
import 'offline_outbox_service.dart';

class ShiftService extends ChangeNotifier {
  static final ShiftService _instance = ShiftService._internal();
  factory ShiftService() => _instance;
  ShiftService._internal();

  static const String _kActiveShiftKey = 'active_cashier_shift_session';
  static const String _kRosterKey = 'cashier_roster_list';
  static const String _kShiftHistoryKey = 'cashier_shift_history';
  static const String _kOfflineZReportsKey = 'offline_z_reports_json';

  CashierShiftSession? _currentSession;
  List<CashierEmployee> _roster = [];
  List<CashierShiftSession> _history = [];
  List<ZReportData> _zReports = [];

  CashierShiftSession get currentSession =>
      _currentSession ?? _createDefaultSession();
  List<CashierEmployee> get roster => List.unmodifiable(_roster);
  List<CashierShiftSession> get history => List.unmodifiable(_history);
  List<ZReportData> get zReports => List.unmodifiable(_zReports);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load or Seed Roster
      final rosterJson = prefs.getString(_kRosterKey);
      if (rosterJson != null && rosterJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(rosterJson);
        _roster = list.map((e) => CashierEmployee.fromMap(e as Map<String, dynamic>)).toList();
      } else {
        _roster = _getDefaultRoster();
        await prefs.setString(_kRosterKey, jsonEncode(_roster.map((e) => e.toMap()).toList()));
      }

      // 2. Load or Seed Active Shift Session
      final activeJson = prefs.getString(_kActiveShiftKey);
      if (activeJson != null && activeJson.isNotEmpty) {
        _currentSession = CashierShiftSession.fromJson(activeJson);
      } else {
        _currentSession = _createDefaultSession();
        await prefs.setString(_kActiveShiftKey, _currentSession!.toJson());
      }

      // 3. Load Shift History
      final historyJson = prefs.getString(_kShiftHistoryKey);
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(historyJson);
        _history = list.map((e) => CashierShiftSession.fromMap(e as Map<String, dynamic>)).toList();
      }

      // 4. Load Offline Z-Reports
      final zReportsJson = prefs.getString(_kOfflineZReportsKey);
      if (zReportsJson != null && zReportsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(zReportsJson);
        _zReports = list.map((e) => ZReportData.fromMap(e as Map<String, dynamic>)).toList();
      }

      notifyListeners();

      // 5. Background sync roster & Z-reports to Firestore if online
      _syncRosterToFirestore();
      ConnectivityService().isOnlineNotifier.addListener(_syncPendingZReportsToFirestore);
      if (ConnectivityService().isOnline) {
        _syncPendingZReportsToFirestore();
      }
    } catch (e) {
      debugPrint('[ShiftService] init notice: $e');
      _currentSession = _createDefaultSession();
    }
  }

  Future<void> _syncPendingZReportsToFirestore() async {
    if (!ConnectivityService().isOnline || _zReports.isEmpty) return;
    try {
      final db = EmailAuthService.tenantCollection('z_reports');
      bool updated = false;
      for (int i = 0; i < _zReports.length; i++) {
        if (!_zReports[i].syncedToFirestore) {
          await db.doc(_zReports[i].reportId).set(_zReports[i].toMap(), SetOptions(merge: true));
          _zReports[i] = _zReports[i].copyWith(syncedToFirestore: true);
          updated = true;
        }
      }
      if (updated) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kOfflineZReportsKey, jsonEncode(_zReports.map((e) => e.toMap()).toList()));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ShiftService] Sync Z-reports notice: $e');
    }
  }

  List<CashierEmployee> _getDefaultRoster() {
    return const [
      CashierEmployee(
        id: 'emp_1',
        name: 'Nurmiyaty',
        role: 'Lead Cashier',
        defaultShiftLabel: 'Morning Shift',
        startTime: '07:00',
        endTime: '15:00',
        pin: '1234',
      ),
      CashierEmployee(
        id: 'emp_2',
        name: 'Rina Sari',
        role: 'Barista & Cashier',
        defaultShiftLabel: 'Afternoon Shift',
        startTime: '15:00',
        endTime: '23:00',
        pin: '2345',
      ),
      CashierEmployee(
        id: 'emp_3',
        name: 'Budi Santoso',
        role: 'Weekend Cashier',
        defaultShiftLabel: 'Full Day Shift',
        startTime: '09:00',
        endTime: '21:00',
        pin: '3456',
      ),
    ];
  }

  CashierShiftSession _createDefaultSession() {
    final now = DateTime.now();
    final todayMorning = DateTime(now.year, now.month, now.day, 7, 0);
    return CashierShiftSession(
      id: 'SHIFT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-01',
      cashierId: 'emp_1',
      cashierName: 'Nurmiyaty',
      role: 'Lead Cashier',
      shiftLabel: 'Morning Shift',
      shiftHours: '07:00 - 15:00',
      startTime: todayMorning.isBefore(now) ? todayMorning : now,
      openingCash: 200000, // Rp 200.000 modal awal laci kasir
      status: 'ACTIVE',
    );
  }

  /// Calculates dynamic live metrics for the current active shift based on transactions
  CashierShiftSession calculateSessionMetrics(List<PosTransaction> allTransactions, [int? actualCashCounted]) {
    final session = currentSession;
    final start = session.startTime;

    // Filter transactions created during this active shift
    final shiftTxs = allTransactions.where((tx) => tx.timestamp.isAfter(start)).toList();

    int totalOrders = shiftTxs.length;
    int grossSales = 0;
    int cashSales = 0;
    int nonCashSales = 0;

    for (final tx in shiftTxs) {
      final total = tx.total.round();
      grossSales += total;
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash') || method.contains('tunai')) {
        cashSales += total;
      } else {
        nonCashSales += total;
      }
    }

    final expectedCash = session.openingCash + cashSales;
    final variance = actualCashCounted != null ? (actualCashCounted - expectedCash) : null;

    return session.copyWith(
      totalOrders: totalOrders,
      grossSales: grossSales,
      cashSales: cashSales,
      nonCashSales: nonCashSales,
      expectedCash: expectedCash,
      closingCash: actualCashCounted,
      variance: variance,
    );
  }

  /// Calculates a complete Z-Report merging both live Firestore and local offline outbox JSON
  ZReportData calculateZReportData({
    required List<PosTransaction> transactions,
    required int actualCash,
    required String storeName,
    String aiSummary = '',
    String? nextCashierName,
  }) {
    final session = currentSession;
    final start = session.startTime;
    final now = DateTime.now();

    // 1. Gather and deduplicate transactions across online & offline
    final Map<String, PosTransaction> mergedTxs = {};
    for (final tx in transactions) {
      if (tx.timestamp.isAfter(start)) {
        mergedTxs[tx.id] = tx;
      }
    }

    final outbox = OfflineOutboxService().queue;
    for (final item in outbox) {
      try {
        final id = item['id']?.toString() ?? '';
        final tsStr = item['timestamp']?.toString() ?? '';
        final ts = DateTime.tryParse(tsStr) ?? now;
        if (ts.isAfter(start)) {
          if (!mergedTxs.containsKey(id)) {
            final tx = PosTransaction.fromMap(item, id);
            mergedTxs[id] = tx;
          }
        }
      } catch (_) {}
    }

    final shiftTxs = mergedTxs.values.toList();
    final outboxIds = outbox.map((e) => e['id']?.toString()).toSet();

    int grossSales = 0;
    int cashSales = 0;
    int nonCashSales = 0;
    int taxAndServiceTotal = 0;
    int offlineCount = 0;
    int onlineCount = 0;

    for (final tx in shiftTxs) {
      final total = tx.total.round();
      grossSales += total;
      final taxAmt = tx.tax.round();
      taxAndServiceTotal += taxAmt;

      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash') || method.contains('tunai')) {
        cashSales += total;
      } else {
        nonCashSales += total;
      }

      if (outboxIds.contains(tx.id) || tx.aiSource == 'OFFLINE') {
        offlineCount++;
      } else {
        onlineCount++;
      }
    }

    final totalOrders = shiftTxs.length;
    final expectedCash = session.openingCash + cashSales;
    final variance = actualCash - expectedCash;

    final reportId = 'ZRP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    return ZReportData(
      storeName: storeName,
      reportId: reportId,
      cashierName: session.cashierName,
      role: session.role,
      shiftLabel: session.shiftLabel,
      shiftHours: session.shiftHours,
      startTime: session.startTime,
      endTime: now,
      totalOrders: totalOrders,
      onlineOrderCount: onlineCount,
      offlineOrderCount: offlineCount,
      grossSales: grossSales,
      taxAndServiceTotal: taxAndServiceTotal,
      cashSales: cashSales,
      nonCashSales: nonCashSales,
      openingCash: session.openingCash,
      expectedCash: expectedCash,
      actualCash: actualCash,
      variance: variance,
      aiSummary: aiSummary.isNotEmpty ? aiSummary : session.handoverNotes,
      nextCashierName: nextCashierName ?? session.nextCashierName,
      createdAt: now,
      syncedToFirestore: false,
    );
  }

  /// Closes the active shift, saves the Z-Report to local JSON and syncs to Firestore
  Future<ZReportData> saveZReportAndCloseShift({
    required ZReportData report,
    required List<PosTransaction> transactions,
    String notes = '',
    String? nextCashierName,
  }) async {
    // 1. Always save to Local JSON first (100% offline-first reliability)
    final bool isOnline = ConnectivityService().isOnline;
    final ZReportData toSave = report.copyWith(syncedToFirestore: isOnline);

    _zReports.insert(0, toSave);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kOfflineZReportsKey, jsonEncode(_zReports.map((e) => e.toMap()).toList()));

      // 2. Dual persistence: sync to Firestore if online
      if (isOnline) {
        await EmailAuthService.tenantCollection('z_reports').doc(toSave.reportId).set(toSave.toMap());
      }
    } catch (e) {
      debugPrint('[ShiftService] saveZReport error: $e');
    }

    // 3. Close the active shift session
    await closeShift(
      transactions: transactions,
      actualCashCounted: report.actualCash,
      notes: notes.isNotEmpty ? notes : report.aiSummary,
      nextCashierName: nextCashierName,
    );

    return toSave;
  }

  /// Closes the active shift and saves it to history
  Future<CashierShiftSession> closeShift({
    required List<PosTransaction> transactions,
    required int actualCashCounted,
    String notes = '',
    String? nextCashierName,
  }) async {
    final computed = calculateSessionMetrics(transactions, actualCashCounted);
    final closed = computed.copyWith(
      endTime: DateTime.now(),
      closingCash: actualCashCounted,
      notes: notes,
      nextCashierName: nextCashierName,
      status: 'CLOSED',
    );

    _history.insert(0, closed);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kShiftHistoryKey, jsonEncode(_history.map((e) => e.toMap()).toList()));
      // Also persist to Firestore
      if (ConnectivityService().isOnline) {
        EmailAuthService.tenantCollection('shift_sessions').doc(closed.id).set(closed.toMap());
      }
    } catch (e) {
      debugPrint('[ShiftService] closeShift persist notice: $e');
    }

    return closed;
  }

  /// Starts a new shift session for an incoming cashier
  Future<void> startShift({
    required CashierEmployee employee,
    required String shiftLabel,
    required String shiftHours,
    required int openingCash,
  }) async {
    final now = DateTime.now();
    final newId = 'SHIFT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(7)}';

    _currentSession = CashierShiftSession(
      id: newId,
      cashierId: employee.id,
      cashierName: employee.name,
      role: employee.role,
      shiftLabel: shiftLabel,
      shiftHours: shiftHours,
      startTime: now,
      openingCash: openingCash,
      status: 'ACTIVE',
    );

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveShiftKey, _currentSession!.toJson());

      if (ConnectivityService().isOnline) {
        EmailAuthService.tenantCollection('shift_sessions').doc(newId).set(_currentSession!.toMap());
      }
    } catch (e) {
      debugPrint('[ShiftService] startShift persist notice: $e');
    }
  }

  /// Adds a new cashier employee to the roster
  Future<void> addEmployee(CashierEmployee emp) async {
    _roster.add(emp);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRosterKey, jsonEncode(_roster.map((e) => e.toMap()).toList()));

      if (ConnectivityService().isOnline) {
        EmailAuthService.tenantCollection('cashiers').doc(emp.id).set(emp.toMap());
      }
    } catch (e) {
      debugPrint('[ShiftService] addEmployee persist notice: $e');
    }
  }

  void _syncRosterToFirestore() {
    if (!ConnectivityService().isOnline) return;
    try {
      for (final emp in _roster) {
        EmailAuthService.tenantCollection('cashiers').doc(emp.id).set(emp.toMap());
      }
    } catch (_) {}
  }
}
