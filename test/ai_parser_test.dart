import 'package:flutter_test/flutter_test.dart';
import 'package:nusantara_hybrid_pos/services/firestore_service.dart';
import 'package:nusantara_hybrid_pos/services/ai_service.dart';

void main() {
  final ai = AiService();
  final defaultItems = FirestoreService.defaultSeedMenuItems;

  group('Nusantara AI Smart Order Parser Rigorous Verification', () {
    test('Sample Prompt 1: 2 Palm Sugar Latte less ice, 1 Croissant, cash 100k', () async {
      final res = await ai.parseNaturalOrder(
        prompt: '2 Palm Sugar Latte less ice, 1 Croissant, cash 100k',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      // Must have exactly 2 items: Kopi Aren (qty 2, less ice) and Croissant (qty 1)
      // Must NOT contain Paket Sarapan or Nasi Goreng
      expect(res.cashReceived, 100000.0);
      expect(res.items.length, 2);

      final latte = res.items.firstWhere((i) => i.menuItem.id == 'menu_kopi_aren');
      expect(latte.quantity, 2);
      expect(latte.notes.toLowerCase().contains('ice'), true);

      final croissant = res.items.firstWhere((i) => i.menuItem.id == 'menu_croissant');
      expect(croissant.quantity, 1);
      expect(croissant.notes, ''); // notes should NOT bleed into croissant
    });

    test('Sample Prompt 2: 1 Nasi Ayam Sambal Matah, 1 Es Teh Melati', () async {
      final res = await ai.parseNaturalOrder(
        prompt: '1 Nasi Ayam Sambal Matah, 1 Es Teh Melati',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      // Must have exactly 2 items: Nasi Ayam Matah and Es Teh Melati
      // Must NOT match Nasi Goreng
      expect(res.items.length, 2);

      final ayam = res.items.firstWhere((i) => i.menuItem.id == 'menu_ayam_matah');
      expect(ayam.quantity, 1);

      final teh = res.items.firstWhere((i) => i.menuItem.id == 'menu_iced_tea');
      expect(teh.quantity, 1);

      expect(res.items.any((i) => i.menuItem.id == 'menu_nasgor_spesial'), false);
    });

    test('Sample Prompt 3: 2 Kyoto Matcha Latte, 1 Pisang Madu, bayar 100rb', () async {
      final res = await ai.parseNaturalOrder(
        prompt: '2 Kyoto Matcha Latte, 1 Pisang Madu, bayar 100rb',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      expect(res.cashReceived, 100000.0);
      expect(res.items.length, 2);

      final matcha = res.items.firstWhere((i) => i.menuItem.id == 'menu_matcha_latte');
      expect(matcha.quantity, 2);

      final pisang = res.items.firstWhere((i) => i.menuItem.id == 'menu_pisang_goreng');
      expect(pisang.quantity, 1);

      // Must NOT match Nasi Goreng
      expect(res.items.any((i) => i.menuItem.id == 'menu_nasgor_spesial'), false);
    });

    test('Sample Prompt 4: 1 Paket Semangat Pagi, cash 50k', () async {
      final res = await ai.parseNaturalOrder(
        prompt: '1 Paket Semangat Pagi, cash 50k',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      expect(res.cashReceived, 50000.0);
      expect(res.items.length, 1);
      expect(res.items.first.menuItem.id, 'bundle_sarapan');
      expect(res.items.first.quantity, 1);
    });

    test('Indonesian natural order: kopi susu 2 sedikit es sama 1 pisang goreng', () async {
      final res = await ai.parseNaturalOrder(
        prompt: 'kopi susu 2 sedikit es sama 1 pisang goreng',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      expect(res.items.length, 2);
      final kopi = res.items.firstWhere((i) => i.menuItem.id == 'menu_kopi_aren');
      expect(kopi.quantity, 2);

      final pisang = res.items.firstWhere((i) => i.menuItem.id == 'menu_pisang_goreng');
      expect(pisang.quantity, 1);

      expect(res.items.any((i) => i.menuItem.id == 'menu_nasgor_spesial'), false);
      expect(res.items.any((i) => i.menuItem.id == 'bundle_sarapan'), false);
    });

    test('Indonesian natural order without punctuation: 2 es teh 1 nasi goreng bayar 50rb', () async {
      final res = await ai.parseNaturalOrder(
        prompt: '2 es teh 1 nasi goreng bayar 50rb',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      expect(res.cashReceived, 50000.0);
      expect(res.items.length, 2);

      final teh = res.items.firstWhere((i) => i.menuItem.id == 'menu_iced_tea');
      expect(teh.quantity, 2);

      final nasgor = res.items.firstWhere((i) => i.menuItem.id == 'menu_nasgor_spesial');
      expect(nasgor.quantity, 1);

      expect(res.items.any((i) => i.menuItem.id == 'menu_ayam_matah'), false);
      expect(res.items.any((i) => i.menuItem.id == 'menu_pisang_goreng'), false);
    });

    test('Indonesian word numbers: dua kopi aren dan satu croissant', () async {
      final res = await ai.parseNaturalOrder(
        prompt: 'dua kopi aren dan satu croissant',
        menuItems: defaultItems,
        rawStockMap: {},
        mode: InferenceMode.onlyOnDevice,
      );

      expect(res.items.length, 2);
      final kopi = res.items.firstWhere((i) => i.menuItem.id == 'menu_kopi_aren');
      expect(kopi.quantity, 2);

      final croissant = res.items.firstWhere((i) => i.menuItem.id == 'menu_croissant');
      expect(croissant.quantity, 1);
    });
  });
}
