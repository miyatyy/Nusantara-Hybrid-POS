import 'dart:convert';

class CashierEmployee {
  final String id;
  final String name;
  final String role; // e.g. 'Lead Cashier', 'Barista & Cashier'
  final String defaultShiftLabel; // e.g. 'Morning Shift', 'Afternoon Shift'
  final String startTime; // '07:00'
  final String endTime; // '15:00'
  final String pin; // optional 4-digit PIN

  const CashierEmployee({
    required this.id,
    required this.name,
    required this.role,
    required this.defaultShiftLabel,
    required this.startTime,
    required this.endTime,
    this.pin = '',
  });

  String get shiftHours => '$startTime - $endTime';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'defaultShiftLabel': defaultShiftLabel,
      'startTime': startTime,
      'endTime': endTime,
      'pin': pin,
    };
  }

  factory CashierEmployee.fromMap(Map<String, dynamic> map) {
    return CashierEmployee(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Staff',
      role: map['role']?.toString() ?? 'Cashier',
      defaultShiftLabel: map['defaultShiftLabel']?.toString() ?? 'General Shift',
      startTime: map['startTime']?.toString() ?? '08:00',
      endTime: map['endTime']?.toString() ?? '16:00',
      pin: map['pin']?.toString() ?? '',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CashierEmployee.fromJson(String source) =>
      CashierEmployee.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class CashierShiftSession {
  final String id;
  final String cashierId;
  final String cashierName;
  final String role;
  final String shiftLabel;
  final String shiftHours;
  final DateTime startTime;
  final DateTime? endTime;
  final int openingCash; // Modal awal di laci kasir
  final int? closingCash; // Uang fisik dihitung saat tutup shift
  final int? expectedCash; // openingCash + cashSales
  final int? variance; // closingCash - expectedCash (selisih)
  final int totalOrders;
  final int grossSales;
  final int cashSales;
  final int nonCashSales;
  final String notes;
  final String? nextCashierName;
  final String status; // 'ACTIVE', 'CLOSED'

  const CashierShiftSession({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.role,
    required this.shiftLabel,
    required this.shiftHours,
    required this.startTime,
    this.endTime,
    required this.openingCash,
    this.closingCash,
    this.expectedCash,
    this.variance,
    this.totalOrders = 0,
    this.grossSales = 0,
    this.cashSales = 0,
    this.nonCashSales = 0,
    this.notes = '',
    this.nextCashierName,
    this.status = 'ACTIVE',
  });

  bool get isActive => status == 'ACTIVE';
  String get handoverNotes => notes;

  CashierShiftSession copyWith({
    String? id,
    String? cashierId,
    String? cashierName,
    String? role,
    String? shiftLabel,
    String? shiftHours,
    DateTime? startTime,
    DateTime? endTime,
    int? openingCash,
    int? closingCash,
    int? expectedCash,
    int? variance,
    int? totalOrders,
    int? grossSales,
    int? cashSales,
    int? nonCashSales,
    String? notes,
    String? nextCashierName,
    String? status,
  }) {
    return CashierShiftSession(
      id: id ?? this.id,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      role: role ?? this.role,
      shiftLabel: shiftLabel ?? this.shiftLabel,
      shiftHours: shiftHours ?? this.shiftHours,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      openingCash: openingCash ?? this.openingCash,
      closingCash: closingCash ?? this.closingCash,
      expectedCash: expectedCash ?? this.expectedCash,
      variance: variance ?? this.variance,
      totalOrders: totalOrders ?? this.totalOrders,
      grossSales: grossSales ?? this.grossSales,
      cashSales: cashSales ?? this.cashSales,
      nonCashSales: nonCashSales ?? this.nonCashSales,
      notes: notes ?? this.notes,
      nextCashierName: nextCashierName ?? this.nextCashierName,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'role': role,
      'shiftLabel': shiftLabel,
      'shiftHours': shiftHours,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'openingCash': openingCash,
      'closingCash': closingCash,
      'expectedCash': expectedCash,
      'variance': variance,
      'totalOrders': totalOrders,
      'grossSales': grossSales,
      'cashSales': cashSales,
      'nonCashSales': nonCashSales,
      'notes': notes,
      'nextCashierName': nextCashierName,
      'status': status,
    };
  }

  factory CashierShiftSession.fromMap(Map<String, dynamic> map) {
    return CashierShiftSession(
      id: map['id']?.toString() ?? '',
      cashierId: map['cashierId']?.toString() ?? '',
      cashierName: map['cashierName']?.toString() ?? 'Cashier',
      role: map['role']?.toString() ?? 'Staff',
      shiftLabel: map['shiftLabel']?.toString() ?? 'Standard Shift',
      shiftHours: map['shiftHours']?.toString() ?? '07:00 - 15:00',
      startTime: DateTime.tryParse(map['startTime']?.toString() ?? '') ?? DateTime.now(),
      endTime: map['endTime'] != null ? DateTime.tryParse(map['endTime'].toString()) : null,
      openingCash: (map['openingCash'] as num?)?.toInt() ?? 0,
      closingCash: (map['closingCash'] as num?)?.toInt(),
      expectedCash: (map['expectedCash'] as num?)?.toInt(),
      variance: (map['variance'] as num?)?.toInt(),
      totalOrders: (map['totalOrders'] as num?)?.toInt() ?? 0,
      grossSales: (map['grossSales'] as num?)?.toInt() ?? 0,
      cashSales: (map['cashSales'] as num?)?.toInt() ?? 0,
      nonCashSales: (map['nonCashSales'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString() ?? '',
      nextCashierName: map['nextCashierName']?.toString(),
      status: map['status']?.toString() ?? 'ACTIVE',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CashierShiftSession.fromJson(String source) =>
      CashierShiftSession.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class ZReportData {
  final String storeName;
  final String reportId;
  final String cashierName;
  final String role;
  final String shiftLabel;
  final String shiftHours;
  final DateTime startTime;
  final DateTime endTime;
  final int totalOrders;
  final int onlineOrderCount;
  final int offlineOrderCount;
  final int grossSales;
  final int taxAndServiceTotal;
  final int cashSales;
  final int nonCashSales;
  final int openingCash;
  final int expectedCash;
  final int actualCash;
  final int variance;
  final String aiSummary;
  final String? nextCashierName;
  final DateTime createdAt;
  final bool syncedToFirestore;

  const ZReportData({
    required this.storeName,
    required this.reportId,
    required this.cashierName,
    required this.role,
    required this.shiftLabel,
    required this.shiftHours,
    required this.startTime,
    required this.endTime,
    required this.totalOrders,
    required this.onlineOrderCount,
    required this.offlineOrderCount,
    required this.grossSales,
    required this.taxAndServiceTotal,
    required this.cashSales,
    required this.nonCashSales,
    required this.openingCash,
    required this.expectedCash,
    required this.actualCash,
    required this.variance,
    this.aiSummary = '',
    this.nextCashierName,
    required this.createdAt,
    this.syncedToFirestore = false,
  });

  bool get isBalanced => variance == 0;
  bool get isSurplus => variance > 0;
  String get varianceStatus {
    if (variance == 0) return 'BALANCED';
    return variance > 0 ? 'SURPLUS' : 'DEFICIT';
  }

  ZReportData copyWith({
    String? storeName,
    String? reportId,
    String? cashierName,
    String? role,
    String? shiftLabel,
    String? shiftHours,
    DateTime? startTime,
    DateTime? endTime,
    int? totalOrders,
    int? onlineOrderCount,
    int? offlineOrderCount,
    int? grossSales,
    int? taxAndServiceTotal,
    int? cashSales,
    int? nonCashSales,
    int? openingCash,
    int? expectedCash,
    int? actualCash,
    int? variance,
    String? aiSummary,
    String? nextCashierName,
    DateTime? createdAt,
    bool? syncedToFirestore,
  }) {
    return ZReportData(
      storeName: storeName ?? this.storeName,
      reportId: reportId ?? this.reportId,
      cashierName: cashierName ?? this.cashierName,
      role: role ?? this.role,
      shiftLabel: shiftLabel ?? this.shiftLabel,
      shiftHours: shiftHours ?? this.shiftHours,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalOrders: totalOrders ?? this.totalOrders,
      onlineOrderCount: onlineOrderCount ?? this.onlineOrderCount,
      offlineOrderCount: offlineOrderCount ?? this.offlineOrderCount,
      grossSales: grossSales ?? this.grossSales,
      taxAndServiceTotal: taxAndServiceTotal ?? this.taxAndServiceTotal,
      cashSales: cashSales ?? this.cashSales,
      nonCashSales: nonCashSales ?? this.nonCashSales,
      openingCash: openingCash ?? this.openingCash,
      expectedCash: expectedCash ?? this.expectedCash,
      actualCash: actualCash ?? this.actualCash,
      variance: variance ?? this.variance,
      aiSummary: aiSummary ?? this.aiSummary,
      nextCashierName: nextCashierName ?? this.nextCashierName,
      createdAt: createdAt ?? this.createdAt,
      syncedToFirestore: syncedToFirestore ?? this.syncedToFirestore,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'reportId': reportId,
      'cashierName': cashierName,
      'role': role,
      'shiftLabel': shiftLabel,
      'shiftHours': shiftHours,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'totalOrders': totalOrders,
      'onlineOrderCount': onlineOrderCount,
      'offlineOrderCount': offlineOrderCount,
      'grossSales': grossSales,
      'taxAndServiceTotal': taxAndServiceTotal,
      'cashSales': cashSales,
      'nonCashSales': nonCashSales,
      'openingCash': openingCash,
      'expectedCash': expectedCash,
      'actualCash': actualCash,
      'variance': variance,
      'aiSummary': aiSummary,
      'nextCashierName': nextCashierName,
      'createdAt': createdAt.toIso8601String(),
      'syncedToFirestore': syncedToFirestore,
    };
  }

  factory ZReportData.fromMap(Map<String, dynamic> map) {
    return ZReportData(
      storeName: map['storeName']?.toString() ?? 'Nusantara POS',
      reportId: map['reportId']?.toString() ?? '',
      cashierName: map['cashierName']?.toString() ?? 'Cashier',
      role: map['role']?.toString() ?? 'Staff',
      shiftLabel: map['shiftLabel']?.toString() ?? 'Standard Shift',
      shiftHours: map['shiftHours']?.toString() ?? '07:00 - 15:00',
      startTime: DateTime.tryParse(map['startTime']?.toString() ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(map['endTime']?.toString() ?? '') ?? DateTime.now(),
      totalOrders: (map['totalOrders'] as num?)?.toInt() ?? 0,
      onlineOrderCount: (map['onlineOrderCount'] as num?)?.toInt() ?? 0,
      offlineOrderCount: (map['offlineOrderCount'] as num?)?.toInt() ?? 0,
      grossSales: (map['grossSales'] as num?)?.toInt() ?? 0,
      taxAndServiceTotal: (map['taxAndServiceTotal'] as num?)?.toInt() ?? 0,
      cashSales: (map['cashSales'] as num?)?.toInt() ?? 0,
      nonCashSales: (map['nonCashSales'] as num?)?.toInt() ?? 0,
      openingCash: (map['openingCash'] as num?)?.toInt() ?? 0,
      expectedCash: (map['expectedCash'] as num?)?.toInt() ?? 0,
      actualCash: (map['actualCash'] as num?)?.toInt() ?? 0,
      variance: (map['variance'] as num?)?.toInt() ?? 0,
      aiSummary: map['aiSummary']?.toString() ?? '',
      nextCashierName: map['nextCashierName']?.toString(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      syncedToFirestore: map['syncedToFirestore'] == true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ZReportData.fromJson(String source) =>
      ZReportData.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
