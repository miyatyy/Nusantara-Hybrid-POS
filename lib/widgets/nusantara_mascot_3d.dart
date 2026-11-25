import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Cheerful, high-detail 3D-shaded Cartoon Barista/Chef Mascot holding a coffee cup & burger.
/// Checks for `assets/images/mascot_chef.png` and falls back to a 100% offline pure-Flutter
/// vector CustomPainter with claymorphic depth, radial lighting, and gentle idle bobbing.
class NusantaraMascot3D extends StatefulWidget {
  final double size;
  final bool animate;

  const NusantaraMascot3D({
    super.key,
    this.size = 140,
    this.animate = true,
  });

  @override
  State<NusantaraMascot3D> createState() => _NusantaraMascot3DState();
}

class _NusantaraMascot3DState extends State<NusantaraMascot3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;
  late final Animation<double> _bobAnimation;
  bool _hasImageAsset = false;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _bobAnimation = Tween<double>(begin: -3.5, end: 3.5).animate(
      CurvedAnimation(parent: _bobController, curve: Curves.easeInOutSine),
    );

    if (widget.animate) {
      _bobController.repeat(reverse: true);
    }

    _checkAssetImage();
  }

  Future<void> _checkAssetImage() async {
    try {
      await rootBundle.load('assets/images/mascot_chef.png');
      if (mounted) setState(() => _hasImageAsset = true);
    } catch (_) {
      if (mounted) setState(() => _hasImageAsset = false);
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget mascotContent;
    if (_hasImageAsset) {
      mascotContent = Image.asset(
        'assets/images/mascot_chef.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    } else {
      mascotContent = CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _MascotVectorPainter(),
      );
    }

    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: mascotContent,
      );
    }

    return AnimatedBuilder(
      animation: _bobAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bobAnimation.value),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: child,
          ),
        );
      },
      child: mascotContent,
    );
  }
}

class _MascotVectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 140.0;
    canvas.save();
    canvas.scale(scale, scale);

    // 1. Soft Floor Clay Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(70, 134), width: 78, height: 10),
      shadowPaint,
    );

    // 2. Barista Body / Apron & Arms (Claymorphic Shaded)
    final bodyRect = Rect.fromCenter(center: const Offset(70, 102), width: 54, height: 44);
    final bodyGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppTheme.royalBlue,
        const Color(0xFF1E40AF),
        const Color(0xFF172554),
      ],
    );
    final bodyPaint = Paint()..shader = bodyGrad.createShader(bodyRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(18)),
      bodyPaint,
    );

    // White Apron Overlay
    final apronRect = Rect.fromCenter(center: const Offset(70, 106), width: 34, height: 34);
    final apronPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
      ).createShader(apronRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(apronRect, const Radius.circular(10)),
      apronPaint,
    );

    // Golden Buttons on Apron
    final goldButtonPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFDE047), AppTheme.goldenAmber],
      ).createShader(const Rect.fromLTWH(66, 94, 8, 8));
    canvas.drawCircle(const Offset(70, 97), 3.5, goldButtonPaint);
    canvas.drawCircle(const Offset(70, 108), 3.5, goldButtonPaint);

    // Left Arm & Hand (Holding Coffee) - Left side (Viewer's left: x ~ 35)
    final armPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
      ).createShader(const Rect.fromLTWH(30, 90, 25, 25));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(32, 92, 16, 22), const Radius.circular(8)),
      armPaint,
    );

    // Left Hand (Skin Tone)
    final skinGrad = const RadialGradient(
      center: Alignment(-0.3, -0.3),
      colors: [Color(0xFFFFDFBA), Color(0xFFFBBF87), Color(0xFFE59C5C)],
    );
    final handPaint = Paint()
      ..shader = skinGrad.createShader(const Rect.fromLTWH(26, 98, 14, 14));
    canvas.drawCircle(const Offset(33, 104), 7, handPaint);

    // Left Hand Item: 3D Coffee Cup
    _drawCoffeeCup(canvas, const Offset(24, 94));

    // Right Arm & Hand (Holding Burger) - Right side (Viewer's right: x ~ 105)
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(92, 92, 16, 22), const Radius.circular(8)),
      armPaint,
    );
    final rightHandPaint = Paint()
      ..shader = skinGrad.createShader(const Rect.fromLTWH(100, 98, 14, 14));
    canvas.drawCircle(const Offset(107, 104), 7, rightHandPaint);

    // Right Hand Item: 3D Burger
    _drawBurger(canvas, const Offset(116, 98));

    // 3. Cheerful Head & Face (Claymorphic Round Sphere)
    final faceRect = Rect.fromCircle(center: const Offset(70, 64), radius: 26);
    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 0.9,
        colors: const [
          Color(0xFFFFF0DC),
          Color(0xFFFFDAB9),
          Color(0xFFF9B880),
        ],
      ).createShader(faceRect);

    // Face shadow
    final faceShadowPaint = Paint()
      ..color = Colors.black.withAlpha(25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(const Offset(70, 66), 26, faceShadowPaint);
    canvas.drawCircle(const Offset(70, 64), 26, facePaint);

    // Rosy Cheeks (Soft blushing clay spheres)
    final blushPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFF87171).withAlpha(150), const Color(0xFFF87171).withAlpha(0)],
      ).createShader(const Rect.fromLTWH(50, 66, 12, 12));
    canvas.drawCircle(const Offset(55, 71), 5.5, blushPaint);

    final rightBlushPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFF87171).withAlpha(150), const Color(0xFFF87171).withAlpha(0)],
      ).createShader(const Rect.fromLTWH(78, 66, 12, 12));
    canvas.drawCircle(const Offset(85, 71), 5.5, rightBlushPaint);

    // Cute Cheerful Smiling Eyes (Happy Arc)
    final eyePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final leftEyePath = Path()
      ..moveTo(56, 61)
      ..quadraticBezierTo(60, 56, 64, 61);
    canvas.drawPath(leftEyePath, eyePaint);

    final rightEyePath = Path()
      ..moveTo(76, 61)
      ..quadraticBezierTo(80, 56, 84, 61);
    canvas.drawPath(rightEyePath, eyePaint);

    // Eyebrows
    final browPaint = Paint()
      ..color = const Color(0xFF78350F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(56, 54), const Offset(64, 53), browPaint);
    canvas.drawLine(const Offset(76, 53), const Offset(84, 54), browPaint);

    // Happy Open Smile (with pink tongue)
    final mouthPath = Path()
      ..moveTo(63, 69)
      ..quadraticBezierTo(70, 81, 77, 69)
      ..close();
    final mouthPaint = Paint()..color = const Color(0xFF991B1B);
    canvas.drawPath(mouthPath, mouthPaint);

    // Mouth Tongue Highlight
    final tonguePath = Path()
      ..moveTo(65, 74)
      ..quadraticBezierTo(70, 80, 75, 74)
      ..close();
    final tonguePaint = Paint()..color = const Color(0xFFFB7185);
    canvas.drawPath(tonguePath, tonguePaint);

    // Soft Cute Nose
    final nosePaint = Paint()
      ..color = const Color(0xFFEA580C).withAlpha(120)
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: const Offset(70, 65), width: 4.5, height: 3), nosePaint);

    // 4. Chef Toque (Puffy 3D Chef Hat)
    _drawChefToque(canvas);

    canvas.restore();
  }

  void _drawChefToque(Canvas canvas) {
    // Hat Band / Base (Rim)
    final rimRect = Rect.fromCenter(center: const Offset(70, 42), width: 46, height: 12);
    final rimPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
      ).createShader(rimRect);
    canvas.drawRRect(RRect.fromRectAndRadius(rimRect, const Radius.circular(6)), rimPaint);

    // Golden Hat Emblem Star
    final starPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFDE047), AppTheme.goldenAmber],
      ).createShader(const Rect.fromLTWH(66, 38, 8, 8));
    canvas.drawCircle(const Offset(70, 42), 3.5, starPaint);

    // Hat Puffy Crown (3-Lobe 3D Cloud)
    final puffPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.4),
        radius: 0.8,
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFF1F5F9),
          Color(0xFFCBD5E1),
        ],
      ).createShader(const Rect.fromLTWH(42, 14, 56, 32));

    // Left puff
    canvas.drawCircle(const Offset(52, 28), 12, puffPaint);
    // Right puff
    canvas.drawCircle(const Offset(88, 28), 12, puffPaint);
    // Center big puff
    canvas.drawCircle(const Offset(70, 22), 15, puffPaint);

    // Subtle 3D Fold Lines
    final foldPaint = Paint()
      ..color = const Color(0xFF94A3B8).withAlpha(70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(62, 24), const Offset(64, 37), foldPaint);
    canvas.drawLine(const Offset(78, 24), const Offset(76, 37), foldPaint);
  }

  void _drawCoffeeCup(Canvas canvas, Offset pos) {
    // Takeaway Coffee Cup with lid and sleeve
    final cupRect = Rect.fromCenter(center: pos, width: 18, height: 24);

    // Cup Shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy + 13), width: 16, height: 4),
      Paint()..color = Colors.black.withAlpha(30),
    );

    // Cup Body
    final cupBody = Path()
      ..moveTo(pos.dx - 8, pos.dy - 10)
      ..lineTo(pos.dx + 8, pos.dy - 10)
      ..lineTo(pos.dx + 6.5, pos.dy + 11)
      ..lineTo(pos.dx - 6.5, pos.dy + 11)
      ..close();
    final cupPaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
      ).createShader(cupRect);
    canvas.drawPath(cupBody, cupPaint);

    // Kraft Paper Sleeve (Brown)
    final sleeveRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy), width: 15, height: 10);
    final sleevePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFD97706), Color(0xFFB45309)],
      ).createShader(sleeveRect);
    canvas.drawRRect(RRect.fromRectAndRadius(sleeveRect, const Radius.circular(2)), sleevePaint);

    // Cup Golden / Royal Blue Lid
    final lidRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy - 11), width: 19, height: 4.5);
    final lidPaint = Paint()..color = AppTheme.royalBlue;
    canvas.drawRRect(RRect.fromRectAndRadius(lidRect, const Radius.circular(3)), lidPaint);

    // Warm Steam Curls
    final steamPaint = Paint()
      ..color = const Color(0xFF94A3B8).withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final steam1 = Path()
      ..moveTo(pos.dx - 2, pos.dy - 14)
      ..quadraticBezierTo(pos.dx - 4, pos.dy - 18, pos.dx - 1, pos.dy - 22);
    canvas.drawPath(steam1, steamPaint);

    final steam2 = Path()
      ..moveTo(pos.dx + 3, pos.dy - 14)
      ..quadraticBezierTo(pos.dx + 5, pos.dy - 19, pos.dx + 2, pos.dy - 23);
    canvas.drawPath(steam2, steamPaint);
  }

  void _drawBurger(Canvas canvas, Offset pos) {
    // 3D Juicy Burger: Top Bun, Lettuce, Tomato, Cheese, Patty, Bottom Bun
    // Burger shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy + 12), width: 22, height: 5),
      Paint()..color = Colors.black.withAlpha(30),
    );

    // Bottom Bun
    final bottomBunRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 8), width: 20, height: 5);
    final bunPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.2),
        colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
      ).createShader(bottomBunRect);
    canvas.drawRRect(RRect.fromRectAndRadius(bottomBunRect, const Radius.circular(3)), bunPaint);

    // Beef Patty
    final pattyRect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 4), width: 21, height: 4.5);
    final pattyPaint = Paint()..color = const Color(0xFF78350F);
    canvas.drawRRect(RRect.fromRectAndRadius(pattyRect, const Radius.circular(2)), pattyPaint);

    // Melted Golden Cheese
    final cheesePath = Path()
      ..moveTo(pos.dx - 10, pos.dy + 2)
      ..lineTo(pos.dx + 10, pos.dy + 2)
      ..lineTo(pos.dx + 5, pos.dy + 5)
      ..lineTo(pos.dx - 3, pos.dy + 3)
      ..lineTo(pos.dx - 8, pos.dy + 5)
      ..close();
    final cheesePaint = Paint()..color = const Color(0xFFFACC15);
    canvas.drawPath(cheesePath, cheesePaint);

    // Lettuce Ruffle (Fresh Green)
    final lettucePaint = Paint()..color = const Color(0xFF22C55E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(pos.dx, pos.dy), width: 22, height: 3.5),
        const Radius.circular(2),
      ),
      lettucePaint,
    );

    // Top Bun (Puffy Dome)
    final topBunPath = Path()
      ..moveTo(pos.dx - 11, pos.dy - 1)
      ..quadraticBezierTo(pos.dx, pos.dy - 12, pos.dx + 11, pos.dy - 1)
      ..close();
    final topBunPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.4),
        colors: const [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFB45309)],
      ).createShader(Rect.fromCenter(center: Offset(pos.dx, pos.dy - 5), width: 24, height: 12));
    canvas.drawPath(topBunPath, topBunPaint);

    // Sesame Seeds on top bun
    final sesamePaint = Paint()..color = const Color(0xFFFEF3C7);
    canvas.drawCircle(Offset(pos.dx - 5, pos.dy - 5), 0.9, sesamePaint);
    canvas.drawCircle(Offset(pos.dx, pos.dy - 7), 0.9, sesamePaint);
    canvas.drawCircle(Offset(pos.dx + 5, pos.dy - 5), 0.9, sesamePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
