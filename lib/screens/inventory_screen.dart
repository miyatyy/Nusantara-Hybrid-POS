import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/raw_material.dart';
import '../models/transaction_model.dart';
import '../models/procurement_log.dart';
import '../services/localization_service.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

class InventoryScreen extends StatefulWidget {
  final List<RawMaterial> rawMaterials;
  final List<PosTransaction> transactions;

  const InventoryScreen({
    super.key,
    required this.rawMaterials,
    required this.transactions,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final FirestoreService _firestore = FirestoreService();
  final AiService _ai = AiService();
  bool _isLoadingAdvice = false;
  AiProcurementAdviceResult? _aiAdvice;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.iceBlueScaffold,
      appBar: AppBar(
        title: Text(
          tr('inventory_title'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.royalBlue,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Procurement Advisor Button & Result Card
            _buildAiAdvisorSection(currencyFormatter),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Raw Materials Stock (${widget.rawMaterials.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Auto-Deducts on POS Checkout',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Raw Materials List
            ...widget.rawMaterials.map((material) {
              final isLow = material.isLowStock;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLow ? AppTheme.roseRed.withAlpha(160) : AppTheme.cardBorder,
                    width: isLow ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isLow ? AppTheme.roseRed.withAlpha(15) : AppTheme.royalBlue.withAlpha(10),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isLow
                            ? AppTheme.roseRed.withAlpha(20)
                            : AppTheme.blueSubtle,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
                        color: isLow ? AppTheme.roseRed : AppTheme.royalBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            material.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tr('current_stock')}: ${material.currentStock.toStringAsFixed(0)} ${material.unit} (Min: ${material.minSafetyStock.toStringAsFixed(0)})',
                            style: TextStyle(
                              fontSize: 11,
                              color: isLow ? AppTheme.roseRed : Colors.grey.shade700,
                              fontWeight: isLow ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          Text(
                            '${tr('supplier_cost')}: ${currencyFormatter.format(material.costPerUnit)}/${material.unit}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openRestockDialog(material),
                      icon: const Icon(Icons.add_rounded, size: 14, color: AppTheme.darkNavy),
                      label: Text(
                        tr('restock_btn'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.goldenAmber,
                        foregroundColor: AppTheme.darkNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),
            // Recent Procurement Logs Stream
            const Text(
              'Recent Supplier Inbound Logs',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.royalBlue,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<ProcurementLog>>(
              stream: _firestore.streamProcurementLogs(),
              builder: (context, snap) {
                final logs = snap.data ?? [];
                if (logs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Center(
                      child: Text(
                        'No procurement logs yet. Tap "+ Log Stock-In" above.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length > 5 ? 5 : logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(log.timestamp);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.local_shipping_rounded, size: 22, color: AppTheme.royalBlue),
                        title: Text(
                          '+${log.quantityAdded} ${log.unit} ${log.rawMaterialName}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                        ),
                        subtitle: Text('${log.supplier} • $dateStr', style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          currencyFormatter.format(log.costTotal),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.royalBlue),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiAdvisorSection(NumberFormat currencyFormatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.royalBlue, Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.brightYellow.withAlpha(160)),
                ),
                child: const Icon(Icons.psychology_rounded, color: AppTheme.brightYellow, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('ai_procurement_btn'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Automated inventory replenishment powered by Gemini 3.8 Flash',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingAdvice
                  ? null
                  : () async {
                      setState(() => _isLoadingAdvice = true);
                      try {
                        final advice = await _ai.getProcurementAdvice(
                          rawMaterials: widget.rawMaterials,
                          transactions: widget.transactions,
                        );
                        setState(() => _aiAdvice = advice);
                      } finally {
                        setState(() => _isLoadingAdvice = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldenAmber,
                foregroundColor: AppTheme.darkNavy,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isLoadingAdvice
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkNavy),
                    )
                  : const Icon(Icons.auto_awesome, size: 16, color: AppTheme.darkNavy),
              label: Text(
                _isLoadingAdvice ? 'Analyzing burn rates...' : 'Run AI Procurement Advisor',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppTheme.darkNavy),
              ),
            ),
          ),

          if (_aiAdvice != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _aiAdvice!.generalAdvice,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  const Divider(height: 16),
                  ..._aiAdvice!.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.urgency == 'HIGH'
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.urgency,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: item.urgency == 'HIGH'
                                    ? AppTheme.roseRed
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item.name}: +${item.recommendedBuyQty.toStringAsFixed(0)} ${item.unit}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                            ),
                          ),
                          Text(
                            currencyFormatter.format(item.estimatedCost),
                            style: const TextStyle(fontSize: 11, color: AppTheme.royalBlue, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Estimated Budget:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                      ),
                      Text(
                        currencyFormatter.format(_aiAdvice!.totalEstimatedBudget),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openRestockDialog(RawMaterial material) {
    final qtyCtrl = TextEditingController(text: material.minSafetyStock.toStringAsFixed(0));
    final supplierCtrl = TextEditingController(text: 'Mitra Nusantara F&B');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restock ${material.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity to Add (${material.unit})',
              ),
            ),
            TextField(
              controller: supplierCtrl,
              decoration: const InputDecoration(labelText: 'Supplier Name'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.royalBlue),
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
              final costTotal = qty * material.costPerUnit;

              Navigator.pop(ctx);
              await _firestore.logProcurementRestock(
                rawMaterialId: material.id,
                rawMaterialName: material.name,
                quantityAdded: qty,
                unit: material.unit,
                costTotal: costTotal,
                supplier: supplierCtrl.text.trim(),
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.royalBlue,
                    behavior: SnackBarBehavior.floating,
                    content: Text('Restocked +$qty ${material.unit} of ${material.name}'),
                  ),
                );
              }
            },
            child: const Text('Confirm Restock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
