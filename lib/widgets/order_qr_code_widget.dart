import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Renders a real, scannable QR Code using the pure-Dart 'qr' package
class OrderQrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;

  const OrderQrCodeWidget({
    super.key,
    required this.data,
    this.size = 180,
    this.foregroundColor = const Color(0xFF0F172A),
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);

      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
        child: CustomPaint(
          size: Size(size - 28, size - 28),
          painter: _QrPainter(qrImage: qrImage, color: foregroundColor, data: data),
        ),
      );
    } catch (e) {
      // Fallback if data is too long for default level
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: backgroundColor,
        child: const Icon(Icons.qr_code_2_rounded, size: 80, color: Color(0xFF1E3A8A)),
      );
    }
  }
}

class _QrPainter extends CustomPainter {
  final QrImage qrImage;
  final Color color;
  final String data;

  _QrPainter({required this.qrImage, required this.color, required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    final moduleCount = qrImage.moduleCount;
    final pixelSize = size.width / moduleCount;

    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        if (qrImage.isDark(r, c)) {
          canvas.drawRect(
            Rect.fromLTWH(
              c * pixelSize,
              r * pixelSize,
              pixelSize + 0.35,
              pixelSize + 0.35,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.data != data || oldDelegate.color != color;
}
