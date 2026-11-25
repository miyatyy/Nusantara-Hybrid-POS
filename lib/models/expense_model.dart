class ExpenseModel {
  final String id;
  final String title;
  final String category; // 'Restock', 'Operational', 'Packaging', 'Wages', 'Other'
  final double amount;
  final DateTime timestamp;
  final String loggedBy;
  final String? referenceId; // e.g. procurement log id

  const ExpenseModel({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.timestamp,
    this.loggedBy = 'Staff',
    this.referenceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
      'loggedBy': loggedBy,
      'referenceId': referenceId,
    };
  }

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String docId) {
    return ExpenseModel(
      id: docId.isNotEmpty ? docId : (map['id']?.toString() ?? ''),
      title: map['title']?.toString() ?? 'Pengeluaran',
      category: map['category']?.toString() ?? 'Operational',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
      loggedBy: map['loggedBy']?.toString() ?? 'Staff',
      referenceId: map['referenceId']?.toString(),
    );
  }
}
