import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_item.dart';
import '../models/raw_material.dart';
import 'email_auth_service.dart';

enum MenuOverrideState {
  auto,
  forceReady,
  forceSoldOut,
}

/// Global, app-wide reactive menu availability controller
/// Keyed by BOTH normalized `menuId` AND lowercase trimmed `menuName` (and `nameEn`)
/// Persisted in SharedPreferences AND synchronized to Cloud Firestore (`menu_items` collection)
class MenuAvailabilityNotifier extends ValueNotifier<Map<String, MenuOverrideState>> {
  static final MenuAvailabilityNotifier _instance = MenuAvailabilityNotifier._internal();
  factory MenuAvailabilityNotifier() => _instance;
  MenuAvailabilityNotifier._internal() : super({});

  static const String _kStorageKey = 'menu_availability_overrides_v2';
  static const String _kLegacyStorageKey = 'menu_availability_overrides';

  CollectionReference<Map<String, dynamic>> get _menuItemsRef =>
      EmailAuthService.tenantCollection('menu_items');

  /// Reload overrides when switching tenant accounts.
  Future<void> reloadForTenant() => init();

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, MenuOverrideState> map = {};

      // 1. Load from V2 storage key (scoped per tenant)
      final rawV2 = prefs.getString(EmailAuthService.scopedKey(_kStorageKey));
      if (rawV2 != null && rawV2.isNotEmpty) {
        final decoded = jsonDecode(rawV2) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val == 'forceReady' || val == 'ready') {
            map[key] = MenuOverrideState.forceReady;
          } else if (val == 'forceSoldOut' || val == 'soldOut') {
            map[key] = MenuOverrideState.forceSoldOut;
          } else {
            map[key] = MenuOverrideState.auto;
          }
        });
      }

      // 2. Fallback / Migration from legacy storage key
      final rawLegacy = prefs.getString(_kLegacyStorageKey);
      if (rawLegacy != null && rawLegacy.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawLegacy) as Map<String, dynamic>;
          decoded.forEach((key, val) {
            if (val is Map) {
              final isSoldOut = val['isManualSoldOut'] == true;
              final forceReady = val['forceManualReady'] == true;
              if (isSoldOut) {
                map.putIfAbsent(key, () => MenuOverrideState.forceSoldOut);
              } else if (forceReady) {
                map.putIfAbsent(key, () => MenuOverrideState.forceReady);
              }
            }
          });
        } catch (_) {}
      }

      value = map;
    } catch (e) {
      debugPrint('[MenuAvailabilityNotifier] init error: $e');
    }
  }

  /// Get override state for a MenuItem (checks id, trimmed lowercase name, and trimmed lowercase nameEn)
  MenuOverrideState getOverride(MenuItem item) {
    final idKey = item.id.trim();
    if (idKey.isNotEmpty && value.containsKey(idKey)) {
      return value[idKey]!;
    }

    final nameKey = item.name.trim().toLowerCase();
    if (nameKey.isNotEmpty && value.containsKey(nameKey)) {
      return value[nameKey]!;
    }

    if (item.nameEn.trim().isNotEmpty) {
      final nameEnKey = item.nameEn.trim().toLowerCase();
      if (value.containsKey(nameEnKey)) {
        return value[nameEnKey]!;
      }
    }

    // Direct model fallback if item was received with flags from Firestore
    if (item.isManualSoldOut) return MenuOverrideState.forceSoldOut;
    if (item.forceManualReady) return MenuOverrideState.forceReady;

    return MenuOverrideState.auto;
  }

  /// Strict priority availability checker:
  /// 1. If override == forceSoldOut -> true (Sold Out grayscale)
  /// 2. Else if override == forceReady -> false (Ready & colored, add button active)
  /// 3. Else (auto) -> availablePortions <= 0
  bool isItemSoldOut(MenuItem item, Map<String, RawMaterial> rawStockMap) {
    final state = getOverride(item);
    if (state == MenuOverrideState.forceSoldOut) return true;
    if (state == MenuOverrideState.forceReady) return false;

    // Auto mode: check raw materials and recipe stock
    final portions = item.calculateAvailablePortions(rawStockMap);
    return portions <= 0;
  }

  /// Returns true if item is ready and can be added to cart on POS storefront
  bool isItemReady(MenuItem item, Map<String, RawMaterial> rawStockMap) {
    return !isItemSoldOut(item, rawStockMap);
  }

  /// Set override state for a MenuItem with instant state notification and persistence
  Future<void> setOverride(MenuItem item, MenuOverrideState state) async {
    final newMap = Map<String, MenuOverrideState>.from(value);
    final idKey = item.id.trim();
    final nameKey = item.name.trim().toLowerCase();
    final nameEnKey = item.nameEn.trim().toLowerCase();

    if (state == MenuOverrideState.auto) {
      if (idKey.isNotEmpty) newMap.remove(idKey);
      if (nameKey.isNotEmpty) newMap.remove(nameKey);
      if (nameEnKey.isNotEmpty) newMap.remove(nameEnKey);
    } else {
      if (idKey.isNotEmpty) newMap[idKey] = state;
      if (nameKey.isNotEmpty) newMap[nameKey] = state;
      if (nameEnKey.isNotEmpty) newMap[nameEnKey] = state;
    }

    value = newMap;
    notifyListeners();

    // 1. Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> toSave = {};
      newMap.forEach((k, v) {
        toSave[k] = v.name;
      });
      await prefs.setString(
          EmailAuthService.scopedKey(_kStorageKey), jsonEncode(toSave));
    } catch (e) {
      debugPrint('[MenuAvailabilityNotifier] SharedPreferences error: $e');
    }

    // 2. Persist to Firestore
    try {
      final isSoldOut = state == MenuOverrideState.forceSoldOut;
      final isReady = state == MenuOverrideState.forceReady;
      if (item.id.trim().isNotEmpty) {
        await _menuItemsRef.doc(item.id.trim()).set({
          'isManualSoldOut': isSoldOut,
          'forceManualReady': isReady,
          'isAvailable': !isSoldOut,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[MenuAvailabilityNotifier] Firestore error: $e');
    }
  }

  /// Clear override for a single item (restore automatic recipe/stock calculation)
  Future<void> resetItem(MenuItem item) async {
    await setOverride(item, MenuOverrideState.auto);
  }

  /// Reset all overrides
  Future<void> resetAll() async {
    value = {};
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(EmailAuthService.scopedKey(_kStorageKey));
    } catch (_) {}
  }
}
