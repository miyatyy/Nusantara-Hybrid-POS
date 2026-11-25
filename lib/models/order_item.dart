import 'menu_item.dart';

class OrderItem {
  final MenuItem menuItem;
  int quantity;
  String notes;

  OrderItem({
    required this.menuItem,
    this.quantity = 1,
    this.notes = '',
  });

  double get unitPrice => menuItem.price;
  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItem.id,
      'menuItemName': menuItem.name,
      'category': menuItem.category,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'totalPrice': totalPrice,
      'notes': notes,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map, MenuItem item) {
    return OrderItem(
      menuItem: item,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      notes: map['notes'] ?? '',
    );
  }
}
