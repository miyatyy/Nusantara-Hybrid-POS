import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/menu_item.dart';
import '../models/raw_material.dart';
import '../services/localization_service.dart';
import '../services/menu_catalog_service.dart';
import '../services/menu_availability_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_image_banner.dart';

class MenuScreen extends StatefulWidget {
  final List<MenuItem> menuItems;
  final List<RawMaterial> rawMaterials;

  const MenuScreen({
    super.key,
    required this.menuItems,
    required this.rawMaterials,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _selectedCategory = 'All';

  Map<String, RawMaterial> get _rawStockMap =>
      {for (var r in widget.rawMaterials) r.id: r};

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final categories = ['All', 'Minuman', 'Makanan', 'Cemilan', 'Paket'];

    return AnimatedBuilder(
      animation: Listenable.merge([MenuCatalogService(), MenuAvailabilityNotifier()]),
      builder: (context, _) {
        final currentItems = MenuCatalogService().items.isNotEmpty
            ? MenuCatalogService().items
            : widget.menuItems;
        final filtered = currentItems.where((m) {
          if (_selectedCategory == 'All') return true;
          return m.category.toLowerCase() == _selectedCategory.toLowerCase();
        }).toList();

    return Scaffold(
      backgroundColor: AppTheme.iceBlueScaffold,
      appBar: AppBar(
        title: Text(
          tr('menu_management_title'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.royalBlue,
        elevation: 0.5,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16, color: AppTheme.darkNavy),
              label: Text(
                tr('add_menu_item'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldenAmber,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openAddEditDialog(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Category selector chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: AppTheme.royalBlue,
                      backgroundColor: Colors.grey.shade100,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : AppTheme.darkNavy,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppTheme.royalBlue : AppTheme.cardBorder,
                      ),
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Menu list with BOM Recipe details
          Expanded(
            child: ValueListenableBuilder<Map<String, MenuOverrideState>>(
              valueListenable: MenuAvailabilityNotifier(),
              builder: (context, overrides, _) {
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final isSoldOut = MenuAvailabilityNotifier().isItemSoldOut(item, _rawStockMap);
                    final isReady = !isSoldOut;
                    final cogs = item.calculateCostOfGoods(_rawStockMap);
                    final margin = item.price > 0
                        ? ((item.price - cogs) / item.price) * 100
                        : 0.0;

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      child: ExpansionTile(
                        shape: const Border(),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: MenuImageBanner(
                              imageUrl: item.imageUrl,
                              category: item.category,
                              iconEmoji: item.iconEmoji,
                              height: 52,
                              borderRadius: BorderRadius.circular(10),
                              isSoldOut: isSoldOut,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.darkNavy,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isReady
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isReady ? 'Ready' : tr('stock_out'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isReady
                                      ? const Color(0xFF15803D)
                                      : AppTheme.roseRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          '${item.category} • ${currencyFormatter.format(item.price)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.royalBlue,
                          ),
                        ),
                        Text(
                          '${tr('cost_of_goods')}: ${currencyFormatter.format(cogs)} • ${tr('margin')}: ${margin.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        color: AppTheme.lightBlueTint.withAlpha(120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('bom_recipe'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.royalBlue,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (item.recipe.isEmpty)
                              Text(
                                'No raw ingredients configured.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else
                              ...item.recipe.entries.map((e) {
                                final mat = _rawStockMap[e.key];
                                final matName = mat?.name ?? e.key;
                                final unit = mat?.unit ?? '';
                                final cost = (mat?.costPerUnit ?? 0) * e.value;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '• $matName',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.darkNavy),
                                        ),
                                      ),
                                      Text(
                                        '${e.value} $unit (${currencyFormatter.format(cost)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _openAddEditDialog(item),
                                  icon: const Icon(Icons.edit, size: 14),
                                  label: const Text('Edit Item', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.royalBlue,
                                    side: const BorderSide(color: AppTheme.royalBlue),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.roseRed, size: 20),
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(item),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
        ],
      ),
    );
      },
    );
  }

  void _confirmDelete(MenuItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: const Text('Are you sure you want to remove this item from POS?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.roseRed),
            onPressed: () async {
              Navigator.pop(ctx);
              await MenuCatalogService().deleteMenuItem(item.id);
              if (mounted) setState(() {});
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openAddEditDialog([MenuItem? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final nameEnCtrl = TextEditingController(text: existing?.nameEn ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toStringAsFixed(0) ?? '25000');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final imgCtrl = TextEditingController(text: existing?.imageUrl ?? '');
    String category = existing?.category ?? 'Makanan';
    String iconEmoji = existing?.iconEmoji ?? '🍽️';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Menu Item' : 'Edit Menu Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Menu Name (ID)'),
                  ),
                  TextField(
                    controller: nameEnCtrl,
                    decoration: const InputDecoration(labelText: 'Menu Name (EN)'),
                  ),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (IDR)'),
                  ),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: imgCtrl,
                    decoration: const InputDecoration(labelText: 'Image URL (Optional)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: ['Makanan', 'Minuman', 'Cemilan', 'Paket'].map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: iconEmoji,
                    decoration: const InputDecoration(labelText: 'Icon Emoji'),
                    items: ['☕', '🍵', '🧋', '🍛', '🍳', '🥐', '🍌', '⭐', '🍽️'].map((e) {
                      return DropdownMenuItem(value: e, child: Text('$e  $e'));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => iconEmoji = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue),
                onPressed: () async {
                  final price = double.tryParse(priceCtrl.text) ?? 20000;
                  final item = MenuItem(
                    id: existing?.id ?? '',
                    name: nameCtrl.text.trim(),
                    nameEn: nameEnCtrl.text.trim(),
                    category: category,
                    price: price,
                    description: descCtrl.text.trim(),
                    recipe: existing?.recipe ?? {},
                    iconEmoji: iconEmoji,
                    imageUrl: imgCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                  await MenuCatalogService().saveMenuItem(item);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF15803D),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Menu "${item.name}" saved successfully!',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
