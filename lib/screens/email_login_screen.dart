import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/email_auth_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Unified Email + OTP Login Gate for all operational roles in Nusantara Hybrid POS
/// (Kasir, Dapur Kanban, Pembeli, Hardware Hub, Store Operations).
/// Layar Antrian (Queue Display) bypasses this gate cleanly via [onOpenQueueDisplay].
class EmailLoginScreen extends StatefulWidget {
  final VoidCallback onOpenQueueDisplay;
  final VoidCallback? onLoginSuccess;

  const EmailLoginScreen({
    super.key,
    required this.onOpenQueueDisplay,
    this.onLoginSuccess,
  });

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final EmailAuthService _auth = EmailAuthService();
  final SettingsService _settings = SettingsService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _otpSent = false;
  bool _isSending = false;
  bool _isVerifying = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestOtp() async {
    HapticFeedback.lightImpact();
    final email = _emailController.text.trim();
    if (!EmailAuthService.isValidEmail(email)) {
      setState(() {
        _statusMessage = 'Please enter a valid email address (e.g. name@gmail.com).';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    final storeName = _settings.storeName.isNotEmpty ? _settings.storeName : 'Nusantara Hybrid POS';
    final res = await _auth.requestOtp(recipientEmail: email, storeName: storeName);

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _otpSent = res.success;
      _statusMessage = res.message;
      _statusIsError = !res.success;
      if (res.devPreviewCode != null && !res.sentViaGmail) {
        _otpController.text = res.devPreviewCode!;
      }
    });
  }

  Future<void> _handleVerifyOtp() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });

    final ok = await _auth.verifyOtp(
      email: _emailController.text,
      code: _otpController.text,
      name: _nameController.text,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (ok) {
      widget.onLoginSuccess?.call();
    } else {
      setState(() {
        _statusMessage = 'Invalid or expired OTP code. Please request a new code.';
        _statusIsError = true;
      });
    }
  }

  Future<void> _showGmailSetupDialog() async {
    final senderCtrl = TextEditingController(text: _auth.senderEmail);
    final passCtrl = TextEditingController(text: _auth.gmailAppPassword);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_rounded, color: AppTheme.royalBlue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gmail OTP Sender Settings',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the 16-digit Google App Password from the sender account so OTP codes are delivered directly to user inboxes.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: senderCtrl,
                decoration: InputDecoration(
                  labelText: 'Sender Email (Gmail)',
                  prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Gmail App Password (16 Digits)',
                  hintText: 'xxxx xxxx xxxx xxxx',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'How to create: Google Account -> Security -> 2-Step Verification -> App Passwords.',
                style: TextStyle(fontSize: 10.5, color: AppTheme.royalBlue, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _auth.saveGmailConfig(
                senderEmail: senderCtrl.text,
                appPassword: passCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF15803D),
                    behavior: SnackBarBehavior.floating,
                    content: Text('✓ OTP sender settings (${_auth.senderEmail}) saved!'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.iceBlueScaffold,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.royalBlue.withAlpha(20),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.mark_email_unread_rounded,
                              size: 34,
                              color: AppTheme.brightYellow,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'Nusantara POS Account Login',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Center(
                          child: Text(
                            'Sign in once via Email + OTP Code (Cashier, Kitchen, Customer & Hardware). Auto-saved & secure.',
                            style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Sender Badge + Quick Setup
                        ListenableBuilder(
                          listenable: _auth,
                          builder: (context, _) {
                            final configured = _auth.hasGmailAppPassword;
                            return InkWell(
                              onTap: _showGmailSetupDialog,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: configured ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: configured ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      configured ? Icons.verified_rounded : Icons.settings_suggest_rounded,
                                      size: 16,
                                      color: configured ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        configured
                                            ? 'OTP Active via ${_auth.senderEmail}'
                                            : 'Sender: ${_auth.senderEmail} (Tap to set App Password)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: configured ? const Color(0xFF166534) : const Color(0xFF92400E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Alex Morgan',
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.royalBlue),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        const Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'youremail@gmail.com',
                            prefixIcon: const Icon(Icons.email_outlined, size: 18, color: AppTheme.royalBlue),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),

                        if (_otpSent) ...[
                          const SizedBox(height: 14),
                          const Text('OTP Code (6 Digits from Email)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkNavy)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: InputDecoration(
                              hintText: '123456',
                              counterText: '',
                              prefixIcon: const Icon(Icons.lock_clock_rounded, size: 18, color: Color(0xFFD97706)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ],

                        if (_statusMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _statusIsError ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _statusIsError ? const Color(0xFFFCA5A5) : const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _statusIsError ? const Color(0xFF991B1B) : AppTheme.royalBlue,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        if (!_otpSent)
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: _isSending ? null : _handleRequestOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.royalBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: Text(
                                _isSending ? 'Sending OTP to Email...' : 'Send OTP Code to Email',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                            ),
                          )
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: _isVerifying ? null : _handleVerifyOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF15803D),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: _isVerifying
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.verified_user_rounded, size: 18),
                              label: const Text(
                                'Verify OTP & Sign In (Auto-Save)',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: _isSending ? null : _handleRequestOtp,
                              child: const Text(
                                'Resend OTP Code',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.royalBlue),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Exempt Queue Display Shortcut (No Login Required)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onOpenQueueDisplay();
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.royalBlue,
                        side: const BorderSide(color: AppTheme.royalBlue, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.tv_rounded, size: 20, color: Color(0xFFD97706)),
                      label: const Text(
                        'Open Queue Display (No Login Required)',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
