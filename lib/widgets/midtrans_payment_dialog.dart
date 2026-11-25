import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/order_item.dart';
import '../services/localization_service.dart';
import '../services/midtrans_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'qris_painter.dart';

class MidtransPaymentDialog extends StatefulWidget {
  final String orderId;
  final double total;
  final List<OrderItem> items;
  final NumberFormat currencyFormatter;
  final void Function(String paymentMethod) onPaymentSuccess;

  const MidtransPaymentDialog({
    super.key,
    required this.orderId,
    required this.total,
    required this.items,
    required this.currencyFormatter,
    required this.onPaymentSuccess,
  });

  @override
  State<MidtransPaymentDialog> createState() => _MidtransPaymentDialogState();
}

class _MidtransPaymentDialogState extends State<MidtransPaymentDialog> with SingleTickerProviderStateMixin {
  final MidtransService _midtrans = MidtransService();
  final SettingsService _settings = SettingsService();

  late TabController _tabController;
  Timer? _countdownTimer;
  late int _remainingSeconds;

  bool _isLoading = true;
  bool _isCheckingStatus = false;
  MidtransSnapResponse? _snapResponse;
  String _statusMessage = 'Awaiting Payment (Pending)';
  bool _isSettled = false;

  // Card Tab Form Controllers
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _cardCvvController = TextEditingController();
  String _detectedCardBrand = 'Unknown';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _remainingSeconds = _settings.qrisExpiryMinutes * 60;
    _startTimer();
    _initiateSnap();
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _initiateSnap() async {
    setState(() => _isLoading = true);

    final resp = await _midtrans.createSnapTransaction(
      orderId: widget.orderId,
      grossAmount: widget.total,
      items: widget.items,
    );

    if (mounted) {
      setState(() {
        _snapResponse = resp;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCheckStatus() async {
    setState(() => _isCheckingStatus = true);

    try {
      final status = await _midtrans.checkTransactionStatus(widget.orderId);
      final txStatus = status['transaction_status']?.toString() ?? 'pending';

      if (mounted) {
        setState(() {
          if (txStatus == 'settlement' || txStatus == 'capture') {
            _statusMessage = 'PAID (Settlement Verified)';
            _isSettled = true;
          } else if (txStatus == 'pending') {
            _statusMessage = 'Awaiting Payment (Pending)';
          } else {
            _statusMessage = 'Status: $txStatus';
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _isSettled ? const Color(0xFF15803D) : AppTheme.royalBlue,
            content: Text('Midtrans Sandbox Status: $txStatus'),
            duration: const Duration(seconds: 2),
          ),
        );

        if (_isSettled) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onPaymentSuccess('Midtrans QRIS');
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingStatus = false);
      }
    }
  }

  void _handleSimulateQrisSettlement() {
    setState(() {
      _isSettled = true;
      _statusMessage = 'PAID (QRIS Settlement)';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF15803D),
        content: Text('QRIS Payment Verified Successfully!'),
        duration: Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onPaymentSuccess('Midtrans QRIS');
      }
    });
  }

  void _fillTestCard() {
    HapticFeedback.lightImpact();
    setState(() {
      _cardNumberController.text = '4811 1111 1111 1114';
      _cardExpiryController.text = '12/28';
      _cardCvvController.text = '123';
      _detectedCardBrand = 'VISA';
    });
  }

  void _handleCardPay() {
    if (_cardNumberController.text.replaceAll(' ', '').length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.roseRed,
          content: Text('Please enter a valid 16-digit card number.'),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isSettled = true;
      _statusMessage = 'PAID (Card Capture Verified)';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF15803D),
        content: Text('$_detectedCardBrand Payment Completed Successfully!'),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onPaymentSuccess('Midtrans Card ($_detectedCardBrand)');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _remainingSeconds <= 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.royalBlue.withAlpha(50),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Store Name, Order ID, and Timer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.royalBlue, Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.payment_rounded, color: AppTheme.brightYellow, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _settings.storeName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.goldenAmber,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'SANDBOX',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.darkNavy,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Order #${widget.orderId}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live Countdown Timer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isExpired ? AppTheme.roseRed : Colors.white.withAlpha(35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isExpired ? Colors.red.shade300 : AppTheme.brightYellow.withAlpha(160),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: isExpired ? Colors.white : AppTheme.brightYellow,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formattedTime,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: isExpired ? Colors.white : AppTheme.brightYellow,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Gross Amount Strip
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: AppTheme.lightBlueTint,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL PAYMENT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      widget.currencyFormatter.format(widget.total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ],
                ),
              ),

              // Payment Channel Tabs: QRIS & Card
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.royalBlue,
                labelColor: AppTheme.royalBlue,
                unselectedLabelColor: AppTheme.slateMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    text: tr('qris_tab'),
                  ),
                  Tab(
                    icon: const Icon(Icons.credit_card_rounded, size: 18),
                    text: tr('card_tab'),
                  ),
                ],
              ),

              // Tab Views
              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Authentic QRIS View
                    _buildQrisTabView(isExpired),

                    // Tab 2: Debit / Credit Card View
                    _buildCardTabView(isExpired),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: QRIS VIEW ---
  Widget _buildQrisTabView(bool isExpired) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.royalBlue),
            SizedBox(height: 12),
            Text('Preparing QRIS Sandbox...', style: TextStyle(fontSize: 12, color: AppTheme.slateMuted)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Authentic QRIS Matrix Frame
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Official QRIS Banner
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'QRIS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Text(
                      'NMID: ID1020260389281',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: AppTheme.slateMuted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Pure-Flutter QRIS Canvas
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(160, 160),
                        painter: QrisPainter(
                          data: _snapResponse?.qrString ?? widget.orderId,
                          color: isExpired ? Colors.grey : AppTheme.darkNavy,
                        ),
                      ),
                      // Center Logo
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _settings.storeName,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.darkNavy),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Status & Token Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isSettled ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSettled ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                      size: 11,
                      color: _isSettled ? const Color(0xFF15803D) : const Color(0xFFB45309),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: _isSettled ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),

          // Buttons
          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: _isCheckingStatus || isExpired ? null : _handleCheckStatus,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.royalBlue,
                      side: const BorderSide(color: AppTheme.royalBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                    child: _isCheckingStatus
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.royalBlue),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: isExpired ? null : _handleSimulateQrisSettlement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.goldenAmber,
                      foregroundColor: AppTheme.darkNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.darkNavy),
                    label: const Text(
                      'Pay Now (Simulate QRIS)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 2: CREDIT / DEBIT CARD VIEW ---
  Widget _buildCardTabView(bool isExpired) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1-Tap Quick Fill Sandbox Test Card Button
          Align(
            alignment: Alignment.centerRight,
            child: ActionChip(
              avatar: const Icon(Icons.flash_on_rounded, size: 14, color: AppTheme.warmGoldDark),
              label: const Text(
                'Isi Kartu Uji (4811-...)',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.royalBlue),
              ),
              backgroundColor: AppTheme.lightBlueTint,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onPressed: _fillTestCard,
            ),
          ),
          const SizedBox(height: 6),

          // Card Number Field
          TextField(
            controller: _cardNumberController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              setState(() {
                if (val.startsWith('4')) {
                  _detectedCardBrand = 'VISA';
                } else if (val.startsWith('5')) {
                  _detectedCardBrand = 'Mastercard';
                } else {
                  _detectedCardBrand = 'Unknown';
                }
              });
            },
            decoration: InputDecoration(
              labelText: tr('card_number'),
              labelStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.credit_card_rounded, size: 18, color: AppTheme.royalBlue),
              suffixIcon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlueTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _detectedCardBrand,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppTheme.royalBlue),
                ),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // Expiry & CVV Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cardExpiryController,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: tr('card_expiry'),
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cardCvvController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('card_cvv'),
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Info Note
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: AppTheme.slateMuted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Simulasi 3D-Secure Sandbox Midtrans aktif (Tanpa pemotongan saldo nyata)',
                    style: TextStyle(fontSize: 9, color: AppTheme.slateMuted),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Pay with Card Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: isExpired ? null : _handleCardPay,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.lock_outline_rounded, size: 16),
              label: Text(
                '${tr('pay_with_card')} (${widget.currencyFormatter.format(widget.total)})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
