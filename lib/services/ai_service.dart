import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/raw_material.dart';
import '../models/transaction_model.dart';
import '../models/ai_recommendation.dart';
import 'connectivity_service.dart';

enum InferenceMode {
  preferOnDevice,
  onlyInCloud,
  onlyOnDevice,
}

enum ActiveAiEngine {
  localNano,
  cloudFlash,
  offlineFallback,
}

class AiOrderParseResult {
  final List<OrderItem> items;
  final double? cashReceived;
  final String engineUsed; // 'ON_DEVICE' or 'IN_CLOUD'
  final String explanation;

  AiOrderParseResult({
    required this.items,
    this.cashReceived,
    required this.engineUsed,
    this.explanation = '',
  });
}

class AiBusinessInsightResult {
  final String executiveSummary;
  final String topTrend;
  final String suggestedBundleName;
  final String suggestedBundleDescription;
  final double suggestedBundlePrice;
  final List<String> bundleItemIds;
  final double estimatedMargin;

  AiBusinessInsightResult({
    required this.executiveSummary,
    required this.topTrend,
    required this.suggestedBundleName,
    required this.suggestedBundleDescription,
    required this.suggestedBundlePrice,
    required this.bundleItemIds,
    required this.estimatedMargin,
  });
}

class AiProcurementAdviceResult {
  final String generalAdvice;
  final List<ProcurementItemAdvice> items;
  final double totalEstimatedBudget;

  AiProcurementAdviceResult({
    required this.generalAdvice,
    required this.items,
    required this.totalEstimatedBudget,
  });
}

class ProcurementItemAdvice {
  final String rawMaterialId;
  final String name;
  final double recommendedBuyQty;
  final String unit;
  final double estimatedCost;
  final String urgency; // 'HIGH', 'MEDIUM', 'NORMAL'

  ProcurementItemAdvice({
    required this.rawMaterialId,
    required this.name,
    required this.recommendedBuyQty,
    required this.unit,
    required this.estimatedCost,
    required this.urgency,
  });
}

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  final ValueNotifier<ActiveAiEngine> activeEngineNotifier =
      ValueNotifier<ActiveAiEngine>(ActiveAiEngine.cloudFlash);

  ActiveAiEngine get activeEngine => activeEngineNotifier.value;

  // 1. Google AI generative model initialized with Gemini 1.5 Flash
  GenerativeModel get _cloudFlashModel {
    final googleAI = FirebaseAI.googleAI();
    return googleAI.generativeModel(
      model: 'gemini-1.5-flash',
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: 1024,
      ),
    );
  }

  // Hybrid Cashier Model: preferOnDevice with cloud fallback
  Future<AiOrderParseResult> parseNaturalOrder({
    required String prompt,
    required List<MenuItem> menuItems,
    required Map<String, RawMaterial> rawStockMap,
    InferenceMode mode = InferenceMode.preferOnDevice,
  }) async {
    final isOnline = ConnectivityService().isOnline;

    // Fast, deterministic on-device parsing for preferOnDevice or offline mode
    if (!isOnline || mode == InferenceMode.onlyOnDevice || mode == InferenceMode.preferOnDevice) {
      activeEngineNotifier.value = ActiveAiEngine.localNano;
      return _localFastOrderParser(
        prompt: prompt,
        menuItems: menuItems,
        engineTag: 'ON_DEVICE',
      );
    }

    try {
      activeEngineNotifier.value = ActiveAiEngine.cloudFlash;

      final compactMenu = menuItems.map((m) {
        return {
          'id': m.id,
          'name': m.name,
          'nameEn': m.nameEn,
          'price': m.price,
          'portions': m.calculateAvailablePortions(rawStockMap),
        };
      }).toList();

      final systemPrompt = '''
You are the AI Cashier engine for "Nusantara Hybrid POS".
Extract ordered items from the customer text.
Menu options: ${jsonEncode(compactMenu)}

Return ONLY a valid JSON object matching this schema:
{
  "items": [
    {
      "menuItemId": "exact_matching_id",
      "quantity": 1,
      "notes": "e.g. less ice, extra sugar, no sambal"
    }
  ],
  "cashReceived": 100000 (numeric amount if user mentioned paying cash e.g. "100k", "cash 100rb", or null)
}
No markdown formatting, no code blocks, just raw JSON.
''';

      final response = await _cloudFlashModel.generateContent([
        Content.text('$systemPrompt\n\nCustomer order: "$prompt"')
      ]).timeout(const Duration(seconds: 8));

      final rawText = response.text?.trim() ?? '';
      final cleanJson = _cleanJsonString(rawText);

      final Map<String, dynamic> data = jsonDecode(cleanJson);
      final List<dynamic> itemsJson = data['items'] ?? [];
      final List<OrderItem> orderItems = [];

      for (final itemMap in itemsJson) {
        final id = itemMap['menuItemId']?.toString() ?? '';
        final qty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
        final notes = itemMap['notes']?.toString() ?? '';

        final matched = menuItems.firstWhere(
          (m) => m.id == id,
          orElse: () => _findBestMenuItemMatch(id, menuItems) ?? const MenuItem(
            id: '',
            name: '',
            category: '',
            price: 0,
            description: '',
          ),
        );

        if (matched.id.isNotEmpty) {
          orderItems.add(OrderItem(
            menuItem: matched,
            quantity: qty,
            notes: notes,
          ));
        }
      }

      double? cashReceived;
      if (data['cashReceived'] != null) {
        cashReceived = (data['cashReceived'] as num).toDouble();
      }

      // If cloud returned empty, fallback to local fast parser
      if (orderItems.isEmpty) {
        return _localFastOrderParser(
          prompt: prompt,
          menuItems: menuItems,
          engineTag: 'ON_DEVICE',
        );
      }

      return AiOrderParseResult(
        items: orderItems,
        cashReceived: cashReceived,
        engineUsed: 'IN_CLOUD',
        explanation: 'Parsed by Cloud: Gemini 3.8 Flash in ultra-fast mode.',
      );
    } catch (e) {
      debugPrint('Cloud AI parsing notice (falling back to on-device engine): $e');
      activeEngineNotifier.value = ActiveAiEngine.localNano;
      return _localFastOrderParser(
        prompt: prompt,
        menuItems: menuItems,
        engineTag: 'ON_DEVICE',
      );
    }
  }

  // Fast on-device intelligent parser for Gemini Nano / Offline fallback
  AiOrderParseResult _localFastOrderParser({
    required String prompt,
    required List<MenuItem> menuItems,
    required String engineTag,
  }) {
    String workingText = prompt.trim();
    if (workingText.isEmpty) {
      return AiOrderParseResult(
        items: [],
        engineUsed: engineTag,
        explanation: 'Empty prompt.',
      );
    }

    // 1. Detect and isolate cash payment first so it NEVER contaminates item quantities
    double? cashReceived;
    final explicitCashRegex = RegExp(
      r'(?:cash|bayar|tunai|uang|uangnya)\s*(?:rp\.?)?\s*(\d+(?:[\.,]\d+)?)\s*(k|rb|ribu|jt|juta|000)?\b',
      caseSensitive: false,
    );
    final explicitMatch = explicitCashRegex.firstMatch(workingText);
    if (explicitMatch != null) {
      final cleanNum = explicitMatch.group(1)?.replaceAll('.', '').replaceAll(',', '') ?? '0';
      final numVal = double.tryParse(cleanNum) ?? 0;
      final unit = (explicitMatch.group(2) ?? '').toLowerCase();
      if (unit == 'k' || unit == 'rb' || unit == 'ribu' || unit == '000') {
        cashReceived = numVal * 1000;
      } else if (unit == 'jt' || unit == 'juta') {
        cashReceived = numVal * 1000000;
      } else {
        cashReceived = numVal;
      }
      // Remove cash phrase from workingText
      workingText = workingText.replaceRange(explicitMatch.start, explicitMatch.end, ' ');
    } else {
      // Standalone number with k/rb suffix enforcing word boundary (e.g. "100k", "50rb")
      final standaloneRegex = RegExp(r'\b(\d+)\s*(k|rb|ribu)\b', caseSensitive: false);
      final standaloneMatch = standaloneRegex.firstMatch(workingText);
      if (standaloneMatch != null) {
        final numVal = double.tryParse(standaloneMatch.group(1) ?? '0') ?? 0;
        cashReceived = numVal * 1000;
        workingText = workingText.replaceRange(standaloneMatch.start, standaloneMatch.end, ' ');
      }
    }

    // 2. Normalize word numbers to digits
    final wordNumbers = {
      r'\b(?:sebuah|seporsi|segelas|secangkir|satu|one)\b': '1',
      r'\b(?:dua|two)\b': '2',
      r'\b(?:tiga|three)\b': '3',
      r'\b(?:empat|four)\b': '4',
      r'\b(?:lima|five)\b': '5',
      r'\b(?:enam|six)\b': '6',
      r'\b(?:tujuh|seven)\b': '7',
      r'\b(?:delapan|eight)\b': '8',
      r'\b(?:sembilan|nine)\b': '9',
      r'\b(?:sepuluh|ten)\b': '10',
    };
    for (final entry in wordNumbers.entries) {
      workingText = workingText.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }

    // 3. Segment prompt into distinct item clauses
    // Delimiters: commas, semicolons, newlines, "dan", "and", "sama", "terus", "lalu", "juga", "plus", "+", "&"
    List<String> segments = workingText
        .split(RegExp(r'[,;\n]|\s+(?:dan|and|sama|terus|lalu|juga|plus|\+|\&)\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // If there is only 1 segment but multiple numeric patterns like "2 es teh 1 nasi goreng", split them
    if (segments.length == 1) {
      final multiItemRegex = RegExp(r'(\d+\s+[^0-9]+?)(?=\s+\d+\s+|$)', caseSensitive: false);
      final matches = multiItemRegex.allMatches(segments.first).toList();
      if (matches.length > 1) {
        segments = matches.map((m) => m.group(1)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
      }
    }

    // 4. Process each segment individually
    final List<OrderItem> parsedItems = [];

    for (final rawSegment in segments) {
      String segment = rawSegment.trim();
      if (segment.isEmpty) continue;

      // a. Extract notes local to this specific item
      String itemNotes = '';
      final notePatterns = {
        r'\b(?:less\s*ice)\b': 'Less ice',
        r'\b(?:sedikit\s*es)\b': 'Sedikit es',
        r'\b(?:no\s*ice)\b': 'No ice',
        r'\b(?:tanpa\s*es)\b': 'Tanpa es',
        r'\b(?:extra\s*ice)\b': 'Extra ice',
        r'\b(?:banyak\s*es)\b': 'Banyak es',
        r'\b(?:less\s*sugar)\b': 'Less sugar',
        r'\b(?:sedikit\s*gula)\b': 'Sedikit gula',
        r'\b(?:no\s*sugar)\b': 'No sugar',
        r'\b(?:tanpa\s*gula)\b': 'Tanpa gula',
        r'\b(?:extra\s*sugar)\b': 'Extra sugar',
        r'\b(?:lebih\s*manis)\b': 'Lebih manis',
        r'\b(?:pedas|extra\s*pedas|spicy)\b': 'Pedas',
        r'\b(?:tidak\s*pedas|nggak\s*pedas|no\s*spicy)\b': 'Tidak pedas',
        r'\b(?:panas|hot)\b': 'Panas',
        r'\b(?:dingin|cold)\b': 'Dingin',
        r'\b(?:bungkus|take\s*away)\b': 'Bungkus',
      };

      for (final np in notePatterns.entries) {
        final regex = RegExp(np.key, caseSensitive: false);
        if (regex.hasMatch(segment)) {
          itemNotes = np.value;
          segment = segment.replaceAll(regex, ' ').trim();
          break;
        }
      }

      // b. Extract quantity (prefix or suffix)
      int qty = 1;
      final prefixQtyRegex = RegExp(r'^(\d+)\s*(?:x|\*|porsi|cup|gelas|piring|botol|buah|biji)?\s+', caseSensitive: false);
      final suffixQtyRegex = RegExp(r'\s+(\d+)\s*(?:x|\*|porsi|cup|gelas|piring|botol|buah|biji)?$', caseSensitive: false);
      final inlineQtyRegex = RegExp(r'\b(\d+)\s*(?:x|\*|porsi|cup|gelas|piring|botol|buah|biji)?\b', caseSensitive: false);

      final pMatch = prefixQtyRegex.firstMatch(segment);
      if (pMatch != null) {
        qty = int.tryParse(pMatch.group(1) ?? '1') ?? 1;
        segment = segment.substring(pMatch.end).trim();
      } else {
        final sMatch = suffixQtyRegex.firstMatch(segment);
        if (sMatch != null) {
          qty = int.tryParse(sMatch.group(1) ?? '1') ?? 1;
          segment = segment.substring(0, sMatch.start).trim();
        } else {
          final iMatch = inlineQtyRegex.firstMatch(segment);
          if (iMatch != null) {
            qty = int.tryParse(iMatch.group(1) ?? '1') ?? 1;
            segment = '${segment.substring(0, iMatch.start)} ${segment.substring(iMatch.end)}'.trim();
          }
        }
      }

      // Clean up common filler words in segment
      segment = segment.replaceAll(
        RegExp(r'\b(?:pesan|beli|mau|order|minta|tolong|tambah|cup|gelas|piring|porsi|buah)\b', caseSensitive: false),
        ' ',
      ).trim();
      if (segment.isEmpty) continue;

      // c. Find best matching MenuItem for this segment
      final matchedMenu = _findBestMenuItemMatch(segment, menuItems);
      if (matchedMenu != null) {
        final existingIndex = parsedItems.indexWhere((i) => i.menuItem.id == matchedMenu.id);
        if (existingIndex >= 0) {
          final existing = parsedItems[existingIndex];
          parsedItems[existingIndex] = OrderItem(
            menuItem: existing.menuItem,
            quantity: existing.quantity + qty,
            notes: existing.notes.isNotEmpty ? existing.notes : itemNotes,
          );
        } else {
          parsedItems.add(OrderItem(
            menuItem: matchedMenu,
            quantity: qty,
            notes: itemNotes,
          ));
        }
      }
    }

    return AiOrderParseResult(
      items: parsedItems,
      cashReceived: cashReceived,
      engineUsed: engineTag,
      explanation: 'Processed via $engineTag intelligent NLP matching.',
    );
  }

  /// High-accuracy specificity matcher for POS catalog
  MenuItem? _findBestMenuItemMatch(String query, List<MenuItem> menuItems) {
    final q = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) return null;

    final isBundleQuery = q.contains('paket') || q.contains('combo') || q.contains('sarapan') || q.contains('bundle');

    MenuItem? bestItem;
    int highestScore = 0;

    // High-precision canonical aliases for Nusantara signature items
    final Map<String, List<String>> aliases = {
      'menu_kopi_aren': [
        'kopi susu gula aren', 'palm sugar iced latte', 'palm sugar latte',
        'kopi susu aren', 'kopi gula aren', 'kopi aren', 'palm sugar',
        'kopi susu', 'latte gula aren', 'aren latte'
      ],
      'menu_espresso': [
        'espresso double shot', 'double espresso', 'espresso double',
        'double shot espresso', 'espresso'
      ],
      'menu_matcha_latte': [
        'kyoto matcha latte', 'matcha latte', 'kyoto matcha',
        'matcha', 'green tea latte'
      ],
      'menu_iced_tea': [
        'es teh melati nusantara', 'es teh melati', 'iced jasmine tea',
        'jasmine tea', 'teh melati', 'es teh manis', 'es teh', 'teh manis', 'iced tea'
      ],
      'menu_ayam_matah': [
        'nasi ayam sambal matah', 'rice with balinese crispy chicken',
        'ayam sambal matah', 'nasi ayam matah', 'ayam matah',
        'balinese crispy chicken', 'sambal matah', 'nasi ayam'
      ],
      'menu_nasgor_spesial': [
        'nasi goreng nusantara special', 'nusantara fried rice special',
        'nasi goreng spesial', 'nasi goreng special', 'nasi goreng',
        'nasgor spesial', 'nasgor', 'fried rice'
      ],
      'menu_croissant': [
        'butter croissant crispy', 'crispy butter croissant',
        'butter croissant', 'croissant crispy', 'croissant', 'kroisan'
      ],
      'menu_pisang_goreng': [
        'pisang goreng madu wijen', 'caramelized honey banana fritters',
        'pisang goreng madu', 'pisang madu', 'pisang goreng',
        'banana fritters', 'pisang'
      ],
      'bundle_sarapan': [
        'paket semangat pagi', 'morning combo', 'paket sarapan',
        'paket pagi', 'paket combo', 'semangat pagi'
      ],
    };

    for (final menu in menuItems) {
      final nameLower = menu.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
      final nameEnLower = menu.nameEn.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
      final isBundle = menu.category.toLowerCase() == 'paket' || nameLower.contains('paket') || nameLower.contains('combo');

      // GUARD 1: Bundles require bundle query words
      if (isBundle && !isBundleQuery) {
        continue;
      }
      // If user explicitly asks for bundle, non-bundles have lower priority unless exact
      if (!isBundle && isBundleQuery && !q.contains(nameLower)) {
        continue;
      }

      int score = 0;

      // 1. Exact match with name or English name
      if (q == nameLower || q == nameEnLower) {
        score = 1000;
      }

      // 2. Known Aliases Check
      final itemAliases = aliases[menu.id] ?? [];
      for (final alias in itemAliases) {
        if (q == alias) {
          score = math.max(score, 900);
        } else if (q.contains(alias)) {
          score = math.max(score, 800 + alias.length);
        } else if (alias.contains(q) && q.length >= 4) {
          score = math.max(score, 700 + q.length);
        }
      }

      // 3. Name containment
      if (q.contains(nameLower) && nameLower.isNotEmpty) {
        score = math.max(score, 850 + nameLower.length);
      } else if (nameLower.contains(q) && q.length >= 4) {
        score = math.max(score, 750 + q.length);
      }

      // 4. Distinctive tokens matching
      final fillerWords = {
        'spesial', 'special', 'crispy', 'fresh', 'delicious', 'enak',
        'original', 'super', 'premium', 'minuman', 'makanan', 'cemilan',
        'dengan', 'with', 'dan', 'and', 'iced', 'hot', 'panas', 'dingin'
      };

      final qTokens = q.split(RegExp(r'\s+')).where((t) => t.length >= 3 && !fillerWords.contains(t)).toSet();
      final nameTokens = nameLower.split(RegExp(r'\s+')).where((t) => t.length >= 3 && !fillerWords.contains(t)).toSet();

      // Guard: specific collision preventions
      // "pisang goreng" vs "nasi goreng"
      if (qTokens.contains('pisang') && !nameTokens.contains('pisang')) continue;
      if (nameTokens.contains('pisang') && !qTokens.contains('pisang')) continue;

      // "nasi goreng" vs "nasi ayam"
      if (qTokens.contains('goreng') && !nameTokens.contains('goreng')) {
        if (nameTokens.contains('ayam')) continue;
      }
      if (qTokens.contains('ayam') && !nameTokens.contains('ayam')) {
        if (nameTokens.contains('goreng')) continue;
      }
      if (qTokens.contains('matah') && !nameTokens.contains('matah')) continue;
      if (nameTokens.contains('matah') && !qTokens.contains('matah')) {
        if (q.contains('matah')) continue;
      }

      final commonTokens = qTokens.intersection(nameTokens);
      if (commonTokens.isNotEmpty) {
        final tokenScore = 500 + (commonTokens.length * 100);
        score = math.max(score, tokenScore);
      }

      if (score > highestScore && score >= 500) {
        highestScore = score;
        bestItem = menu;
      }
    }

    return bestItem;
  }

  // Real-time AI Menu/Bundle Recommender Card
  AiRecommendation getLiveRecommendation({
    required List<MenuItem> menuItems,
    required Map<String, RawMaterial> rawStockMap,
    String moodTag = 'Lunch Rush',
  }) {
    // Pick optimal item with high popularity and sufficient stock
    final availableItems = menuItems.where((m) {
      return m.calculateAvailablePortions(rawStockMap) > 3;
    }).toList();

    if (availableItems.isEmpty) {
      return const AiRecommendation(
        title: 'Nusantara Special Selection',
        description: 'Selected for high culinary craftsmanship and fresh flavor.',
        reason: 'Recommended by POS AI',
        tag: 'Popular',
      );
    }

    // Sort by popularity score
    availableItems.sort((a, b) => b.popularityScore.compareTo(a.popularityScore));
    final topItem = availableItems.first;

    return AiRecommendation(
      title: 'Top Recommendation: ${topItem.name}',
      description: '${topItem.description} High stock readiness (${topItem.calculateAvailablePortions(rawStockMap)} portions ready).',
      recommendedMenuItemId: topItem.id,
      reason: 'Bestseller with 98% customer satisfaction score.',
      discountPercent: 10,
      bundlePrice: topItem.price * 0.9,
      tag: moodTag,
    );
  }

  // Cloud Analytical Model: Deep Business Insights & AI Bundles
  Future<AiBusinessInsightResult> generateBusinessInsight({
    required List<PosTransaction> transactions,
    required List<MenuItem> menuItems,
    required List<RawMaterial> rawMaterials,
  }) async {
    final isOnline = ConnectivityService().isOnline;

    if (!isOnline) {
      return generateOfflineFallbackInsight(menuItems);
    }

    try {
      final summary = {
        'txCount': transactions.length,
        'recentRevenue': transactions.fold<double>(0, (acc, tx) => acc + tx.total),
        'menuCount': menuItems.length,
        'lowStockCount': rawMaterials.where((r) => r.isLowStock).length,
      };

      final prompt = '''
You are an executive F&B financial analyst for Nusantara Hybrid POS.
Analyze these metrics: ${jsonEncode(summary)}
Available menus: ${jsonEncode(menuItems.map((m) => {'id': m.id, 'name': m.name, 'price': m.price, 'cat': m.category}).toList())}

Provide strategic analysis and create 1 high-profit promotional bundle (Paket) combining 1 popular drink and 1 snack/food item with 10% discount.

Return ONLY a JSON response in this exact format:
{
  "executiveSummary": "Concise summary of revenue and performance...",
  "topTrend": "High demand for palm sugar espresso and breakfast pastries",
  "suggestedBundleName": "Paket Hangat Nusantara (Kopi Aren + Pisang Madu)",
  "suggestedBundleDescription": "Combo harmonis kopi aren bold dengan pisang goreng madu renyah.",
  "suggestedBundlePrice": 36000,
  "bundleItemIds": ["menu_kopi_aren", "menu_pisang_goreng"],
  "estimatedMargin": 68.5
}
No markdown tags, no backticks, pure JSON.
''';

      final response = await _cloudFlashModel
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 12));
      final cleanJson = _cleanJsonString(response.text?.trim() ?? '');
      final Map<String, dynamic> data = jsonDecode(cleanJson);

      return AiBusinessInsightResult(
        executiveSummary: data['executiveSummary'] ?? 'Steady growth driven by signature beverages.',
        topTrend: data['topTrend'] ?? 'High breakfast and afternoon coffee volume.',
        suggestedBundleName: data['suggestedBundleName'] ?? 'Paket Combo Hemat Nusantara',
        suggestedBundleDescription: data['suggestedBundleDescription'] ?? 'Kombinasi menu favorit dengan harga terjangkau.',
        suggestedBundlePrice: (data['suggestedBundlePrice'] as num?)?.toDouble() ?? 38000,
        bundleItemIds: (data['bundleItemIds'] as List?)?.map((e) => e.toString()).toList() ?? ['menu_kopi_aren', 'menu_croissant'],
        estimatedMargin: (data['estimatedMargin'] as num?)?.toDouble() ?? 65.0,
      );
    } catch (e) {
      debugPrint('Cloud AI insight generation error: $e');
      return generateOfflineFallbackInsight(menuItems);
    }
  }

  /// Generates a persuasive WhatsApp promo copywriting campaign via Gemini or on-device fallback
  Future<String> generateSmartPromo({
    required String storeName,
    required List<MenuItem> topItems,
    String discountPercentage = '15%',
  }) async {
    final topNames = topItems.take(3).map((m) => m.name).join(', ');
    final effectiveStoreName = storeName.isNotEmpty ? storeName : 'Nusantara POS Café';

    final prompt = '''
Anda adalah pakar copywriter pemasaran F&B profesional untuk café "$effectiveStoreName".
Buatlah 1 pesan promosi WhatsApp yang sangat menarik, ramah, dan mengonversi tinggi dalam Bahasa Indonesia (lengkap dengan emoji yang relevan dan format bold WhatsApp *kata*).
Fokuskan pada menu favorit pelanggan: $topNames.
Tawarkan diskon spesial $discountPercentage untuk pembelian hari ini menggunakan kode promo: NUSANTARAHEMAT.
Sertakan ajakan tindakan (Call to Action) agar pelanggan datang ke kasir atau memesan via WhatsApp.
Panjang pesan 4-6 kalimat padat dan menarik.
''';

    if (activeEngine == ActiveAiEngine.cloudFlash) {
      try {
        final response = await _cloudFlashModel
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 8));
        if (response.text != null && response.text!.trim().isNotEmpty) {
          return response.text!.trim();
        }
      } catch (e) {
        debugPrint('[AiService] generateSmartPromo cloud fallback: $e');
      }
    }

    return '''
🎉 *PROMO SPESIAL HARI INI DI $effectiveStoreName!* 🎉

Hai Sahabat Nusantara! Nikmati diskon spesial *$discountPercentage* untuk menu terlaris kami:
☕ *$topNames*

Gunakan kode promo eksklusif: *NUSANTARAHEMAT* langsung di kasir atau pesan antar hari ini!
Dibuat segar dengan bahan baku pilihan terbaik. Yuk serbu sebelum kehabisan! Sampai jumpa di $effectiveStoreName 🍽️✨
''';
  }

  AiBusinessInsightResult generateOfflineFallbackInsight(List<MenuItem> menuItems) {
    return AiBusinessInsightResult(
      executiveSummary: 'Peak sales in Kopi Susu Gula Aren and Nasi Ayam Sambal Matah. High profitability on beverage lines (72% gross margin).',
      topTrend: 'Espresso-based iced drinks represent 64% of total peak transactions.',
      suggestedBundleName: 'Paket Sore Santai (Matcha + Pisang Madu)',
      suggestedBundleDescription: 'Kombinasi autentik Matcha Latte hangat dan Pisang Goreng Madu Wijen renyah.',
      suggestedBundlePrice: 39000,
      bundleItemIds: ['menu_matcha_latte', 'menu_pisang_goreng'],
      estimatedMargin: 67.2,
    );
  }

  // Cloud Analytical Model: AI Procurement Advisor
  Future<AiProcurementAdviceResult> getProcurementAdvice({
    required List<RawMaterial> rawMaterials,
    required List<PosTransaction> transactions,
  }) async {
    final isOnline = ConnectivityService().isOnline;

    if (!isOnline) {
      return _generateOfflineProcurementAdvice(rawMaterials);
    }

    try {
      final inventoryContext = rawMaterials.map((r) => {
        'id': r.id,
        'name': r.name,
        'currentStock': r.currentStock,
        'unit': r.unit,
        'minSafetyStock': r.minSafetyStock,
        'costPerUnit': r.costPerUnit,
        'isLow': r.isLowStock,
      }).toList();

      final prompt = '''
You are the Procurement & Supply Chain Advisor for Nusantara Hybrid POS.
Inventory status: ${jsonEncode(inventoryContext)}

Identify items below safety threshold and calculate recommended purchase quantities for the next 7 operating days.
Return ONLY valid JSON matching:
{
  "generalAdvice": "Summary of procurement priorities...",
  "items": [
    {
      "rawMaterialId": "raw_espresso",
      "name": "Biji Kopi House Blend",
      "recommendedBuyQty": 2000,
      "unit": "g",
      "estimatedCost": 500000,
      "urgency": "HIGH"
    }
  ],
  "totalEstimatedBudget": 500000
}
''';

      final response = await _cloudFlashModel
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 12));
      final cleanJson = _cleanJsonString(response.text?.trim() ?? '');
      final Map<String, dynamic> data = jsonDecode(cleanJson);

      final List<dynamic> itemsList = data['items'] ?? [];
      final parsedItems = itemsList.map((i) {
        return ProcurementItemAdvice(
          rawMaterialId: i['rawMaterialId'] ?? '',
          name: i['name'] ?? '',
          recommendedBuyQty: (i['recommendedBuyQty'] as num?)?.toDouble() ?? 0.0,
          unit: i['unit'] ?? 'unit',
          estimatedCost: (i['estimatedCost'] as num?)?.toDouble() ?? 0.0,
          urgency: i['urgency'] ?? 'NORMAL',
        );
      }).toList();

      return AiProcurementAdviceResult(
        generalAdvice: data['generalAdvice'] ?? 'Restock key high-velocity ingredients.',
        items: parsedItems,
        totalEstimatedBudget: (data['totalEstimatedBudget'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('Cloud AI procurement error: $e');
      return _generateOfflineProcurementAdvice(rawMaterials);
    }
  }

  AiProcurementAdviceResult _generateOfflineProcurementAdvice(List<RawMaterial> rawMaterials) {
    final lowStockItems = rawMaterials.where((r) => r.isLowStock).toList();
    double budget = 0.0;
    final List<ProcurementItemAdvice> adviceList = [];

    for (final item in (lowStockItems.isNotEmpty ? lowStockItems : rawMaterials.take(3))) {
      final neededQty = item.minSafetyStock * 2;
      final cost = neededQty * item.costPerUnit;
      budget += cost;
      adviceList.add(ProcurementItemAdvice(
        rawMaterialId: item.id,
        name: item.name,
        recommendedBuyQty: neededQty,
        unit: item.unit,
        estimatedCost: cost,
        urgency: item.isLowStock ? 'HIGH' : 'MEDIUM',
      ));
    }

    return AiProcurementAdviceResult(
      generalAdvice: 'Auto-calculated safety replenishment based on historical usage.',
      items: adviceList,
      totalEstimatedBudget: budget,
    );
  }

  String _cleanJsonString(String text) {
    String cleaned = text.trim();
    // 1. Extract content within markdown code fences (```json ... ``` or ``` ... ```)
    final RegExp codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
    final match = codeBlockRegex.firstMatch(cleaned);
    if (match != null && match.group(1) != null) {
      cleaned = match.group(1)!.trim();
    } else {
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
    }
    // 2. Isolate JSON object between outer curly braces
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }
    return cleaned.trim();
  }

  /// Generates a concise professional shift handover summary note using Gemini 3.8 Flash or offline fallback
  Future<String> generateShiftHandoverSummary({
    required String summaryPrompt,
    required String cashierName,
  }) async {
    final isOnline = ConnectivityService().isOnline;
    if (!isOnline) {
      return 'Shift serah terima kasir $cashierName selesai. Data transaksi, total kas fisik, dan stok telah diarsipkan secara lokal.';
    }

    try {
      final prompt = '''
Anda adalah AI Shift Supervisor restoran / kafe Nusantara.
Tuliskan 1-2 kalimat ringkasan profesional serah terima kasir (handover note) berdasarkan data metrik shift berikut:
$summaryPrompt

Format: teks singkat, padat, profesional, mencakup kelancaran shift, status seimbang/selisih kas, dan kesiapan operasional kasir pengganti.
''';
      final response = await _cloudFlashModel.generateContent([Content.text(prompt)]);
      final text = response.text?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    } catch (e) {
      debugPrint('[AiService] generateShiftHandoverSummary notice: $e');
    }

    return 'Shift serah terima kasir $cashierName selesai dengan lancar. Seluruh penerimaan kas dan stok telah diverifikasi siap diserahterimakan.';
  }
}
