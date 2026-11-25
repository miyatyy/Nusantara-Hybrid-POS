import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/menu_item.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'menu_image_banner.dart';

/// 1. Category Sales Share (Circular Donut Percentage Chart)
class CategoryDonutChart extends StatelessWidget {
  final Map<String, double> categoryRevenue;
  final double totalRevenue;
  final NumberFormat currencyFormatter;

  const CategoryDonutChart({
    super.key,
    required this.categoryRevenue,
    required this.totalRevenue,
    required this.currencyFormatter,
  });

  static const Map<String, Color> categoryColors = {
    'Minuman': AppTheme.royalBlue,
    'Makanan': AppTheme.goldenAmber,
    'Cemilan': Color(0xFF38BDF8), // Crisp Sky Blue
    'Paket': Color(0xFFF97316),   // Warm Sunset Orange
    'Other': Color(0xFF64748B),   // Slate Grey
  };

  /// Normalizes category keys case-insensitively across Indonesian and English terms
  static String normalizeCategory(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) return 'Other';
    if (lower.contains('minum') || lower.contains('beverag') || lower.contains('drink') || lower.contains('kopi') || lower.contains('tea') || lower.contains('jus') || lower.contains('boba')) {
      return 'Minuman';
    }
    if (lower.contains('makan') || lower.contains('food') || lower.contains('dish') || lower.contains('meal') || lower.contains('rice') || lower.contains('nasi') || lower.contains('mie') || lower.contains('ayam')) {
      return 'Makanan';
    }
    if (lower.contains('cemil') || lower.contains('snack') || lower.contains('pastry') || lower.contains('roti') || lower.contains('kue') || lower.contains('dessert') || lower.contains('gorengan')) {
      return 'Cemilan';
    }
    if (lower.contains('paket') || lower.contains('bundle') || lower.contains('combo') || lower.contains('set')) {
      return 'Paket';
    }
    return 'Other';
  }

  @override
  Widget build(BuildContext context) {
    // 1. Normalize and aggregate revenues into canonical categories
    final Map<String, double> normalizedRevenue = {
      'Minuman': 0.0,
      'Makanan': 0.0,
      'Cemilan': 0.0,
      'Paket': 0.0,
    };

    categoryRevenue.forEach((key, val) {
      final normKey = normalizeCategory(key);
      normalizedRevenue[normKey] = (normalizedRevenue[normKey] ?? 0.0) + val;
    });

    final effectiveTotal = totalRevenue > 0 ? totalRevenue : 0.0;
    final Map<String, double> percentages = {};
    normalizedRevenue.forEach((cat, rev) {
      percentages[cat] = effectiveTotal > 0 ? (rev / effectiveTotal) * 100 : 0.0;
    });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(10),
            blurRadius: 10,
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlueTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.pie_chart_rounded, size: 18, color: AppTheme.cobaltBlue),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tr('chart_category_share'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Live Firestore Stream',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Donut + Legend Layout
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 520;
              final donutWidget = SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(150, 150),
                      painter: _DonutChartPainter(
                        categoryRevenue: normalizedRevenue,
                        totalRevenue: totalRevenue,
                        categoryColors: categoryColors,
                      ),
                    ),
                    // Center Label: Guard against totalSales <= 0
                    if (totalRevenue <= 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          LocalizationService().isIndonesian ? 'Belum ada\ndata penjualan' : 'No sales\ndata yet',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slateMuted,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slateMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            currencyFormatter.format(totalRevenue),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.royalBlue,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                  ],
                ),
              );

              final legendWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: normalizedRevenue.entries.map((entry) {
                  final cat = entry.key;
                  final rev = entry.value;
                  final pct = percentages[cat] ?? 0.0;
                  final color = categoryColors[cat] ?? AppTheme.royalBlue;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: color.withAlpha(10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withAlpha(35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cat,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkNavy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currencyFormatter.format(rev),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );

              if (isWide) {
                return Row(
                  children: [
                    donutWidget,
                    const SizedBox(width: 20),
                    Expanded(child: legendWidget),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Center(child: donutWidget),
                    const SizedBox(height: 16),
                    legendWidget,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final Map<String, double> categoryRevenue;
  final double totalRevenue;
  final Map<String, Color> categoryColors;

  _DonutChartPainter({
    required this.categoryRevenue,
    required this.totalRevenue,
    required this.categoryColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 22.0;

    final paintBg = Paint()
      ..color = AppTheme.iceBlueScaffold
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius - strokeWidth / 2, paintBg);

    if (totalRevenue <= 0) {
      // Paint clean neutral ring if no revenue yet
      final paintEmpty = Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius - strokeWidth / 2, paintEmpty);
      return;
    }

    double currentAngle = -math.pi / 2;
    categoryRevenue.forEach((category, revenue) {
      if (revenue <= 0) return;
      final sweepAngle = (revenue / totalRevenue) * (2 * math.pi);
      final color = categoryColors[category] ?? AppTheme.royalBlue;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        currentAngle,
        sweepAngle - 0.04, // slight segment gap
        false,
        paint,
      );

      currentAngle += sweepAngle;
    });
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.totalRevenue != totalRevenue ||
        oldDelegate.categoryRevenue != categoryRevenue;
  }
}

/// 2. Top Best-Sellers Bar Diagram
class TopBestSellersBarChart extends StatelessWidget {
  final List<MenuItem> menuItems;
  final Map<String, int> itemFrequency;
  final Map<String, double> itemRevenue;
  final NumberFormat currencyFormatter;

  const TopBestSellersBarChart({
    super.key,
    required this.menuItems,
    required this.itemFrequency,
    required this.itemRevenue,
    required this.currencyFormatter,
  });

  @override
  Widget build(BuildContext context) {
    // Sort items by units sold
    final sorted = List<MenuItem>.from(menuItems);
    sorted.sort((a, b) {
      final soldA = itemFrequency[a.id] ?? (a.popularityScore ~/ 10);
      final soldB = itemFrequency[b.id] ?? (b.popularityScore ~/ 10);
      return soldB.compareTo(soldA);
    });

    final top5 = sorted.take(5).toList();
    final maxUnits = top5.isEmpty
        ? 1
        : (itemFrequency[top5.first.id] ?? (top5.first.popularityScore ~/ 10)).clamp(1, 9999);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(10),
            blurRadius: 10,
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.yellowSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.warmGoldDark),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tr('chart_top_sellers_bar'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.leaderboard_rounded, size: 18, color: AppTheme.goldenAmber),
            ],
          ),
          const SizedBox(height: 16),

          ...top5.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final unitsSold = itemFrequency[item.id] ?? (item.popularityScore ~/ 10);
            final revenue = itemRevenue[item.id] ?? (unitsSold * item.price);
            final ratio = (unitsSold / maxUnits).clamp(0.08, 1.0);
            final isTop1 = index == 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: MenuImageBanner(
                            imageUrl: item.imageUrl,
                            category: item.category,
                            iconEmoji: item.iconEmoji,
                            height: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Rank Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isTop1 ? AppTheme.goldenAmber : AppTheme.lightBlueTint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: isTop1 ? AppTheme.darkNavy : AppTheme.royalBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.darkNavy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        currencyFormatter.format(revenue),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Horizontal Bar Diagram
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Track
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.iceBlueScaffold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      // Progress Bar
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isTop1
                                  ? [AppTheme.brightYellow, AppTheme.goldenAmber]
                                  : [const Color(0xFF60A5FA), AppTheme.royalBlue],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: (isTop1 ? AppTheme.goldenAmber : AppTheme.royalBlue).withAlpha(40),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            '$unitsSold',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: isTop1 ? AppTheme.darkNavy : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Financial data bucket for Daily, Weekly, or Monthly aggregation
class FinancialBucket {
  final String label;
  final DateTime date;
  final double sales;
  final double expenses;

  double get netProfit => sales - expenses;
  double get marginPercent => sales > 0 ? (netProfit / sales) * 100 : 0.0;

  const FinancialBucket({
    required this.label,
    required this.date,
    required this.sales,
    required this.expenses,
  });
}

/// 3. Interactive Multi-Series Financial Chart (Sales, Expenses & Net Profit)
class FinancialOverviewChart extends StatefulWidget {
  final List<FinancialBucket> buckets;
  final String selectedTimeframe; // 'daily', 'weekly', 'monthly'
  final ValueChanged<String> onTimeframeChanged;
  final VoidCallback onLogExpense;
  final NumberFormat currencyFormatter;

  const FinancialOverviewChart({
    super.key,
    required this.buckets,
    required this.selectedTimeframe,
    required this.onTimeframeChanged,
    required this.onLogExpense,
    required this.currencyFormatter,
  });

  @override
  State<FinancialOverviewChart> createState() => _FinancialOverviewChartState();
}

class _FinancialOverviewChartState extends State<FinancialOverviewChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    double totalSales = 0;
    double totalExpenses = 0;
    for (final b in widget.buckets) {
      totalSales += b.sales;
      totalExpenses += b.expenses;
    }
    final netProfit = totalSales - totalExpenses;
    final marginPercent = totalSales > 0 ? (netProfit / totalSales) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chart Header: Title, Log Expense Action & Timeframe Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlueTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.ssid_chart_rounded,
                        size: 18,
                        color: AppTheme.cobaltBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('financial_chart_title'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                          Text(
                            'Sales vs Expenses (Margin: ${marginPercent.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: widget.onLogExpense,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.goldenAmber,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.goldenAmber.withAlpha(50),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_circle_outline, size: 13, color: AppTheme.darkNavy),
                      const SizedBox(width: 4),
                      Text(
                        tr('log_expense_btn'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Timeframe Segmented Toggle Bar (Daily, Weekly, Monthly)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.iceBlueScaffold,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.blueSubtle),
            ),
            child: Row(
              children: [
                _buildTimeframeTab('daily', tr('timeframe_daily')),
                _buildTimeframeTab('weekly', tr('timeframe_weekly')),
                _buildTimeframeTab('monthly', tr('timeframe_monthly')),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Legend Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(AppTheme.royalBlue, tr('financial_kpi_sales')),
              const SizedBox(width: 14),
              _buildLegendItem(const Color(0xFFEF4444), tr('financial_kpi_expenses')),
              const SizedBox(width: 14),
              _buildLegendItem(
                const Color(0xFF10B981),
                tr('financial_kpi_profit'),
                isLine: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Selected Tooltip Display
          if (_selectedIndex != null && _selectedIndex! < widget.buckets.length) ...[
            Builder(builder: (context) {
              final b = widget.buckets[_selectedIndex!];
              final isProfit = b.netProfit >= 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlueTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.blueSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      b.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppTheme.darkNavy,
                      ),
                    ),
                    Text(
                      'Sales: ${widget.currencyFormatter.format(b.sales)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                    Text(
                      'Exp: ${widget.currencyFormatter.format(b.expenses)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isProfit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${isProfit ? "+" : ""}${widget.currencyFormatter.format(b.netProfit)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                          color: isProfit ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Interactive Pure-Flutter CustomPainter Chart
          SizedBox(
            height: 180,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapUp: (details) {
                    if (widget.buckets.isEmpty) return;
                    final bucketWidth = constraints.maxWidth / widget.buckets.length;
                    final index = (details.localPosition.dx / bucketWidth).floor();
                    if (index >= 0 && index < widget.buckets.length) {
                      setState(() {
                        _selectedIndex = (_selectedIndex == index) ? null : index;
                      });
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 180),
                    painter: _FinancialGroupedBarLinePainter(
                      buckets: widget.buckets,
                      selectedIndex: _selectedIndex,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Tap any column to inspect exact figures',
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeTab(String key, String label) {
    final isSelected = widget.selectedTimeframe == key;
    return Expanded(
      child: InkWell(
        onTap: () => widget.onTimeframeChanged(key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.royalBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.royalBlue.withAlpha(50),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : AppTheme.slateMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text, {bool isLine = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLine)
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _FinancialGroupedBarLinePainter extends CustomPainter {
  final List<FinancialBucket> buckets;
  final int? selectedIndex;

  _FinancialGroupedBarLinePainter({
    required this.buckets,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    const bottomPadding = 24.0;
    const topPadding = 10.0;
    final chartHeight = size.height - bottomPadding - topPadding;
    final chartWidth = size.width;

    // Calculate max value for scaling
    double maxVal = 100000;
    for (final b in buckets) {
      if (b.sales > maxVal) maxVal = b.sales;
      if (b.expenses > maxVal) maxVal = b.expenses;
    }
    // Round maxVal up nicely
    maxVal = maxVal * 1.15;

    // 1. Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);
    }

    final bucketCount = buckets.length;
    final slotWidth = chartWidth / bucketCount;
    final barWidth = math.min(slotWidth * 0.28, 14.0);

    final List<Offset> netProfitPoints = [];

    // 2. Draw Grouped Bars (Sales & Expenses)
    for (int i = 0; i < bucketCount; i++) {
      final b = buckets[i];
      final slotCenterX = i * slotWidth + slotWidth / 2;
      final isSelected = selectedIndex == i;

      // Highlight selected background
      if (isSelected) {
        final highlightRect = Rect.fromLTWH(
          i * slotWidth + 2,
          topPadding,
          slotWidth - 4,
          chartHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(highlightRect, const Radius.circular(8)),
          Paint()..color = AppTheme.lightBlueTint.withAlpha(120),
        );
      }

      // Sales Bar (Royal Blue) - Safely clamp height to prevent negative Rect exceptions
      final salesHeight = math.max(0.0, (b.sales / maxVal) * chartHeight);
      final salesRect = Rect.fromLTWH(
        slotCenterX - barWidth - 1.5,
        topPadding + (chartHeight - salesHeight),
        barWidth,
        salesHeight,
      );
      final salesPaint = Paint()
        ..color = isSelected ? const Color(0xFF1D4ED8) : AppTheme.royalBlue;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          salesRect,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        salesPaint,
      );

      // Expenses Bar (Coral Red) - Safely clamp height
      final expHeight = math.max(0.0, (b.expenses / maxVal) * chartHeight);
      final expRect = Rect.fromLTWH(
        slotCenterX + 1.5,
        topPadding + (chartHeight - expHeight),
        barWidth,
        expHeight,
      );
      final expPaint = Paint()..color = const Color(0xFFEF4444);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          expRect,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        expPaint,
      );

      // Calculate Net Profit Point for line safely (handles negative profit gracefully)
      final profitClamped = b.netProfit.clamp(-maxVal, maxVal);
      final profitRatio = (profitClamped / maxVal); // -1.0 to 1.0
      final profitY = topPadding + (chartHeight * 0.5) - (profitRatio * chartHeight * 0.45);
      netProfitPoints.add(Offset(slotCenterX, profitY.clamp(topPadding + 2, topPadding + chartHeight - 2)));

      // X-Axis Label
      final textSpan = TextSpan(
        text: b.label,
        style: TextStyle(
          color: isSelected ? AppTheme.royalBlue : const Color(0xFF64748B),
          fontSize: 10,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(slotCenterX - tp.width / 2, size.height - bottomPadding + 6),
      );
    }

    // 3. Draw Net Profit Trend Line
    if (netProfitPoints.length > 1) {
      final linePath = Path();
      linePath.moveTo(netProfitPoints.first.dx, netProfitPoints.first.dy);
      for (int i = 1; i < netProfitPoints.length; i++) {
        linePath.lineTo(netProfitPoints[i].dx, netProfitPoints[i].dy);
      }

      final trendLinePaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, trendLinePaint);
    }

    // 4. Draw Net Profit Dots
    for (int i = 0; i < netProfitPoints.length; i++) {
      final p = netProfitPoints[i];
      final isSelected = selectedIndex == i;

      // Outer Green Circle
      canvas.drawCircle(
        p,
        isSelected ? 5.5 : 4.0,
        Paint()..color = const Color(0xFF10B981),
      );
      // Inner White Core
      canvas.drawCircle(
        p,
        isSelected ? 3.0 : 2.0,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FinancialGroupedBarLinePainter oldDelegate) {
    return oldDelegate.buckets != buckets || oldDelegate.selectedIndex != selectedIndex;
  }
}

