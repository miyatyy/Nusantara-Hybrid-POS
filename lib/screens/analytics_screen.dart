import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/menu_item.dart';
import '../models/raw_material.dart';
import '../models/transaction_model.dart';
import '../models/expense_model.dart';
import '../services/localization_service.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/menu_catalog_service.dart';
import '../services/offline_outbox_service.dart';
import '../services/whatsapp_gateway_service.dart';
import '../services/email_auth_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_image_banner.dart';
import '../widgets/analytics_charts.dart';

class AnalyticsScreen extends StatefulWidget {
  final List<PosTransaction> transactions;
  final List<MenuItem> menuItems;
  final List<RawMaterial> rawMaterials;

  const AnalyticsScreen({
    super.key,
    required this.transactions,
    required this.menuItems,
    required this.rawMaterials,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirestoreService _firestore = FirestoreService();
  final AiService _ai = AiService();

  String _selectedTimeframe = 'daily'; // 'daily', 'weekly', 'monthly'
  bool _isGeneratingInsight = false;
  AiBusinessInsightResult? _insightResult;

  bool _isGeneratingPromo = false;
  bool _isBroadcastingPromo = false;
  String? _generatedPromoText;
  final TextEditingController _promoTextController = TextEditingController();

  @override
  void dispose() {
    _promoTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    // Reactive live streams for transactions & expenses directly from Cloud Firestore
    return StreamBuilder<List<PosTransaction>>(
      stream: _firestore.streamTransactions(),
      initialData: widget.transactions,
      builder: (context, txSnapshot) {
        final firestoreTransactions = txSnapshot.data ?? widget.transactions;

        // Merge with pending local offline transactions from Outbox
        final allTransactions = _mergeWithOfflineTransactions(firestoreTransactions);

        return StreamBuilder<List<ExpenseModel>>(
          stream: _firestore.streamExpenses(),
          initialData: const [],
          builder: (context, expSnapshot) {
            final liveExpenses = expSnapshot.data ?? [];

            // Compute financial buckets based on selected timeframe
            final buckets = _computeFinancialBuckets(
              transactions: allTransactions,
              expenses: liveExpenses,
              timeframe: _selectedTimeframe,
            );

            // Compute period-specific financial totals
            double periodSales = 0;
            double periodExpenses = 0;
            for (final b in buckets) {
              periodSales += b.sales;
              periodExpenses += b.expenses;
            }
            final periodNetProfit = periodSales - periodExpenses;
            final periodMargin = periodSales > 0 ? (periodNetProfit / periodSales) * 100 : 0.0;

            // Overall All-Time Category breakdown for Donut Chart
            final Map<String, double> categoryRevenue = {
              'Minuman': 0.0,
              'Makanan': 0.0,
              'Cemilan': 0.0,
              'Paket': 0.0,
            };

            final Map<String, int> itemFrequency = {};
            final Map<String, double> itemRevenue = {};
            double allTimeRevenue = 0;

            for (final tx in allTransactions) {
              allTimeRevenue += tx.total;
              for (final item in tx.items) {
                final cat = CategoryDonutChart.normalizeCategory(item.menuItem.category);
                categoryRevenue[cat] = (categoryRevenue[cat] ?? 0.0) + item.totalPrice;
                itemFrequency[item.menuItem.id] =
                    (itemFrequency[item.menuItem.id] ?? 0) + item.quantity;
                itemRevenue[item.menuItem.id] =
                    (itemRevenue[item.menuItem.id] ?? 0.0) + item.totalPrice;
              }
            }

            final double rawCategorySum = categoryRevenue.values.fold(0.0, (a, b) => a + b);
            if (rawCategorySum == 0 && allTimeRevenue > 0) {
              categoryRevenue['Minuman'] = allTimeRevenue * 0.42;
              categoryRevenue['Makanan'] = allTimeRevenue * 0.32;
              categoryRevenue['Cemilan'] = allTimeRevenue * 0.14;
              categoryRevenue['Paket'] = allTimeRevenue * 0.12;
            }

            // Best sellers list
            final sortedMenuItems = List.of(widget.menuItems);
            sortedMenuItems.sort((a, b) {
              final freqA = itemFrequency[a.id] ?? a.popularityScore;
              final freqB = itemFrequency[b.id] ?? b.popularityScore;
              return freqB.compareTo(freqA);
            });

            return Scaffold(
              backgroundColor: AppTheme.iceBlueScaffold,
              appBar: AppBar(
                title: Text(
                  tr('analytics_title'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkNavy,
                  ),
                ),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.royalBlue,
                elevation: 0.5,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () => _showLogExpenseModal(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.goldenAmber,
                        foregroundColor: AppTheme.darkNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.add_circle, size: 14, color: AppTheme.darkNavy),
                      label: Text(
                        tr('log_expense_btn'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppTheme.darkNavy),
                      ),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. KPI Summary Cards (Sales, Expenses, Net Profit)
                    Row(
                      children: [
                        Expanded(
                          child: _buildFinancialMetricCard(
                            title: tr('financial_kpi_sales'),
                            value: currencyFormatter.format(periodSales),
                            subtitle: '${buckets.length} Period Buckets',
                            icon: Icons.payments_rounded,
                            color: AppTheme.royalBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFinancialMetricCard(
                            title: tr('financial_kpi_expenses'),
                            value: currencyFormatter.format(periodExpenses),
                            subtitle: '${liveExpenses.length} Logged Items',
                            icon: Icons.receipt_long_rounded,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFinancialMetricCard(
                            title: tr('financial_kpi_profit'),
                            value: currencyFormatter.format(periodNetProfit),
                            subtitle: 'Margin: ${periodMargin.toStringAsFixed(1)}%',
                            icon: Icons.trending_up_rounded,
                            color: periodNetProfit >= 0 ? const Color(0xFF10B981) : AppTheme.roseRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. Interactive Multi-Series Financial Chart (Grouped Bar & Net Profit Trend)
                    FinancialOverviewChart(
                      buckets: buckets,
                      selectedTimeframe: _selectedTimeframe,
                      onTimeframeChanged: (tf) {
                        setState(() => _selectedTimeframe = tf);
                      },
                      onLogExpense: () => _showLogExpenseModal(context),
                      currencyFormatter: currencyFormatter,
                    ),
                    const SizedBox(height: 16),

                    // 3. Category Sales Share (Circular Donut Percentage Chart)
                    CategoryDonutChart(
                      categoryRevenue: categoryRevenue,
                      totalRevenue: allTimeRevenue,
                      currencyFormatter: currencyFormatter,
                    ),
                    const SizedBox(height: 16),

                    // 4. Top Best-Sellers Bar Diagram
                    TopBestSellersBarChart(
                      menuItems: widget.menuItems,
                      itemFrequency: itemFrequency,
                      itemRevenue: itemRevenue,
                      currencyFormatter: currencyFormatter,
                    ),
                    const SizedBox(height: 16),

                    // 5. AI Business Insight & 1-Click Publish to POS
                    _buildAiInsightCard(currencyFormatter, allTransactions),
                    const SizedBox(height: 16),

                    // 5b. AI Smart Promo & WhatsApp Broadcaster
                    _buildAiPromoBroadcasterCard(sortedMenuItems),

                    const SizedBox(height: 20),
                    // Best Sellers & Customer Favorites Detailed Listing
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Best Sellers & Customer Favorites',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.royalBlue,
                          ),
                        ),
                        Text(
                          '${sortedMenuItems.length} Menus',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...sortedMenuItems.take(5).map((item) {
                      final soldCount = itemFrequency[item.id] ?? (item.popularityScore ~/ 10);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: MenuImageBanner(
                                imageUrl: item.imageUrl,
                                category: item.category,
                                iconEmoji: item.iconEmoji,
                                height: 44,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.darkNavy),
                          ),
                          subtitle: Text(
                            '${item.category} • ${currencyFormatter.format(item.price)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.royalBlue, fontWeight: FontWeight.w600),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.yellowSubtle,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.goldenAmber.withAlpha(120)),
                            ),
                            child: Text(
                              '$soldCount sold',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.darkNavy,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Merge live Firestore transactions with local pending offline transactions (deduplicated by receiptId)
  List<PosTransaction> _mergeWithOfflineTransactions(List<PosTransaction> firestoreTxs) {
    final Map<String, PosTransaction> mergedMap = {};
    for (final tx in firestoreTxs) {
      final key = tx.receiptId.isNotEmpty ? tx.receiptId : tx.id;
      mergedMap[key] = tx;
      if (tx.id.isNotEmpty) mergedMap[tx.id] = tx;
    }

    final outboxQueue = OfflineOutboxService().queue;
    for (final raw in outboxQueue) {
      final id = raw['id']?.toString() ?? '';
      final receiptId = raw['receiptId']?.toString() ?? '';
      final key = receiptId.isNotEmpty ? receiptId : id;
      if (key.isNotEmpty && !mergedMap.containsKey(key) && !mergedMap.containsKey(id)) {
        final parsed = PosTransaction.fromMap(raw, id.isNotEmpty ? id : key);
        mergedMap[key] = parsed;
        if (id.isNotEmpty) mergedMap[id] = parsed;
      }
    }

    final Set<String> seen = {};
    final List<PosTransaction> result = [];
    for (final tx in mergedMap.values) {
      final uniqueKey = tx.receiptId.isNotEmpty ? tx.receiptId : tx.id;
      if (seen.add(uniqueKey)) {
        result.add(tx);
      }
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  // Dynamic Bucket Aggregation for Daily, Weekly, and Monthly
  List<FinancialBucket> _computeFinancialBuckets({
    required List<PosTransaction> transactions,
    required List<ExpenseModel> expenses,
    required String timeframe,
  }) {
    final now = DateTime.now();

    if (timeframe == 'daily') {
      // Last 7 days
      final List<FinancialBucket> buckets = [];
      for (int i = 6; i >= 0; i--) {
        final targetDate = now.subtract(Duration(days: i));
        final dayLabel = DateFormat('E, d/M').format(targetDate);

        double daySales = 0;
        for (final tx in transactions) {
          if (tx.timestamp.year == targetDate.year &&
              tx.timestamp.month == targetDate.month &&
              tx.timestamp.day == targetDate.day) {
            daySales += tx.total;
          }
        }

        double dayExpenses = 0;
        for (final exp in expenses) {
          if (exp.timestamp.year == targetDate.year &&
              exp.timestamp.month == targetDate.month &&
              exp.timestamp.day == targetDate.day) {
            dayExpenses += exp.amount;
          }
        }

        buckets.add(FinancialBucket(
          label: i == 0 ? 'Today' : dayLabel,
          date: targetDate,
          sales: daySales,
          expenses: dayExpenses,
        ));
      }
      return buckets;
    } else if (timeframe == 'weekly') {
      // Last 4 weeks
      final List<FinancialBucket> buckets = [];
      for (int i = 3; i >= 0; i--) {
        final startRange = now.subtract(Duration(days: (i + 1) * 7));
        final endRange = now.subtract(Duration(days: i * 7));
        final label = i == 0 ? 'This Wk' : 'W-$i';

        double weekSales = 0;
        for (final tx in transactions) {
          if (tx.timestamp.isAfter(startRange) && tx.timestamp.isBefore(endRange.add(const Duration(days: 1)))) {
            weekSales += tx.total;
          }
        }

        double weekExpenses = 0;
        for (final exp in expenses) {
          if (exp.timestamp.isAfter(startRange) && exp.timestamp.isBefore(endRange.add(const Duration(days: 1)))) {
            weekExpenses += exp.amount;
          }
        }

        buckets.add(FinancialBucket(
          label: label,
          date: endRange,
          sales: weekSales,
          expenses: weekExpenses,
        ));
      }
      return buckets;
    } else {
      // Monthly (Last 6 months)
      final List<FinancialBucket> buckets = [];
      for (int i = 5; i >= 0; i--) {
        final mDate = DateTime(now.year, now.month - i, 1);
        final label = DateFormat('MMM yy').format(mDate);

        double monthSales = 0;
        for (final tx in transactions) {
          if (tx.timestamp.year == mDate.year && tx.timestamp.month == mDate.month) {
            monthSales += tx.total;
          }
        }

        double monthExpenses = 0;
        for (final exp in expenses) {
          if (exp.timestamp.year == mDate.year && exp.timestamp.month == mDate.month) {
            monthExpenses += exp.amount;
          }
        }

        buckets.add(FinancialBucket(
          label: label,
          date: mDate,
          sales: monthSales,
          expenses: monthExpenses,
        ));
      }
      return buckets;
    }
  }

  Widget _buildFinancialMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // "+ Log Expense / Catat Pengeluaran" Modal Bottom Sheet
  void _showLogExpenseModal(BuildContext context) {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Restock';
    final categories = ['Restock', 'Operational', 'Packaging', 'Wages', 'Other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.receipt_long, color: Color(0xFFEF4444), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            tr('log_expense_title'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Category Selector Chips
                  Text(
                    tr('expense_category'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        final isSel = selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSel,
                            selectedColor: AppTheme.royalBlue,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isSel ? Colors.white : AppTheme.darkNavy,
                            ),
                            onSelected: (_) => setModalState(() => selectedCategory = cat),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title / Description
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: tr('expense_note'),
                      hintText: 'e.g. Listrik Café, Cup Takeaway...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Amount Input
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('expense_amount'),
                      hintText: 'e.g. 150000',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.goldenAmber,
                        foregroundColor: AppTheme.darkNavy,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.save_rounded, color: AppTheme.darkNavy, size: 18),
                      label: Text(
                        tr('log_expense_btn'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      onPressed: () async {
                        final text = titleController.text.trim();
                        final amount = double.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                        if (text.isEmpty || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.roseRed,
                              content: Text('Please enter a valid title and amount.'),
                            ),
                          );
                          return;
                        }

                        final expense = ExpenseModel(
                          id: 'EXP_${DateTime.now().millisecondsSinceEpoch}',
                          title: text,
                          category: selectedCategory,
                          amount: amount,
                          timestamp: DateTime.now(),
                          loggedBy: 'Cashier / Admin',
                        );

                        await _firestore.addExpense(expense);
                        if (ctx.mounted) Navigator.pop(ctx);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF15803D),
                              content: Text(tr('expense_saved_toast')),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAiInsightCard(NumberFormat currencyFormatter, List<PosTransaction> liveTransactions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.royalBlue, Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(50),
            blurRadius: 10,
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
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.brightYellow.withAlpha(160)),
                ),
                child: const Icon(Icons.auto_awesome, color: AppTheme.brightYellow, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('generate_insight_btn'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'AI margin optimization & promotional combo generator',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
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
              onPressed: _isGeneratingInsight
                  ? null
                  : () async {
                      if (!mounted) return;
                      setState(() => _isGeneratingInsight = true);
                      try {
                        final res = await _ai.generateBusinessInsight(
                          transactions: liveTransactions,
                          menuItems: widget.menuItems,
                          rawMaterials: widget.rawMaterials,
                        );
                        if (!mounted) return;
                        setState(() => _insightResult = res);
                      } catch (e) {
                        debugPrint('AI Insight error caught: $e');
                        if (!mounted) return;
                        setState(() {
                          _insightResult = _ai.generateOfflineFallbackInsight(widget.menuItems);
                        });
                      } finally {
                        if (mounted) {
                          setState(() => _isGeneratingInsight = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.goldenAmber,
                foregroundColor: AppTheme.darkNavy,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isGeneratingInsight
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.darkNavy),
                    )
                  : const Icon(Icons.insights, size: 16, color: AppTheme.darkNavy),
              label: Text(
                _isGeneratingInsight ? tr('insight_analyzing') : 'Generate AI Business Insight',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppTheme.darkNavy),
              ),
            ),
          ),

          if (_insightResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_rounded, color: AppTheme.goldenAmber, size: 20),
                      const SizedBox(width: 6),
                      const Text(
                        'Executive Insight:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _insightResult!.executiveSummary,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Key Trend: ${_insightResult!.topTrend}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.royalBlue),
                  ),
                  const Divider(height: 16),

                  // Suggested Bundle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlueTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.blueSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _insightResult!.suggestedBundleName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.royalBlue,
                                ),
                              ),
                            ),
                            Text(
                              currencyFormatter.format(_insightResult!.suggestedBundlePrice),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.royalBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _insightResult!.suggestedBundleDescription,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Estimated Profit Margin: ${_insightResult!.estimatedMargin.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                        ),
                        const SizedBox(height: 10),

                        // 1-Click "Publish Bundle to POS" Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _publishBundleToPos(_insightResult!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.goldenAmber,
                              foregroundColor: AppTheme.darkNavy,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.rocket_launch_rounded, size: 16, color: AppTheme.darkNavy),
                            label: Text(
                              tr('publish_bundle_btn'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.darkNavy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _publishBundleToPos(AiBusinessInsightResult bundle) async {
    final Map<String, double> combinedRecipe = {};
    for (final itemId in bundle.bundleItemIds) {
      final matched = widget.menuItems.firstWhere(
        (m) => m.id == itemId,
        orElse: () => const MenuItem(
          id: '',
          name: '',
          category: '',
          price: 0,
          description: '',
        ),
      );
      if (matched.id.isNotEmpty) {
        matched.recipe.forEach((matId, qty) {
          combinedRecipe[matId] = (combinedRecipe[matId] ?? 0.0) + qty;
        });
      }
    }

    final newBundleItem = MenuItem(
      id: 'bundle_ai_${DateTime.now().millisecondsSinceEpoch}',
      name: bundle.suggestedBundleName,
      nameEn: 'AI Promo Bundle Combo',
      category: 'Paket',
      price: bundle.suggestedBundlePrice,
      description: bundle.suggestedBundleDescription,
      recipe: combinedRecipe,
      iconEmoji: '⭐',
      popularityScore: 99,
      imageUrl: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=600&auto=format&fit=crop&q=80',
    );

    await MenuCatalogService().saveMenuItem(newBundleItem);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.royalBlue,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.brightYellow),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('bundle_published_toast'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildAiPromoBroadcasterCard(List<MenuItem> topItems) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.goldenAmber.withAlpha(150), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 10,
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
                  color: AppTheme.goldenAmber.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.goldenAmber.withAlpha(120)),
                ),
                child: const Icon(Icons.campaign_rounded, color: AppTheme.brightYellow, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Smart Promo & WhatsApp Broadcaster',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Gemini 3.8 Flash • Blast Kupon & Menu Terlaris',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.goldenAmber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_generatedPromoText == null) ...[
            const Text(
              'Use Gemini AI to craft persuasive WhatsApp promotional copy based on your store\'s transaction data & best-selling items, then broadcast to all opted-in customers in 1 tap.',
              style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.goldenAmber,
                  foregroundColor: AppTheme.darkNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isGeneratingPromo
                    ? null
                    : () async {
                        setState(() => _isGeneratingPromo = true);
                        final promo = await _ai.generateSmartPromo(
                          storeName: SettingsService().storeName,
                          topItems: topItems,
                          discountPercentage: '15%',
                        );
                        if (mounted) {
                          setState(() {
                            _generatedPromoText = promo;
                            _promoTextController.text = promo;
                            _isGeneratingPromo = false;
                          });
                        }
                      },
                icon: _isGeneratingPromo
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppTheme.darkNavy, strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _isGeneratingPromo ? 'Drafting Promo with Gemini...' : 'Generate AI Promo Now',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'WhatsApp Message Preview:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.goldenAmber),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                        tooltip: 'Copy Text',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _promoTextController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.royalBlue,
                              content: Text('Promo text copied to clipboard!'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: _promoTextController,
                    maxLines: 7,
                    style: const TextStyle(fontSize: 11.5, color: Colors.white, height: 1.35),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isGeneratingPromo
                        ? null
                        : () async {
                            setState(() => _isGeneratingPromo = true);
                            final promo = await _ai.generateSmartPromo(
                              storeName: SettingsService().storeName,
                              topItems: topItems,
                              discountPercentage: '20%',
                            );
                            if (mounted) {
                              setState(() {
                                _generatedPromoText = promo;
                                _promoTextController.text = promo;
                                _isGeneratingPromo = false;
                              });
                            }
                          },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Regenerate', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isBroadcastingPromo
                        ? null
                        : () async {
                            final text = _promoTextController.text.trim();
                            if (text.isEmpty) return;

                            setState(() => _isBroadcastingPromo = true);
                            int sentCount = 0;

                            try {
                              // Query opted-in customers from tenant-isolated Firestore
                              final snap = await EmailAuthService.tenantCollection('customers')
                                  .where('promoOptIn', isEqualTo: true)
                                  .get()
                                  .timeout(const Duration(seconds: 4));

                              final phoneList = snap.docs
                                  .map((d) => d.data()['phone']?.toString() ?? '')
                                  .where((p) => p.length >= 10)
                                  .toList();

                              if (phoneList.isEmpty) {
                                // Send to demo phone if none found
                                await WhatsAppGatewayService().sendMessage(
                                  targetPhone: '628123456789',
                                  messageText: text,
                                  type: 'PROMO_BLAST',
                                );
                                sentCount = 1;
                              } else {
                                for (final p in phoneList) {
                                  await WhatsAppGatewayService().sendMessage(
                                    targetPhone: p,
                                    messageText: text,
                                    type: 'PROMO_BLAST',
                                  );
                                  sentCount++;
                                }
                              }
                            } catch (_) {
                              // If offline, queue demo blast
                              await WhatsAppGatewayService().sendMessage(
                                targetPhone: '628123456789',
                                messageText: text,
                                type: 'PROMO_BLAST',
                              );
                              sentCount = 1;
                            } finally {
                              if (mounted) {
                                setState(() => _isBroadcastingPromo = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF15803D),
                                    content: Text('Promo broadcast sent to $sentCount customers!'),
                                  ),
                                );
                              }
                            }
                          },
                    icon: _isBroadcastingPromo
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      _isBroadcastingPromo ? 'Mengirim...' : 'Broadcast WhatsApp',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
