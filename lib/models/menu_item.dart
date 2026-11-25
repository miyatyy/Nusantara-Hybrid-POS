import 'raw_material.dart';
import '../services/menu_availability_notifier.dart';
import '../services/firestore_service.dart';

class MenuItem {
  final String id;
  final String name;
  final String nameEn;
  final String category; // 'Makanan', 'Minuman', 'Cemilan', 'Paket'
  final double price; // in IDR
  final String description;
  final bool isAvailable;
  // Recipe: Map of rawMaterialId -> quantity needed per portion
  final Map<String, double> recipe;
  final String iconEmoji;
  final int popularityScore;
  final String imageUrl;

  // Manual Human Override flags for staff & POS operators
  final bool isManualSoldOut;
  final bool forceManualReady;

  const MenuItem({
    required this.id,
    required this.name,
    this.nameEn = '',
    required this.category,
    required this.price,
    required this.description,
    this.isAvailable = true,
    this.recipe = const {},
    this.iconEmoji = '☕',
    this.popularityScore = 50,
    this.imageUrl = '',
    this.isManualSoldOut = false,
    this.forceManualReady = false,
  });

  String get displayName => name;

  // Calculate COGS (Cost of Goods Sold / HPP) based on raw materials
  double calculateCostOfGoods(Map<String, RawMaterial> rawStockMap) {
    double totalCost = 0.0;
    recipe.forEach((matId, qty) {
      RawMaterial? mat = rawStockMap[matId];
      if (mat == null) {
        for (final seed in FirestoreService.defaultSeedRawMaterials) {
          if (seed.id == matId) {
            mat = seed;
            break;
          }
        }
      }
      if (mat != null) {
        totalCost += (mat.costPerUnit * qty);
      }
    });
    return totalCost;
  }

  // Calculate how many portions can be prepared given current raw materials stock
  int calculateAvailablePortions(Map<String, RawMaterial> rawStockMap) {
    final override = MenuAvailabilityNotifier().getOverride(this);
    if (override == MenuOverrideState.forceReady || forceManualReady) return 999;
    if (override == MenuOverrideState.forceSoldOut || isManualSoldOut) return 0;
    if (recipe.isEmpty) return 999;

    int maxPortions = 999999;
    for (final entry in recipe.entries) {
      RawMaterial? mat = rawStockMap[entry.key];
      if (mat == null) {
        for (final seed in FirestoreService.defaultSeedRawMaterials) {
          if (seed.id == entry.key) {
            mat = seed;
            break;
          }
        }
      }
      if (mat == null || entry.value <= 0) {
        return 0;
      }
      final possible = (mat.currentStock / entry.value).floor();
      if (possible < maxPortions) {
        maxPortions = possible;
      }
    }
    return maxPortions < 0 ? 0 : maxPortions;
  }

  // Effective Sold Out status factoring in manual overrides and recipe raw materials
  bool isEffectivelySoldOut(Map<String, RawMaterial> rawStockMap) {
    final override = MenuAvailabilityNotifier().getOverride(this);
    if (override == MenuOverrideState.forceSoldOut || isManualSoldOut) return true;
    if (override == MenuOverrideState.forceReady || forceManualReady) return false;
    return calculateAvailablePortions(rawStockMap) <= 0;
  }

  // Effective Ready status (available for ordering on POS & Menu)
  bool isEffectivelyReady(Map<String, RawMaterial> rawStockMap) {
    return !isEffectivelySoldOut(rawStockMap);
  }

  // Combined Hybrid AI & BOM Auto-Availability computation
  bool computeIsReady(Map<String, RawMaterial> rawStockMap, {bool autoDeductEnabled = true}) {
    final override = MenuAvailabilityNotifier().getOverride(this);
    if (override == MenuOverrideState.forceSoldOut || isManualSoldOut) return false;
    if (override == MenuOverrideState.forceReady || forceManualReady) return true;
    if (!autoDeductEnabled) return isAvailable;
    final portions = calculateAvailablePortions(rawStockMap);
    return portions > 0 && isAvailable;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nameEn': nameEn,
      'category': category,
      'price': price,
      'description': description,
      'isAvailable': isAvailable,
      'recipe': recipe,
      'iconEmoji': iconEmoji,
      'popularityScore': popularityScore,
      'imageUrl': imageUrl,
      'isManualSoldOut': isManualSoldOut,
      'forceManualReady': forceManualReady,
    };
  }

  factory MenuItem.fromMap(Map<String, dynamic> map, String docId) {
    Map<String, double> parsedRecipe = {};
    if (map['recipe'] is Map) {
      (map['recipe'] as Map).forEach((k, v) {
        parsedRecipe[k.toString()] = (v as num).toDouble();
      });
    }

    return MenuItem(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      name: map['name'] ?? '',
      nameEn: map['nameEn'] ?? '',
      category: map['category'] ?? 'Makanan',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      description: map['description'] ?? '',
      isAvailable: map['isAvailable'] ?? true,
      recipe: parsedRecipe,
      iconEmoji: map['iconEmoji'] ?? '🍽️',
      popularityScore: (map['popularityScore'] as num?)?.toInt() ?? 50,
      imageUrl: map['imageUrl'] ?? '',
      isManualSoldOut: map['isManualSoldOut'] == true,
      forceManualReady: map['forceManualReady'] == true,
    );
  }

  MenuItem copyWith({
    String? id,
    String? name,
    String? nameEn,
    String? category,
    double? price,
    String? description,
    bool? isAvailable,
    Map<String, double>? recipe,
    String? iconEmoji,
    int? popularityScore,
    String? imageUrl,
    bool? isManualSoldOut,
    bool? forceManualReady,
  }) {
    return MenuItem(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      category: category ?? this.category,
      price: price ?? this.price,
      description: description ?? this.description,
      isAvailable: isAvailable ?? this.isAvailable,
      recipe: recipe ?? this.recipe,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      popularityScore: popularityScore ?? this.popularityScore,
      imageUrl: imageUrl ?? this.imageUrl,
      isManualSoldOut: isManualSoldOut ?? this.isManualSoldOut,
      forceManualReady: forceManualReady ?? this.forceManualReady,
    );
  }
}
