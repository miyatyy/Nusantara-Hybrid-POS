class ProcurementLog {
  final String id;
  final String rawMaterialId;
  final String rawMaterialName;
  final double quantityAdded;
  final String unit;
  final double costTotal;
  final String supplier;
  final DateTime timestamp;

  ProcurementLog({
    required this.id,
    required this.rawMaterialId,
    required this.rawMaterialName,
    required this.quantityAdded,
    required this.unit,
    required this.costTotal,
    required this.supplier,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rawMaterialId': rawMaterialId,
      'rawMaterialName': rawMaterialName,
      'quantityAdded': quantityAdded,
      'unit': unit,
      'costTotal': costTotal,
      'supplier': supplier,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ProcurementLog.fromMap(Map<String, dynamic> map, String docId) {
    return ProcurementLog(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      rawMaterialId: map['rawMaterialId'] ?? '',
      rawMaterialName: map['rawMaterialName'] ?? '',
      quantityAdded: (map['quantityAdded'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? 'unit',
      costTotal: (map['costTotal'] as num?)?.toDouble() ?? 0.0,
      supplier: map['supplier'] ?? 'Supplier',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
