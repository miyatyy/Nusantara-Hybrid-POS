import 'package:flutter/foundation.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../services/settings_service.dart';

class PosState extends ChangeNotifier {
  static final PosState _instance = PosState._internal();
  factory PosState() => _instance;
  PosState._internal() {
    SettingsService().addListener(notifyListeners);
  }

  final List<OrderItem> _cart = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  int _currentTabIndex = 0;
  String _orderMode = 'Dine In'; // 'Dine In' vs 'Take Away'
  String _orderNotes = '';

  List<OrderItem> get cart => List.unmodifiable(_cart);
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  int get currentTabIndex => _currentTabIndex;
  String get orderMode => _orderMode;
  String get orderNotes => _orderNotes;

  int get totalItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.totalPrice);

  // Dynamic Service Charge and Tax from Store Settings
  double get serviceChargeRate => SettingsService().serviceChargeRate / 100.0;
  double get taxRate => SettingsService().taxRate / 100.0;

  double get serviceCharge => subtotal * serviceChargeRate;
  double get tax => (subtotal + serviceCharge) * taxRate;

  double get total => subtotal + serviceCharge + tax;

  int getItemQuantity(String menuItemId) {
    final idx = _cart.indexWhere((i) => i.menuItem.id == menuItemId);
    return idx >= 0 ? _cart[idx].quantity : 0;
  }

  void setOrderMode(String mode) {
    _orderMode = mode;
    notifyListeners();
  }

  void setOrderNotes(String notes) {
    _orderNotes = notes;
    notifyListeners();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void addToCart(MenuItem item, {int quantity = 1, String notes = ''}) {
    final existingIndex = _cart.indexWhere((i) => i.menuItem.id == item.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].quantity += quantity;
      if (notes.isNotEmpty) {
        _cart[existingIndex].notes = notes;
      }
    } else {
      _cart.add(OrderItem(
        menuItem: item,
        quantity: quantity,
        notes: notes,
      ));
    }
    notifyListeners();
  }

  void updateQuantity(String menuItemId, int newQuantity) {
    final index = _cart.indexWhere((i) => i.menuItem.id == menuItemId);
    if (index >= 0) {
      if (newQuantity <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].quantity = newQuantity;
      }
      notifyListeners();
    }
  }

  void updateItemNotes(String menuItemId, String notes) {
    final index = _cart.indexWhere((i) => i.menuItem.id == menuItemId);
    if (index >= 0) {
      _cart[index] = OrderItem(
        menuItem: _cart[index].menuItem,
        quantity: _cart[index].quantity,
        notes: notes,
      );
      notifyListeners();
    }
  }

  void removeFromCart(String menuItemId) {
    _cart.removeWhere((i) => i.menuItem.id == menuItemId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _orderNotes = '';
    notifyListeners();
  }

  void notifyMenuChanged() {
    notifyListeners();
  }
}
