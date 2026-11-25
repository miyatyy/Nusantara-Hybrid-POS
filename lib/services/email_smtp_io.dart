import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

Future<bool> sendGmailOtpImpl({
  required String senderEmail,
  required String appPassword,
  required String recipientEmail,
  required String otpCode,
  required String storeName,
}) async {
  try {
    final cleanPass = appPassword.replaceAll(' ', '').trim();
    if (senderEmail.trim().isEmpty || cleanPass.isEmpty || recipientEmail.trim().isEmpty) {
      return false;
    }

    final smtpServer = gmail(senderEmail.trim(), cleanPass);

    final message = Message()
      ..from = Address(senderEmail.trim(), '$storeName (POS System)')
      ..recipients.add(recipientEmail.trim())
      ..subject = '[$storeName] Kode OTP Login Anda: $otpCode'
      ..text = '''
Halo,

Berikut adalah kode OTP untuk masuk ke sistem $storeName:

KODE OTP: $otpCode

This code is valid for 5 minutes. Do not share this code with anyone.

Automatically sent by $storeName ($senderEmail).
'''
      ..html = '''
<div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto; border: 1px solid #E2E8F0; border-radius: 16px; overflow: hidden;">
  <div style="background: #1E3A8A; padding: 20px; text-align: center; color: #FFFFFF;">
    <h2 style="margin: 0; font-size: 18px;">$storeName</h2>
    <p style="margin: 4px 0 0; font-size: 12px; color: #FDE68A;">POS Account Security Verification</p>
  </div>
  <div style="padding: 24px; background: #FFFFFF; text-align: center;">
    <p style="font-size: 14px; color: #334155; margin-top: 0;">Use the following OTP code to sign in to Nusantara Hybrid POS:</p>
    <div style="display: inline-block; background: #EFF6FF; border: 2px dashed #1E3A8A; border-radius: 12px; padding: 14px 28px; margin: 12px 0;">
      <span style="font-size: 28px; font-weight: 900; letter-spacing: 6px; color: #1E3A8A;">$otpCode</span>
    </div>
    <p style="font-size: 12px; color: #64748B; margin-bottom: 0;">This code is valid for <b>5 minutes</b>. Do not share it with anyone.</p>
  </div>
  <div style="background: #F8FAFC; padding: 12px; text-align: center; font-size: 11px; color: #94A3B8;">
    Sent by POS System ($senderEmail)
  </div>
</div>
''';

    await send(message, smtpServer).timeout(const Duration(seconds: 12));
    debugPrint('[EmailSmtp] OTP sent successfully from $senderEmail to $recipientEmail');
    return true;
  } catch (e) {
    debugPrint('[EmailSmtp] Failed to send OTP via Gmail SMTP: $e');
    return false;
  }
}
