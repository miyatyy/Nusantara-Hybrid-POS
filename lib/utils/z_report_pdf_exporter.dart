import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/cashier_shift.dart';
import '../models/receipt_calculation.dart';

class ZReportPdfExporter {
  static const MethodChannel _channel =
      MethodChannel('com.miya.nusantara_hybrid_pos/thermal_printer');

  /// Builds a valid PDF 1.4 formatted byte array for any ZReportData using pure Dart
  static Future<Uint8List> generatePdfBytes({
    required ZReportData report,
    String storeTagline = 'POS & Kitchen Cloud System',
  }) async {
    final pdf = pw.Document();

    final primaryBlue = PdfColor.fromHex('#1E3A8A');
    final accentGold = PdfColor.fromHex('#F59E0B');
    final darkNavy = PdfColor.fromHex('#0F172A');
    final slateMuted = PdfColor.fromHex('#64748B');
    final bgTint = PdfColor.fromHex('#F8FAFC');
    final borderGray = PdfColor.fromHex('#E2E8F0');
    final emeraldGreen = PdfColor.fromHex('#10B981');
    final coralRed = PdfColor.fromHex('#EF4444');

    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Header Banner
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: primaryBlue,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          report.storeName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          storeTagline,
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: accentGold,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Z - REPORT',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: darkNavy,
                            ),
                          ),
                          pw.Text(
                            report.reportId,
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: darkNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // 2. Meta Information Grid
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: bgTint,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: borderGray),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildMetaRow('Outgoing Cashier', report.cashierName, darkNavy, slateMuted),
                          _buildMetaRow('Jabatan', report.role, darkNavy, slateMuted),
                          _buildMetaRow('Shift', '${report.shiftLabel} (${report.shiftHours})', darkNavy, slateMuted),
                        ],
                      ),
                    ),
                    pw.Container(width: 1, height: 50, color: borderGray),
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 12),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildMetaRow('Mulai Shift', dateFormat.format(report.startTime), darkNavy, slateMuted),
                            _buildMetaRow('Shift Closed', dateFormat.format(report.endTime), darkNavy, slateMuted),
                            _buildMetaRow(
                              'Orders Count',
                              '${report.totalOrders} (${report.onlineOrderCount} Cloud / ${report.offlineOrderCount} Offline)',
                              darkNavy,
                              slateMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // 3. Financial Summary Table
              pw.Text(
                'RINGKASAN PENJUALAN',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: borderGray),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: primaryBlue),
                    children: [
                      _buildTableHeader('Indikator Keuangan'),
                      _buildTableHeader('Method / Category'),
                      _buildTableHeader('Nominal (Rupiah)', alignRight: true),
                    ],
                  ),
                  _buildFinancialRow('Total Gross Sales', 'All Shift Transactions', ReceiptCalculation.formatRupiah(report.grossSales), isBold: true),
                  _buildFinancialRow('Tax & Service Charge', 'Regional Tax & Service', ReceiptCalculation.formatRupiah(report.taxAndServiceTotal)),
                  _buildFinancialRow('Cash Sales', 'Cash Drawer Inflow', ReceiptCalculation.formatRupiah(report.cashSales)),
                  _buildFinancialRow('Non-Cash Sales', 'Midtrans QRIS & Card', ReceiptCalculation.formatRupiah(report.nonCashSales)),
                ],
              ),

              pw.SizedBox(height: 16),

              // 4. Cash Drawer Reconciliation Table
              pw.Text(
                'REKONSILIASI KAS LACI (CASH DRAWER)',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: borderGray),
                children: [
                  _buildReconciliationRow('Opening Drawer Cash', ReceiptCalculation.formatRupiah(report.openingCash)),
                  _buildReconciliationRow('+ Shift Cash Sales', ReceiptCalculation.formatRupiah(report.cashSales)),
                  _buildReconciliationRow('Expected Drawer Cash', ReceiptCalculation.formatRupiah(report.expectedCash), isBold: true, highlight: primaryBlue),
                  _buildReconciliationRow('Actual Cash Counted', ReceiptCalculation.formatRupiah(report.actualCash), isBold: true),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: report.isBalanced
                          ? PdfColor.fromHex('#DCFCE7')
                          : (report.isSurplus ? PdfColor.fromHex('#FEF3C7') : PdfColor.fromHex('#FEE2E2')),
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'SELISIH KAS (${report.varianceStatus})',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: report.isBalanced
                                ? emeraldGreen
                                : (report.isSurplus ? PdfColor.fromHex('#B45309') : coralRed),
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          ReceiptCalculation.formatRupiah(report.variance),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: report.isBalanced
                                ? emeraldGreen
                                : (report.isSurplus ? PdfColor.fromHex('#B45309') : coralRed),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // 5. AI Shift Handover Summary Box
              if (report.aiSummary.isNotEmpty) ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: bgTint,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: borderGray),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'AI Summary & Handover Notes:',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        report.aiSummary,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 18),
              ],

              // 6. Signatures Section
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(
                        'Handed Over By (Outgoing Cashier):',
                        style: pw.TextStyle(fontSize: 9, color: slateMuted),
                      ),
                      pw.SizedBox(height: 38),
                      pw.Container(width: 130, height: 1, color: darkNavy),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        report.cashierName,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: darkNavy,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Received By (Incoming Cashier):',
                        style: pw.TextStyle(fontSize: 9, color: slateMuted),
                      ),
                      pw.SizedBox(height: 38),
                      pw.Container(width: 130, height: 1, color: darkNavy),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        report.nextCashierName ?? 'Shift Receiver',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: darkNavy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Nusantara Hybrid POS - #BuildHybridAI - Official Z-Report - Offline/Online Guaranteed',
                  style: pw.TextStyle(fontSize: 8, color: slateMuted),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildMetaRow(String label, String value, PdfColor textColor, PdfColor labelColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8.5, color: labelColor),
            ),
          ),
          pw.Text(': ', style: pw.TextStyle(fontSize: 8.5, color: labelColor)),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableHeader(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.TableRow _buildFinancialRow(String col1, String col2, String col3, {bool isBold = false}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            col1,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(col2, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            col3,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  static pw.TableRow _buildReconciliationRow(String label, String value, {bool isBold = false, PdfColor? highlight}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ?? PdfColors.black,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: highlight ?? PdfColors.black,
            ),
          ),
        ),
      ],
    );
  }

  /// Generates the PDF and saves/shares it natively via Android MediaStore / Downloads
  static Future<String> exportAndShareZReportPdf(
    ZReportData report, {
    String storeTagline = 'POS & Kitchen Cloud System',
  }) async {
    final bytes = await generatePdfBytes(report: report, storeTagline: storeTagline);

    final safeCashier = report.cashierName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timeStr = DateFormat('yyyyMMdd_HHmm').format(report.endTime);
    final fileName = 'Z-Report_${safeCashier}_$timeStr.pdf';

    try {
      final String? savedPath = await _channel.invokeMethod<String>('saveAndSharePdf', {
        'fileName': fileName,
        'bytes': bytes,
      });
      return savedPath ?? fileName;
    } on PlatformException catch (e) {
      throw Exception('Failed to save or share PDF: ${e.message}');
    }
  }
}
