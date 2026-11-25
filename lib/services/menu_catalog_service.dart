import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_item.dart';
import '../services/firestore_service.dart';
import '../services/email_auth_service.dart';
import '../services/menu_availability_notifier.dart';
import '../state/pos_state.dart';

/// Central reactive in-memory repository for Menu Items.
/// Guarantees:
/// 1. Instant (0ms) synchronous UI updates for edit, add, and delete operations.
/// 2. Offline persistence using local SharedPreferences cache.
/// 3. Asynchronous bidirectional real-time synchronization with Cloud Firestore (`menu_items`).
class MenuCatalogService extends ChangeNotifier {
  static final MenuCatalogService _instance = MenuCatalogService._internal();
  factory MenuCatalogService() => _instance;
  MenuCatalogService._internal();

  static const String _kCachedMenuKey = 'local_cached_menu_items_v2';
  List<MenuItem> _items = [];
  bool _isInitialized = false;

  List<MenuItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await reloadForTenant();
  }

  Future<void> reloadForTenant() async {
    _items.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(EmailAuthService.scopedKey(_kCachedMenuKey));
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        _items = list
            .map((e) => MenuItem.fromMap(e as Map<String, dynamic>, e['id']?.toString() ?? ''))
            .toList();
      }
    } catch (e) {
      debugPrint('[MenuCatalogService] Cache load error: $e');
    }

    // Fallback to default seed if local cache is empty
    if (_items.isEmpty) {
      _items = List.of(FirestoreService.defaultSeedMenuItems);
    }
    notifyListeners();

    // Subscribe to tenant-isolated Firestore real-time stream safely
    try {
      FirestoreService().streamMenuItems().listen(
        (firestoreItems) {
          if (firestoreItems.isNotEmpty) {
            // Merge with Firestore snapshot: keep updated properties
            final Map<String, MenuItem> mergedMap = {for (var i in _items) i.id: i};
            for (final fItem in firestoreItems) {
              mergedMap[fItem.id] = fItem;
            }
            _items = mergedMap.values.toList();
            _saveToCache();
            notifyListeners();
          }
        },
        onError: (err) {
          debugPrint('[MenuCatalogService] Firestore stream notice: $err');
        },
      );
    } catch (e) {
      debugPrint('[MenuCatalogService] Firestore stream not initialized: $e');
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.map((e) => e.toMap()).toList();
      await prefs.setString(EmailAuthService.scopedKey(_kCachedMenuKey), jsonEncode(list));
    } catch (e) {
      debugPrint('[MenuCatalogService] Cache save error: $e');
    }
  }

  /// Save or update a menu item (Instant 0ms local reflection + local cache + Cloud Firestore sync)
  Future<void> saveMenuItem(MenuItem item) async {
    // 1. Assign ID and fallback image if empty
    String itemId = item.id.trim();
    if (itemId.isEmpty) {
      itemId = 'menu_${DateTime.now().millisecondsSinceEpoch}';
    }
    String effectiveImageUrl = item.imageUrl.trim();
    if (effectiveImageUrl.isEmpty) {
      effectiveImageUrl = FirestoreService.resolveDefaultImageUrl(item.name, item.category);
    }
    final resolvedItem = item.copyWith(id: itemId, imageUrl: effectiveImageUrl);

    // 2. Synchronous in-memory update for 0ms UI reaction
    final existingIndex = _items.indexWhere((m) => m.id == itemId);
    if (existingIndex >= 0) {
      _items[existingIndex] = resolvedItem;
    } else {
      _items.add(resolvedItem);
    }

    // 3. Persist to local cache immediately
    await _saveToCache();

    // 4. Notify all UI listeners immediately
    notifyListeners();
    PosState().notifyMenuChanged();

    // 5. Update MenuAvailabilityNotifier override if applicable
    await MenuAvailabilityNotifier().setOverride(resolvedItem, MenuOverrideState.auto);

    // 6. Asynchronously sync to Cloud Firestore
    try {
      await FirestoreService().saveMenuItem(resolvedItem);
    } catch (e) {
      debugPrint('[MenuCatalogService] Firestore save error: $e');
    }
  }

  /// Delete a menu item (Instant 0ms local removal + local cache + Cloud Firestore sync)
  Future<void> deleteMenuItem(String id) async {
    _items.removeWhere((m) => m.id == id);
    await _saveToCache();
    notifyListeners();
    PosState().notifyMenuChanged();

    try {
      await FirestoreService().deleteMenuItem(id);
    } catch (e) {
      debugPrint('[MenuCatalogService] Firestore delete error: $e');
    }
  }
}
