class RawMaterial {
  final String id;
  final String name;
  final String category;
  final double currentStock;
  final String unit; // 'g', 'ml', 'pcs', 'gr'
  final double minSafetyStock;
  final double minThreshold; // Low-stock alert threshold (default 5.0 units)
  final double costPerUnit; // in IDR

  const RawMaterial({
    required this.id,
    required this.name,
    required this.category,
    required this.currentStock,
    required this.unit,
    required this.minSafetyStock,
    this.minThreshold = 5.0,
    required this.costPerUnit,
  });

  bool get isLowStock => currentStock <= (minThreshold > 0 ? minThreshold : minSafetyStock);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'currentStock': currentStock,
      'unit': unit,
      'minSafetyStock': minSafetyStock,
      'minThreshold': minThreshold,
      'costPerUnit': costPerUnit,
    };
  }

  factory RawMaterial.fromMap(Map<String, dynamic> map, String docId) {
    final safetyStock = (map['minSafetyStock'] as num?)?.toDouble() ?? 0.0;
    final threshold = (map['minThreshold'] as num?)?.toDouble() ??
        (safetyStock > 0 ? safetyStock : 5.0);

    return RawMaterial(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      name: map['name'] ?? '',
      category: map['category'] ?? 'General',
      currentStock: (map['currentStock'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? 'unit',
      minSafetyStock: safetyStock,
      minThreshold: threshold,
      costPerUnit: (map['costPerUnit'] as num?)?.toDouble() ?? 0.0,
    );
  }

  RawMaterial copyWith({
    String? id,
    String? name,
    String? category,
    double? currentStock,
    String? unit,
    double? minSafetyStock,
    double? minThreshold,
    double? costPerUnit,
  }) {
    return RawMaterial(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      minSafetyStock: minSafetyStock ?? this.minSafetyStock,
      minThreshold: minThreshold ?? this.minThreshold,
      costPerUnit: costPerUnit ?? this.costPerUnit,
    );
  }
}
