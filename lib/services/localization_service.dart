import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  static const String _prefKey = 'app_language_code';

  // Default to English ('en') as required by Rule 6
  final ValueNotifier<String> currentLanguage = ValueNotifier<String>('en');

  bool get isEnglish => currentLanguage.value == 'en';
  bool get isIndonesian => currentLanguage.value == 'id';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && (saved == 'en' || saved == 'id')) {
        currentLanguage.value = saved;
      }
    } catch (_) {}
  }

  Future<void> setLanguage(String code) async {
    if (code != 'en' && code != 'id') return;
    currentLanguage.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }

  void toggleLanguage() {
    setLanguage(isEnglish ? 'id' : 'en');
  }

  String t(String key) {
    final lang = currentLanguage.value;
    final map = _strings[lang] ?? _strings['en']!;
    return map[key] ?? _strings['en']?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      // App & Navigation
      'app_title': 'Nusantara Hybrid POS',
      'nav_cashier': 'POS Cashier',
      'nav_menu': 'Menu & Bundles',
      'nav_inventory': 'Procurement',
      'nav_analytics': 'Analytics & AI',
      'status_online': 'Online',
      'status_offline': 'Offline Mode',
      'engine_nano': 'Local: Gemini Nano',
      'engine_cloud': 'Cloud: Gemini 3.8 Flash',

      // POS Cashier & Order Modes
      'dine_in': 'Dine In',
      'take_away': 'Take Away',
      'order_notes': 'Order Notes',
      'order_notes_hint': 'e.g. Less ice, separate sauce...',
      'ai_order_title': 'Smart AI Natural Order Box',
      'ai_order_hint': 'Type or speak order (e.g. "2 palm sugar latte less ice, 1 butter croissant, cash 100k")',
      'ai_order_btn': 'Process AI Order',
      'voice_listening': 'Listening... Speak your order',
      'voice_start': 'Start Voice Dictation',
      'voice_stop': 'Stop Voice',
      'sample_chips_label': 'Quick Test Prompts:',
      'recommender_title': 'Real-Time AI Upsell & Recommendation',
      'recommender_badge': 'AI Pick #1',
      'add_to_cart': '+ Add to Cart',
      'cart_title': 'Current Order Cart',
      'cart_empty': 'Cart is empty. Select menu or use AI Voice order.',
      'total': 'Total',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'service_charge': 'Service Charge',
      'checkout': 'Checkout',
      'payment_method': 'Payment Method',
      'cash': 'Cash',
      'qris': 'QRIS',
      'card': 'Debit/Credit Card',
      'cash_received': 'Cash Received',
      'change': 'Change',
      'confirm_payment': 'Complete Payment',
      'stock_available': 'available',
      'stock_out': 'Sold Out',
      'portions': 'portions',
      'status_ready': 'READY',
      'status_sold_out': 'SOLD OUT',
      'force_ready': 'Force Ready',
      'force_sold_out': 'Force Sold Out',
      'auto_bom': 'Auto (Recipe BOM)',

      // Menu Categories
      'cat_all': 'All',
      'cat_food': 'Food',
      'cat_drink': 'Beverages',
      'cat_snack': 'Snacks',
      'cat_bundle': 'Bundles',

      // Menu Screen
      'menu_management_title': 'F&B Recipes & Menu Management',
      'add_menu_item': 'Add Menu Item',
      'bom_recipe': 'Recipe / Bill of Materials (BOM)',
      'price': 'Price',
      'cost_of_goods': 'COGS (HPP)',
      'margin': 'Margin',

      // Inventory / Procurement Screen
      'inventory_title': 'Raw Materials & Procurement',
      'restock_btn': 'Log Supplier Stock-In',
      'ai_procurement_btn': 'AI Procurement Advisor (Gemini 3.8)',
      'current_stock': 'Current Stock',
      'unit': 'Unit',
      'safety_stock': 'Safety Stock',
      'status_safe': 'Sufficient',
      'status_low': 'Low Stock Alert',
      'supplier_cost': 'Cost/Unit',

      // Hero & Mascot
      'hero_headline': 'Serve Fast,\nSmart POS!',
      'hero_sub': 'AI-Powered Hybrid Cloud & Offline Engine',

      // Analytics Screen
      'analytics_title': 'Business Performance & AI Insights',
      'best_sellers': 'Best Sellers & Customer Favorites',
      'revenue_breakdown': 'Category Revenue Breakdown',
      'generate_insight_btn': 'Generate AI Business Insight (Gemini 3.8)',
      'publish_bundle_btn': 'Publish Bundle to POS Cashier',
      'bundle_published_toast': 'Combo Bundle published to POS Cashier!',
      'insight_analyzing': 'Analyzing recent transactions & margins with Gemini 3.8 Flash...',
      'timeframe_daily': 'Daily (7 Days)',
      'timeframe_weekly': 'Weekly (4 Weeks)',
      'timeframe_monthly': 'Monthly (6 Months)',
      'financial_kpi_sales': 'Total Sales',
      'financial_kpi_expenses': 'Total Expenses',
      'financial_kpi_profit': 'Net Profit',
      'financial_chart_title': 'Financial Performance',
      'log_expense_btn': '+ Log Expense',
      'log_expense_title': 'Log Business Expense',
      'expense_category': 'Expense Category',
      'expense_amount': 'Amount (Rp)',
      'expense_note': 'Description / Note',
      'expense_saved_toast': 'Expense recorded successfully!',

      // Receipt
      'receipt_title': 'Digital Thermal Receipt',
      'receipt_store_name': 'NUSANTARA HYBRID POS CAFÉ',
      'receipt_store_tag': 'Official Hackathon Demo Store',
      'receipt_order_id': 'Order #',
      'receipt_date': 'Date',
      'receipt_items': 'Items',
      'receipt_copy': 'Copy Receipt Text',
      'receipt_copied': 'Receipt copied to clipboard!',
      'receipt_close': 'Close & New Order',
      'receipt_print': 'Print Receipt (Thermal / PDF)',
      'receipt_printing': 'Sending to Thermal Printer...',
      'receipt_printed': 'Receipt sent to printer successfully!',
      'receipt_print_bt': 'Print Bluetooth Receipt',
      'receipt_preview_escpos': 'Inspect Raw ESC/POS',
      'receipt_bt_success': 'Receipt sent to Bluetooth Thermal Printer!',
      'stat_today_sales': 'Today Sales',
      'stat_orders_today': 'Orders Today',
      'stat_offline_sync': 'Stock Auto-Deduct',
      'best_sellers_title': '🔥 Best Sellers & AI Picks',
      'best_sellers_sub': 'Top customer favorites & smart recommendations',
      'all_menu_catalog': 'All Menu Catalog',

      // Bluetooth Printer SDK & Offline Outbox
      'printer_sdk_title': 'Bluetooth Thermal Printer SDK',
      'printer_select_device': 'Paired Bluetooth Printer',
      'printer_scan_refresh': 'Refresh Paired Devices',
      'printer_no_devices': 'No paired Bluetooth printer found. Pair in Android Settings first.',
      'printer_paper_width': 'Thermal Paper Width',
      'printer_test_page': 'Print Test Page',
      'printer_test_success': 'Test page sent to printer!',
      'printer_status_connected': 'Ready to Print',
      'printer_status_none': 'No Printer Selected',
      'offline_outbox_title': 'Offline JSON Outbox & Cloud Sync',
      'offline_queue_badge': 'Offline JSON Queue',
      'offline_all_synced': 'All Synced',
      'offline_view_log': 'View Local JSON Log',
      'offline_sync_now': 'Sync to Cloud Now',
      'cash_insufficient': 'Insufficient cash! Missing',
      'change_kembalian': 'Change (Kembalian)',
      'cash_received_label': 'Cash Paid (Tunai)',

      // Midtrans Sandbox
      'midtrans_sandbox': 'Midtrans Sandbox (QRIS)',
      'midtrans_title': 'Midtrans Sandbox Payment',
      'midtrans_scan_qris': 'Scan QRIS with GoPay / BCA / ShopeePay Sandbox',
      'midtrans_check_status': 'Check Sandbox Status',
      'midtrans_simulate_settlement': 'Simulate Sandbox Settlement (Pay Now)',
      'midtrans_offline_warning': 'Midtrans Sandbox requires active internet connection. Please use Cash for offline checkout.',
      'qris_tab': 'QRIS Sandbox',
      'card_tab': 'Debit/Credit Card',
      'card_number': 'Card Number',
      'card_expiry': 'Expiry (MM/YY)',
      'card_cvv': 'CVV',
      'use_test_card': 'Fill Sandbox Test Card (4811-...)',
      'pay_with_card': 'Pay with Test Card',
      'expires_in': 'Expires in',

      // Settings
      'settings_title': 'Store & POS Settings',
      'settings_store_profile': 'Store & Receipt Profile',
      'settings_store_name': 'Store Name',
      'settings_store_tagline': 'Tagline',
      'settings_store_address': 'Address',
      'settings_store_phone': 'Phone Number',
      'settings_receipt_footer': 'Receipt Footer Message',
      'settings_tax_rate': 'Tax Rate (PB1 %)',
      'settings_service_charge': 'Service Charge (%)',
      'settings_stock_automation': 'Stock & AI Menu Automation',
      'settings_auto_deduct': 'Realtime Stock Auto-Deduct',
      'settings_auto_deduct_sub': 'Deducts raw materials BOM on each checkout (works offline)',
      'settings_ai_stock_guard': 'AI Stock Guard & Auto-Sold-Out',
      'settings_ai_stock_guard_sub': 'Automatically hides sold-out items when ingredients run out',
      'settings_menu_overrides': 'Quick Menu Availability Overrides',
      'settings_midtrans_config': 'Midtrans Sandbox & Payments',
      'settings_qris_expiry': 'QRIS Expiry Duration',
      'settings_local_key': 'Local Sandbox Server Key (Optional)',
      'settings_local_key_hint': 'SB-Mid-server-xxxx (Overrides build default)',
      'settings_hybrid_ai_demo': 'Hybrid AI & Demo Controls',
      'settings_ai_mode': 'Gemini AI Inference Mode',
      'settings_reset_demo': 'Reset / Re-seed Demo Data',
      'settings_reset_confirm': 'Are you sure you want to reset all data to default demo state?',
      'settings_saved': 'Settings saved successfully!',

      // Charts
      'chart_category_share': 'Category Sales Share (Donut %)',
      'chart_top_sellers_bar': 'Top Best-Sellers Bar Diagram',
      'chart_units_sold': 'units sold',

      // General
      'search_menu': 'Search menu...',
      'error_no_stock': 'Insufficient raw material stock to prepare this item!',
      'success_checkout': 'Order completed successfully! Ingredients auto-deducted.',
      'ai_fallback_notice': 'Offline fallback active. Running local parsing.',

      // Cashier Shift & Handover
      'shift_title': 'Cashier Shift & Handover',
      'shift_subtitle': 'Handover, Z-Report & Cash Drawer',
      'tab_close_shift': 'Close Shift (Z-Report)',
      'tab_start_shift': 'Start Next Shift',
      'active_duration': 'Active Duration',
      'total_orders': 'Total Orders',
      'gross_sales': 'Gross Sales',
      'cash_sales': 'Cash Sales',
      'non_cash_sales': 'Non-Cash / QRIS',
      'cash_reconciliation_title': 'Cash Drawer Reconciliation',
      'opening_cash': 'Opening Cash',
      'expected_cash': 'Expected Drawer Cash',
      'actual_cash_counted': 'Physical Cash Counted',
      'match_target': 'Match Target',
      'cash_variance': 'Cash Variance',
      'variance_balanced': 'Balanced (Rp 0)',
      'variance_surplus': 'Surplus',
      'variance_shortage': 'Shortage',
      'ai_handover_notes': 'AI Shift Handover Note',
      'generate_ai_notes': 'Generate AI Note',
      'handover_notes_hint': 'Optional cashier handover notes or remarks...',
      'print_z_report': 'Print Z-Report (BT)',
      'close_shift_confirm': 'Close Shift',
      'select_cashier': 'Select Incoming Cashier',
      'opening_cash_label': 'Opening Drawer Cash (Modal Awal)',
      'start_shift_btn': 'Start Shift Now',
      'z_report_printed_success': 'Z-Report sent to Bluetooth printer!',
      'shift_closed_success': 'Shift closed & archived successfully!',
      'shift_started_for': 'Shift successfully started for',
      'active_cashier_pill': 'Active Cashier',
      'switch_shift': 'Switch Shift',
      'manage_roster_title': 'Cashier & Shift Roster',
      'add_employee_btn': 'Add Staff',
      'shift_history_title': 'Shift Handover History',
      'tab_z_history': 'Z-Report History',
      'btn_print_bluetooth_z_report': 'Print Bluetooth Z-Report',
      'btn_save_export_pdf': 'Save / Export PDF',
      'btn_confirm_close_shift': 'Confirm & Close Shift (Sync Firebase / Offline JSON)',
      'pdf_saved_success': 'Z-Report PDF saved to Downloads & opened!',
      'online_offline_breakdown': 'Cloud vs Offline JSON Orders',
    },
    'id': {
      // App & Navigation
      'app_title': 'Nusantara Hybrid POS',
      'nav_cashier': 'Kasir POS',
      'nav_menu': 'Menu & Paket',
      'nav_inventory': 'Pengadaan Bahan',
      'nav_analytics': 'Analitik & AI',
      'status_online': 'Online',
      'status_offline': 'Mode Offline',
      'engine_nano': 'Lokal: Gemini Nano',
      'engine_cloud': 'Cloud: Gemini 3.8 Flash',

      // POS Cashier & Order Modes
      'dine_in': 'Makan di Tempat',
      'take_away': 'Bawa Pulang',
      'order_notes': 'Catatan Pesanan',
      'order_notes_hint': 'Contoh: Less ice, pedas sedang, pisah saus...',
      'ai_order_title': 'Kotak Pesanan Cerdas Natural AI',
      'ai_order_hint': 'Ketik atau ucapkan pesanan (contoh: "2 kopi susu gula aren less ice, 1 butter croissant, bayar 100rb")',
      'ai_order_btn': 'Proses Pesanan AI',
      'voice_listening': 'Mendengarkan... Silakan bicara',
      'voice_start': 'Mulai Dikte Suara',
      'voice_stop': 'Hentikan Suara',
      'sample_chips_label': 'Contoh Cepat Dikte:',
      'recommender_title': 'Rekomendasi & Upsell Real-Time AI',
      'recommender_badge': 'Pilihan AI #1',
      'add_to_cart': '+ Tambah ke Keranjang',
      'cart_title': 'Keranjang Pesanan',
      'cart_empty': 'Keranjang kosong. Pilih menu atau gunakan AI Dikte.',
      'total': 'Total',
      'subtotal': 'Subtotal',
      'tax': 'Pajak (PB1)',
      'service_charge': 'Biaya Layanan',
      'checkout': 'Bayar Sekarang',
      'payment_method': 'Metode Pembayaran',
      'cash': 'Tunai (Cash)',
      'qris': 'QRIS',
      'card': 'Kartu Debit/Kredit',
      'cash_received': 'Uang Diterima',
      'change': 'Kembalian',
      'confirm_payment': 'Selesaikan Pembayaran',
      'stock_available': 'tersedia',
      'stock_out': 'Habis',
      'portions': 'porsi',
      'status_ready': 'TERSEDIA',
      'status_sold_out': 'HABIS',
      'force_ready': 'Paksa Tersedia',
      'force_sold_out': 'Paksa Habis',
      'auto_bom': 'Otomatis (BOM)',

      // Menu Categories
      'cat_all': 'Semua',
      'cat_food': 'Makanan',
      'cat_drink': 'Minuman',
      'cat_snack': 'Cemilan',
      'cat_bundle': 'Paket',

      // Menu Screen
      'menu_management_title': 'Resep F&B & Manajemen Menu',
      'add_menu_item': 'Tambah Menu Baru',
      'bom_recipe': 'Resep / Bahan Baku (BOM)',
      'price': 'Harga Jual',
      'cost_of_goods': 'HPP (Modal)',
      'margin': 'Margin',

      // Inventory / Procurement Screen
      'inventory_title': 'Bahan Baku & Pengadaan',
      'restock_btn': 'Catat Pasokan Masuk',
      'ai_procurement_btn': 'Penasihat Pengadaan AI (Gemini 3.8)',
      'current_stock': 'Stok Saat Ini',
      'unit': 'Satuan',
      'safety_stock': 'Stok Minimum',
      'status_safe': 'Aman',
      'status_low': 'Stok Menipis!',
      'supplier_cost': 'Biaya/Satuan',

      // Hero & Mascot
      'hero_headline': 'Pesan Cepat,\nKasir Pintar!',
      'hero_sub': 'Sistem Kasir Pintar Berbasis AI & Offline',

      // Analytics Screen
      'analytics_title': 'Kinerja Bisnis & Wawasan AI',
      'best_sellers': 'Menu Terlaris & Favorit Pelanggan',
      'revenue_breakdown': 'Distribusi Pendapatan Kategori',
      'generate_insight_btn': 'Hasilkan Wawasan Bisnis AI (Gemini 3.8)',
      'publish_bundle_btn': 'Terbitkan Paket ke Kasir POS',
      'bundle_published_toast': 'Paket promo berhasil diterbitkan ke Kasir POS!',
      'insight_analyzing': 'Menganalisis riwayat transaksi & margin dengan Gemini 3.8 Flash...',
      'timeframe_daily': 'Harian (7 Hari)',
      'timeframe_weekly': 'Mingguan (4 Minggu)',
      'timeframe_monthly': 'Bulanan (6 Bulan)',
      'financial_kpi_sales': 'Total Penjualan',
      'financial_kpi_expenses': 'Total Pengeluaran',
      'financial_kpi_profit': 'Keuntungan Bersih',
      'financial_chart_title': 'Performa Keuangan',
      'log_expense_btn': '+ Catat Biaya',
      'log_expense_title': 'Catat Pengeluaran Usaha',
      'expense_category': 'Kategori Biaya',
      'expense_amount': 'Nominal (Rp)',
      'expense_note': 'Keterangan / Catatan',
      'expense_saved_toast': 'Pengeluaran berhasil dicatat!',

      // Receipt
      'receipt_title': 'Struk Pembayaran Termal Digital',
      'receipt_store_name': 'NUSANTARA HYBRID POS CAFÉ',
      'receipt_store_tag': 'Official Hackathon Demo Store',
      'receipt_order_id': 'No. Transaksi #',
      'receipt_date': 'Tanggal',
      'receipt_items': 'Daftar Menu',
      'receipt_copy': 'Salin Teks Struk',
      'receipt_copied': 'Struk berhasil disalin ke clipboard!',
      'receipt_close': 'Tutup & Pesanan Baru',
      'receipt_print': 'Cetak Struk (Thermal / PDF)',
      'receipt_printing': 'Mengirim ke Printer Thermal...',
      'receipt_printed': 'Struk berhasil dikirim ke printer!',
      'receipt_print_bt': 'Cetak Struk Bluetooth ESC/POS',
      'receipt_preview_escpos': 'Pratinjau Raw ESC/POS',
      'receipt_bt_success': 'Struk berhasil dikirim ke Printer Bluetooth!',
      'stat_today_sales': 'Penjualan Hari Ini',
      'stat_orders_today': 'Transaksi Hari Ini',
      'stat_offline_sync': 'Stok Realtime',
      'best_sellers_title': '🔥 Menu Terlaris & Pilihan AI',
      'best_sellers_sub': 'Favorit pelanggan & rekomendasi pintar',
      'all_menu_catalog': 'Katalog Semua Menu',

      // Bluetooth Printer SDK & Offline Outbox
      'printer_sdk_title': 'SDK Printer Thermal Bluetooth',
      'printer_select_device': 'Printer Bluetooth Terpasang',
      'printer_scan_refresh': 'Segarkan Perangkat Bluetooth',
      'printer_no_devices': 'Belum ada printer Bluetooth terpasang. Pasangkan di Pengaturan Android.',
      'printer_paper_width': 'Lebar Kertas Thermal',
      'printer_test_page': 'Cetak Halaman Uji ESC/POS',
      'printer_test_success': 'Halaman uji berhasil dikirim ke printer!',
      'printer_status_connected': 'Siap Mencetak',
      'printer_status_none': 'Belum Ada Printer Dipilih',
      'offline_outbox_title': 'Antrean JSON Offline & Sinkronisasi',
      'offline_queue_badge': 'Antrean JSON Offline',
      'offline_all_synced': 'Semua Tersinkron',
      'offline_view_log': 'Lihat Log JSON Offline',
      'offline_sync_now': 'Sinkronkan ke Cloud Sekarang',
      'cash_insufficient': 'Uang tunai kurang! Kurang',
      'change_kembalian': 'Kembalian',
      'cash_received_label': 'Uang Diterima (Tunai)',

      // Midtrans Sandbox
      'midtrans_sandbox': 'Midtrans Sandbox (QRIS)',
      'midtrans_title': 'Pembayaran Midtrans Sandbox',
      'midtrans_scan_qris': 'Pindai QRIS via GoPay / BCA / ShopeePay Sandbox',
      'midtrans_check_status': 'Periksa Status Pembayaran',
      'midtrans_simulate_settlement': 'Simulasikan Pembayaran Sukses (Bayar Sekarang)',
      'midtrans_offline_warning': 'Midtrans Sandbox membutuhkan koneksi internet. Silakan pilih Tunai untuk mode offline.',
      'qris_tab': 'QRIS Sandbox',
      'card_tab': 'Kartu Debit/Kredit',
      'card_number': 'Nomor Kartu',
      'card_expiry': 'Masa Berlaku (BB/TT)',
      'card_cvv': 'CVV',
      'use_test_card': 'Isi Kartu Uji Sandbox (4811-...)',
      'pay_with_card': 'Bayar dengan Kartu Uji',
      'expires_in': 'Kedaluwarsa dalam',

      // Settings
      'settings_title': 'Pengaturan Toko & POS',
      'settings_store_profile': 'Profil Toko & Struk',
      'settings_store_name': 'Nama Toko',
      'settings_store_tagline': 'Tagline / Slogan',
      'settings_store_address': 'Alamat',
      'settings_store_phone': 'Nomor Telepon',
      'settings_receipt_footer': 'Pesan Kaki Struk',
      'settings_tax_rate': 'Pajak Restoran (PB1 %)',
      'settings_service_charge': 'Biaya Layanan (%)',
      'settings_stock_automation': 'Otomatisasi Stok & Menu AI',
      'settings_auto_deduct': 'Pemotongan Stok Realtime',
      'settings_auto_deduct_sub': 'Potong bahan baku BOM otomatis setiap transaksi (bekerja offline)',
      'settings_ai_stock_guard': 'AI Stock Guard & Auto Sold-Out',
      'settings_ai_stock_guard_sub': 'Otomatis tandai habis saat bahan baku tidak mencukupi',
      'settings_menu_overrides': 'Kendali Cepat Ketersediaan Menu',
      'settings_midtrans_config': 'Midtrans Sandbox & Pembayaran',
      'settings_qris_expiry': 'Durasi Kedaluwarsa QRIS',
      'settings_local_key': 'Server Key Sandbox Lokal (Opsional)',
      'settings_local_key_hint': 'SB-Mid-server-xxxx (Menimpa default build)',
      'settings_hybrid_ai_demo': 'Hybrid AI & Kontrol Demo',
      'settings_ai_mode': 'Mode Inferensi AI Gemini',
      'settings_reset_demo': 'Reset & Isi Ulang Data Demo',
      'settings_reset_confirm': 'Apakah Anda yakin ingin mengatur ulang semua data ke awal?',
      'settings_saved': 'Pengaturan berhasil disimpan!',

      // Charts
      'chart_category_share': 'Porsi Penjualan Kategori (Donut %)',
      'chart_top_sellers_bar': 'Diagram Batang Menu Terlaris',
      'chart_units_sold': 'porsi terjual',

      // General
      'search_menu': 'Cari menu...',
      'error_no_stock': 'Bahan baku tidak mencukupi untuk membuat menu ini!',
      'success_checkout': 'Pesanan berhasil! Stok bahan baku otomatis terpotong.',
      'ai_fallback_notice': 'Fallback offline aktif. Memproses parsing lokal.',

      // Cashier Shift & Handover
      'shift_title': 'Manajemen Shift Kasir',
      'shift_subtitle': 'Serah Terima, Z-Report & Laci Kas',
      'tab_close_shift': 'Tutup Shift (Z-Report)',
      'tab_start_shift': 'Mulai Shift Baru',
      'active_duration': 'Durasi Aktif',
      'total_orders': 'Total Transaksi',
      'gross_sales': 'Penjualan Kotor',
      'cash_sales': 'Penjualan Tunai',
      'non_cash_sales': 'Non-Tunai / QRIS',
      'cash_reconciliation_title': 'Rekonsiliasi Kas Laci',
      'opening_cash': 'Modal Awal Kasir',
      'expected_cash': 'Target Kas di Laci',
      'actual_cash_counted': 'Kas Fisik di Laci',
      'match_target': 'Sesuai Target',
      'cash_variance': 'Selisih Kas',
      'variance_balanced': 'Seimbang (Rp 0)',
      'variance_surplus': 'Surplus (Lebih)',
      'variance_shortage': 'Defisit (Kurang)',
      'ai_handover_notes': 'Catatan Serah Terima AI',
      'generate_ai_notes': 'Buat Catatan AI',
      'handover_notes_hint': 'Catatan serah terima kasir...',
      'print_z_report': 'Cetak Z-Report',
      'close_shift_confirm': 'Tutup Shift & Serahkan',
      'select_cashier': 'Pilih Kasir Masuk',
      'opening_cash_label': 'Modal Awal Kasir Berikutnya',
      'start_shift_btn': 'Mulai Shift Kasir Sekarang',
      'z_report_printed_success': 'Laporan Z-Report berhasil dikirim ke printer thermal!',
      'shift_closed_success': 'Shift berhasil ditutup dan diarsipkan!',
      'shift_started_for': 'Shift kasir aktif dimulai untuk',
      'active_cashier_pill': 'Kasir Aktif',
      'switch_shift': 'Ganti Shift',
      'manage_roster_title': 'Daftar Karyawan & Shift',
      'add_employee_btn': 'Tambah Karyawan',
      'shift_history_title': 'Riwayat Pergantian Shift',
      'tab_z_history': 'Riwayat Z-Report',
      'btn_print_bluetooth_z_report': 'Print Bluetooth Z-Report',
      'btn_save_export_pdf': 'Save / Export PDF',
      'btn_confirm_close_shift': 'Confirm & Close Shift (Sync Firebase / Offline JSON)',
      'pdf_saved_success': 'PDF Z-Report tersimpan di folder Downloads & dibuka!',
      'online_offline_breakdown': 'Pesanan Cloud vs Offline JSON',
    },
  };
}

// Global convenience translator
String tr(String key) => LocalizationService().t(key);
