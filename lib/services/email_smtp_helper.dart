import 'email_smtp_stub.dart'
    if (dart.library.io) 'email_smtp_io.dart';

/// Platform-safe Gmail SMTP sender interface (uses `mailer` on Android/IO and stub on Web).
abstract class EmailSmtpHelper {
  static Future<bool> sendGmailOtp({
    required String senderEmail,
    required String appPassword,
    required String recipientEmail,
    required String otpCode,
    required String storeName,
  }) =>
      sendGmailOtpImpl(
        senderEmail: senderEmail,
        appPassword: appPassword,
        recipientEmail: recipientEmail,
        otpCode: otpCode,
        storeName: storeName,
      );
}
