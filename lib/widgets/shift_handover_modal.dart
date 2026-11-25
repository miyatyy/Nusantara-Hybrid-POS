import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/cashier_shift.dart';
import '../models/transaction_model.dart';
import '../models/receipt_calculation.dart';
import '../services/shift_service.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';
import '../services/ai_service.dart';
import '../sdk/nusantara_printer_sdk.dart';
import '../theme/app_theme.dart';
import '../utils/z_report_pdf_exporter.dart';

class ShiftHandoverModal extends StatefulWidget {
  final List<PosTransaction> transactions;
  final VoidCallback? onShiftChanged;

  const ShiftHandoverModal({
    super.key,
    required this.transactions,
    this.onShiftChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<PosTransaction> transactions,
    VoidCallback? onShiftChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShiftHandoverModal(
        transactions: transactions,
        onShiftChanged: onShiftChanged,
      ),
    );
  }

  @override
  State<ShiftHandoverModal> createState() => _ShiftHandoverModalState();
}

class _ShiftHandoverModalState extends State<ShiftHandoverModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShiftService _shiftService = ShiftService();
  final SettingsService _settings = SettingsService();
  final NusantaraPrinterSDK _printerSdk = NusantaraPrinterSDK();
  final AiService _aiService = AiService();

  final TextEditingController _actualCashController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Next shift fields
  CashierEmployee? _selectedIncomingEmployee;
  final TextEditingController _nextOpeningCashController =
      TextEditingController(text: '200000');
  late String _nextShiftLabel;
  late String _nextShiftHours;

  bool _isGeneratingAiNote = false;
  bool _isPrinting = false;
  bool _isExportingPdf = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final roster = _shiftService.roster;
    final currentCashierId = _shiftService.currentSession.cashierId;

    // Pick candidate for next cashier
    final candidate = roster.firstWhere(
      (e) => e.id != currentCashierId,
      orElse: () => roster.first,
    );
    _selectedIncomingEmployee = candidate;
    _nextShiftLabel = candidate.defaultShiftLabel;
    _nextShiftHours = '${candidate.startTime} - ${candidate.endTime}';

    // Prefill actual cash with expected cash by default
    final currentMetrics =
        _shiftService.calculateSessionMetrics(widget.transactions);
    _actualCashController.text = currentMetrics.expectedCash.toString();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _actualCashController.dispose();
    _notesController.dispose();
    _nextOpeningCashController.dispose();
    super.dispose();
  }

  int get _parsedActualCash {
    return ReceiptCalculation.parseCashInput(_actualCashController.text);
  }

  Future<void> _handleGenerateAiNote(ZReportData report) async {
    setState(() => _isGeneratingAiNote = true);
    HapticFeedback.lightImpact();

    try {
      final summaryPrompt =
          'Shift: ${report.shiftLabel} (${report.shiftHours})\n'
          'Cashier: ${report.cashierName} (${report.role})\n'
          'Total Orders: ${report.totalOrders} orders (${report.onlineOrderCount} Cloud / ${report.offlineOrderCount} Offline)\n'
          'Gross Sales: Rp ${report.grossSales}\n'
          'Cash Sales: Rp ${report.cashSales}\n'
          'Non-Cash / QRIS: Rp ${report.nonCashSales}\n'
          'Opening Cash: Rp ${report.openingCash}\n'
          'Expected Drawer Cash: Rp ${report.expectedCash}\n'
          'Actual Counted Cash: Rp ${report.actualCash}\n'
          'Cash Variance: Rp ${report.variance}';

      final aiNote = await _aiService.generateShiftHandoverSummary(
        summaryPrompt: summaryPrompt,
        cashierName: report.cashierName,
      );

      if (mounted) {
        setState(() {
          _notesController.text = aiNote;
        });
      }
    } catch (e) {
      if (mounted) {
        final variance = report.variance;
        final varianceText = variance == 0
            ? 'Cash balanced perfectly (Rp 0)'
            : (variance > 0
                ? 'Cash surplus Rp $variance'
                : 'Cash deficit Rp ${variance.abs()}');
        _notesController.text =
            'Shift ${report.shiftLabel} completed with ${report.totalOrders} orders '
            '(${report.onlineOrderCount} Online / ${report.offlineOrderCount} Offline, '
            'Revenue Rp ${ReceiptCalculation.formatRupiah(report.grossSales)}). '
            '$varianceText. Operations smooth and inventory safely handed over.';
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingAiNote = false);
      }
    }
  }

  Future<void> _handlePrintZReport(ZReportData report) async {
    setState(() => _isPrinting = true);
    HapticFeedback.lightImpact();

    try {
      if (!_printerSdk.hasPrinterSelected) {
        throw Exception(
          'No Bluetooth printer selected. Please choose a thermal printer in Settings.',
        );
      }

      final success = await _printerSdk.printZReport(
        report,
        storeTagline: _settings.storeTagline,
      );

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            content: Text(tr('z_report_printed_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Printer: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _handleExportPdf(ZReportData report) async {
    setState(() => _isExportingPdf = true);
    HapticFeedback.lightImpact();

    try {
      final savedPath = await ZReportPdfExporter.exportAndShareZReportPdf(
        report,
        storeTagline: _settings.storeTagline,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.royalBlue,
            content: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.brightYellow),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr('pdf_saved_success')} ($savedPath)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('PDF Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _handleCloseCurrentShift(ZReportData report) async {
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final notes = _notesController.text.trim();
      final nextCashier = _selectedIncomingEmployee?.name;

      await _shiftService.saveZReportAndCloseShift(
        report: report,
        transactions: widget.transactions,
        notes: notes,
        nextCashierName: nextCashier,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            content: Text(tr('shift_closed_success')),
            behavior: SnackBarBehavior.floating,
          ),
        );

        _tabController.animateTo(1);
        widget.onShiftChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Error closing shift: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleStartNextShift() async {
    if (_selectedIncomingEmployee == null) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final emp = _selectedIncomingEmployee!;
      final openingCash =
          ReceiptCalculation.parseCashInput(_nextOpeningCashController.text);

      await _shiftService.startShift(
        employee: emp,
        shiftLabel: _nextShiftLabel,
        shiftHours: _nextShiftHours,
        openingCash: openingCash > 0 ? openingCash : 200000,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onShiftChanged?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF15803D),
            content: Text(
              '${tr('shift_started_for')} ${emp.name} ($_nextShiftLabel)!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.roseRed,
            content: Text('Error starting shift: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentReport = _shiftService.calculateZReportData(
      transactions: widget.transactions,
      actualCash: _parsedActualCash,
      storeName: _settings.storeName,
      aiSummary: _notesController.text.trim(),
      nextCashierName: _selectedIncomingEmployee?.name,
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppTheme.iceBlueScaffold,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlueTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: AppTheme.royalBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('shift_title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                      Text(
                        tr('shift_subtitle'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppTheme.slateMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 3-Segment Tab Bar (Close Shift & Z-Report | Start Next Shift | Z-Report History)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.royalBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: AppTheme.brightYellow,
              unselectedLabelColor: AppTheme.slateMuted,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
              tabs: [
                Tab(
                  icon: const Icon(Icons.assessment_rounded, size: 16),
                  text: tr('tab_close_shift'),
                ),
                Tab(
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  text: tr('tab_start_shift'),
                ),
                Tab(
                  icon: const Icon(Icons.history_rounded, size: 16),
                  text: tr('tab_z_history'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: Close Shift & Z-Report
                _buildCloseShiftTab(currentReport),

                // TAB 2: Start Next Shift
                _buildStartNextShiftTab(),

                // TAB 3: Z-Report History (Offline + Online)
                _buildZReportHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1 WIDGET: Close Shift & Z-Report
  Widget _buildCloseShiftTab(ZReportData report) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final durationHours = DateTime.now().difference(report.startTime).inHours;
    final durationMins =
        DateTime.now().difference(report.startTime).inMinutes % 60;

    final variance = report.variance;
    final isBalanced = variance == 0;
    final isSurplus = variance > 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        // 1. Active Cashier Hero Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.royalBlue, AppTheme.cobaltBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.royalBlue.withAlpha(50),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withAlpha(40),
                child: Text(
                  report.cashierName.isNotEmpty
                      ? report.cashierName[0].toUpperCase()
                      : 'K',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brightYellow,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            report.cashierName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.brightYellow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.role} • ${report.shiftLabel} (${report.shiftHours})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tr('active_duration')}: ${durationHours}h ${durationMins}m',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.brightYellow,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 4-Card Sales Grid (with Online & Offline JSON breakdown)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.receipt_long_rounded,
                iconColor: AppTheme.royalBlue,
                bg: AppTheme.lightBlueTint,
                label: tr('total_orders'),
                value: '${report.totalOrders} Order',
                subValue: '${report.onlineOrderCount} Cloud • ${report.offlineOrderCount} Offline',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.payments_rounded,
                iconColor: AppTheme.warmGoldDark,
                bg: AppTheme.yellowSubtle,
                label: tr('gross_sales'),
                value: currency.format(report.grossSales),
                subValue: 'Pajak: ${currency.format(report.taxAndServiceTotal)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.attach_money_rounded,
                iconColor: AppTheme.emeraldGreen,
                bg: const Color(0xFFDCFCE7),
                label: tr('cash_sales'),
                value: currency.format(report.cashSales),
                subValue: 'Inflow Kas Fisik',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.qr_code_scanner_rounded,
                iconColor: AppTheme.cobaltBlue,
                bg: AppTheme.lightBlueTint,
                label: tr('non_cash_sales'),
                value: currency.format(report.nonCashSales),
                subValue: 'Midtrans QRIS / Kartu',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 3. Cash Drawer Reconciliation Container
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.point_of_sale_rounded,
                      color: AppTheme.royalBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr('cash_reconciliation_title'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSummaryRow(
                  tr('opening_cash'), currency.format(report.openingCash)),
              _buildSummaryRow(
                  '+ ${tr('cash_sales')}', currency.format(report.cashSales)),
              const Divider(color: AppTheme.cardBorder),
              _buildSummaryRow(
                tr('expected_cash'),
                currency.format(report.expectedCash),
                isBold: true,
                valueColor: AppTheme.royalBlue,
              ),
              const SizedBox(height: 12),

              // Actual Cash Input Field
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('actual_cash_counted'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded,
                        size: 14, color: AppTheme.royalBlue),
                    label: Text(
                      tr('match_target'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.royalBlue),
                    ),
                    onPressed: () {
                      setState(() {
                        _actualCashController.text =
                            report.expectedCash.toString();
                      });
                    },
                  ),
                ],
              ),
              TextField(
                controller: _actualCashController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkNavy,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  prefixStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateMuted,
                  ),
                  filled: true,
                  fillColor: AppTheme.iceBlueScaffold,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),

              // Live Variance Status Chip
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isBalanced
                      ? const Color(0xFFDCFCE7)
                      : (isSurplus
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isBalanced
                        ? const Color(0xFF86EFAC)
                        : (isSurplus
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFFCA5A5)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBalanced
                          ? Icons.check_circle_rounded
                          : (isSurplus
                              ? Icons.arrow_upward_rounded
                              : Icons.warning_rounded),
                      size: 16,
                      color: isBalanced
                          ? const Color(0xFF15803D)
                          : (isSurplus
                              ? const Color(0xFFB45309)
                              : AppTheme.roseRed),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${tr('cash_variance')}: ${currency.format(variance)} '
                        '(${isBalanced ? tr('variance_balanced') : (isSurplus ? tr('variance_surplus') : tr('variance_shortage'))})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isBalanced
                              ? const Color(0xFF15803D)
                              : (isSurplus
                                  ? const Color(0xFFB45309)
                                  : AppTheme.roseRed),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. AI Shift Handover Note Generator
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppTheme.warmGoldDark, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        tr('ai_handover_notes'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      side: const BorderSide(color: AppTheme.goldenAmber),
                      backgroundColor: AppTheme.yellowSubtle,
                    ),
                    icon: _isGeneratingAiNote
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.smart_toy_outlined,
                            size: 14, color: AppTheme.warmGoldDark),
                    label: Text(
                      _isGeneratingAiNote ? 'Generating...' : tr('generate_ai_notes'),
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warmGoldDark),
                    ),
                    onPressed: _isGeneratingAiNote
                        ? null
                        : () => _handleGenerateAiNote(report),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.darkNavy),
                decoration: InputDecoration(
                  hintText: tr('handover_notes_hint'),
                  hintStyle: const TextStyle(
                      fontSize: 11, color: AppTheme.slateMuted),
                  filled: true,
                  fillColor: AppTheme.iceBlueScaffold,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. The 3 Core Action Buttons:
        // Button 1: "Print Bluetooth Z-Report" (Royal Blue)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          icon: _isPrinting
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_rounded, size: 17, color: AppTheme.brightYellow),
          label: Text(
            tr('btn_print_bluetooth_z_report'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          onPressed: _isPrinting ? null : () => _handlePrintZReport(report),
        ),
        const SizedBox(height: 8),

        // Button 2: "Save / Export PDF" (Golden Yellow)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.goldenAmber,
            foregroundColor: AppTheme.darkNavy,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          icon: _isExportingPdf
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.darkNavy,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 17, color: AppTheme.darkNavy),
          label: Text(
            tr('btn_save_export_pdf'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.darkNavy,
            ),
          ),
          onPressed: _isExportingPdf ? null : () => _handleExportPdf(report),
        ),
        const SizedBox(height: 8),

        // Button 3: "Confirm & Close Shift (Sync Firebase / Offline JSON)"
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF15803D), // Emerald Green confirmation
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_done_rounded, size: 17, color: Colors.white),
          label: Text(
            tr('btn_confirm_close_shift'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          onPressed: _isSubmitting ? null : () => _handleCloseCurrentShift(report),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // TAB 2 WIDGET: Start Next Shift
  Widget _buildStartNextShiftTab() {
    final roster = _shiftService.roster;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Incoming Staff Selector
        Text(
          tr('select_cashier'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppTheme.darkNavy,
          ),
        ),
        const SizedBox(height: 8),

        ...roster.map((emp) {
          final isSelected = _selectedIncomingEmployee?.id == emp.id;
          return InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedIncomingEmployee = emp;
                _nextShiftLabel = emp.defaultShiftLabel;
                _nextShiftHours = '${emp.startTime} - ${emp.endTime}';
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppTheme.royalBlue : AppTheme.cardBorder,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.royalBlue.withAlpha(20),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isSelected
                        ? AppTheme.royalBlue
                        : AppTheme.lightBlueTint,
                    child: Text(
                      emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'K',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color:
                            isSelected ? AppTheme.brightYellow : AppTheme.royalBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emp.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                        Text(
                          '${emp.role} • ${emp.defaultShiftLabel} (${emp.startTime} - ${emp.endTime})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.royalBlue, size: 20),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Opening Cash Input
        Text(
          tr('opening_cash_label'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppTheme.darkNavy,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nextOpeningCashController,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppTheme.darkNavy,
          ),
          decoration: InputDecoration(
            prefixText: 'Rp ',
            prefixStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.slateMuted,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.cardBorder),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),

        // Quick Cash Chips
        Wrap(
          spacing: 8,
          children: [100000, 200000, 300000, 500000].map((val) {
            return ActionChip(
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppTheme.cardBorder),
              label: Text(
                ReceiptCalculation.formatRupiah(val),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.royalBlue,
                ),
              ),
              onPressed: () {
                setState(() {
                  _nextOpeningCashController.text = val.toString();
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Big Start Shift Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.goldenAmber,
            foregroundColor: AppTheme.darkNavy,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 22),
          label: Text(
            tr('start_shift_btn'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          onPressed: _isSubmitting ? null : _handleStartNextShift,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // TAB 3 WIDGET: Z-Report History (Offline + Online)
  Widget _buildZReportHistoryTab() {
    return AnimatedBuilder(
      animation: _shiftService,
      builder: (context, _) {
        final historyReports = _shiftService.zReports;
        if (historyReports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                const Text(
                  'Belum ada arsip Z-Report',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Laporan Z-Report yang ditutup akan otomatis tersimpan di sini',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
        final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: historyReports.length,
          itemBuilder: (context, index) {
            final report = historyReports[index];
            final variance = report.variance;
            final isBalanced = variance == 0;
            final isSurplus = variance > 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.royalBlue.withAlpha(10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.lightBlueTint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.blueSubtle),
                            ),
                            child: Text(
                              report.reportId,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.royalBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: report.syncedToFirestore
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              report.syncedToFirestore ? 'CLOUD SYNC' : 'OFFLINE JSON',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: report.syncedToFirestore
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        dateFormat.format(report.endTime),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${report.cashierName} • ${report.shiftLabel} (${report.shiftHours})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.totalOrders} Orders (${report.onlineOrderCount} Cloud / ${report.offlineOrderCount} Offline) • Omzet: ${currency.format(report.grossSales)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.royalBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isBalanced
                          ? const Color(0xFFDCFCE7)
                          : (isSurplus
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFFEE2E2)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Selisih Kas: ${currency.format(variance)} (${report.varianceStatus}) • Modal Awal: ${currency.format(report.openingCash)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isBalanced
                            ? const Color(0xFF15803D)
                            : (isSurplus
                                ? const Color(0xFFB45309)
                                : AppTheme.roseRed),
                      ),
                    ),
                  ),
                  if (report.aiSummary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Catatan: ${report.aiSummary}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.slateMuted,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.royalBlue),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.print_rounded,
                              size: 14, color: AppTheme.royalBlue),
                          label: const Text(
                            'Print (BT)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.royalBlue,
                            ),
                          ),
                          onPressed: () => _handlePrintZReport(report),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.goldenAmber,
                            foregroundColor: AppTheme.darkNavy,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.picture_as_pdf_rounded,
                              size: 14, color: AppTheme.darkNavy),
                          label: const Text(
                            'Export PDF',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: () => _handleExportPdf(report),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required String label,
    required String value,
    String? subValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.slateMuted,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppTheme.darkNavy,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue,
              style: const TextStyle(
                fontSize: 9,
                color: AppTheme.slateMuted,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String left,
    String right, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            left,
            style: TextStyle(
              fontSize: 11.5,
              color: isBold ? AppTheme.darkNavy : AppTheme.slateMuted,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
          Text(
            right,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? AppTheme.darkNavy,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
