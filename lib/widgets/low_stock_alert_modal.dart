import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/raw_material.dart';
import '../models/menu_item.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Modal listing all low-stock / depleted raw materials, affected recipes/menu items,
/// and providing 1-tap quick restock buttons.
class LowStockAlertModal extends StatefulWidget {
  final List<RawMaterial> rawMaterials;
  final List<MenuItem> menuItems;

  const LowStockAlertModal({
    super.key,
    required this.rawMaterials,
    required this.menuItems,
  });

  static Future<void> show(
    BuildContext context, {
    required List<RawMaterial> rawMaterials,
    required List<MenuItem> menuItems,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LowStockAlertModal(
        rawMaterials: rawMaterials,
        menuItems: menuItems,
      ),
    );
  }

  @override
  State<LowStockAlertModal> createState() => _LowStockAlertModalState();
}

class _LowStockAlertModalState extends State<LowStockAlertModal> {
  final FirestoreService _firestore = FirestoreService();
  String? _restockingId;

  Future<void> _handleRestock(RawMaterial material) async {
    setState(() => _restockingId = material.id);
    HapticFeedback.mediumImpact();

    // Default restock amounts based on unit type
    final double restockQty = material.unit.toLowerCase().contains('g') ||
            material.unit.toLowerCase().contains('gr') ||
            material.unit.toLowerCase().contains('ml')
        ? 1000.0
        : 50.0;

    final double totalCost = (restockQty * material.costPerUnit).clamp(10000.0, 500000.0);

    try {
      await _firestore.logProcurementRestock(
        rawMaterialId: material.id,
        rawMaterialName: material.name,
        quantityAdded: restockQty,
        unit: material.unit,
        costTotal: totalCost,
        supplier: 'Fast Restock (Alert Modal)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Restocked +${restockQty.toInt()} ${material.unit} ${material.name}!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Restock failed: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _restockingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowMaterials = widget.rawMaterials.where((r) => r.isLowStock).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppTheme.roseRed,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Low-Stock Alert',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                      Text(
                        '${lowMaterials.length} raw material(s) reached minimum threshold',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: lowMaterials.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 54,
                            color: Color(0xFF15803D),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'All Raw Material Stocks Safe!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No raw materials are currently below the minimum threshold.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: lowMaterials.length,
                    itemBuilder: (context, index) {
                      final mat = lowMaterials[index];
                      final isRestocking = _restockingId == mat.id;

                      // Affected menu items
                      final affected = widget.menuItems.where((m) {
                        return m.recipe.containsKey(mat.id);
                      }).toList();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFDBA74),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.goldenAmber.withAlpha(20),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFED7AA),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFC2410C),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mat.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.darkNavy,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            'Sisa: ${mat.currentStock.toStringAsFixed(0)} ${mat.unit}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.roseRed,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '(Batas: ${mat.minThreshold.toStringAsFixed(0)} ${mat.unit})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: isRestocking ? null : () => _handleRestock(mat),
                                  icon: isRestocking
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.add_shopping_cart_rounded, size: 14),
                                  label: const Text(
                                    'Restock Now',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.goldenAmber,
                                    foregroundColor: AppTheme.darkNavy,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                            if (affected.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.orange.shade200),
                                ),
                                child: Text(
                                  'Menu Terdampak: ${affected.map((m) => m.name).join(', ')}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF9A3412),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
