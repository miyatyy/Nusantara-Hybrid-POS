import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GatotkacaHeroMascot extends StatefulWidget {
  final double size;
  final bool animate;

  const GatotkacaHeroMascot({
    super.key,
    this.size = 118,
    this.animate = true,
  });

  @override
  State<GatotkacaHeroMascot> createState() => _GatotkacaHeroMascotState();
}

class _GatotkacaHeroMascotState extends State<GatotkacaHeroMascot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bobAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // 6px vertical floating bobbing motion (-3.0 to +3.0)
    _bobAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Subtle breathing pulse for lightning aura
    _pulseAnimation = Tween<double>(begin: 0.90, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant GatotkacaHeroMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auraSize = widget.size * 1.35;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: auraSize,
          height: auraSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing Royal Blue & Golden Yellow Lightning Aura
              CustomPaint(
                size: Size(auraSize, auraSize),
                painter: _LightningAuraPainter(
                  pulse: _pulseAnimation.value,
                  progress: _controller.value,
                ),
              ),

              // Floating 6px Bobbing Mascot
              Transform.translate(
                offset: Offset(0, _bobAnimation.value),
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/gatotkaca_mascot.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildFallbackWarriorEmblem(widget.size);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallbackWarriorEmblem(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), AppTheme.royalBlue],
          stops: [0.0, 0.65, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.military_tech_rounded,
              color: AppTheme.brightYellow,
              size: 42,
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.royalBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'GATOTKACA',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.brightYellow,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LightningAuraPainter extends CustomPainter {
  final double pulse;
  final double progress;

  _LightningAuraPainter({
    required this.pulse,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * 0.78 * pulse;

    // 1. Soft Radial Glowing Halo (Royal Blue to Golden Yellow)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF59E0B).withAlpha(120),
          const Color(0xFF2563EB).withAlpha(60),
          Colors.transparent,
        ],
        stops: const [0.2, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.25));

    canvas.drawCircle(center, radius * 1.25, glowPaint);

    // 2. Pulsing Golden Energy Arc
    final arcPaint = Paint()
      ..color = const Color(0xFFF59E0B).withAlpha(80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, arcPaint);

    // 3. Crackling Lightning Sparks
    final sparkPaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final goldSparkPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const sparkCount = 6;
    for (int i = 0; i < sparkCount; i++) {
      final angle = (i * (2 * math.pi / sparkCount)) + (progress * 0.8);
      final r1 = radius * 0.85;
      final r2 = radius * (1.1 + (0.12 * math.sin(progress * 2 * math.pi + i)));

      final start = Offset(
        center.dx + r1 * math.cos(angle),
        center.dy + r1 * math.sin(angle),
      );

      final midAngle = angle + (i.isEven ? 0.12 : -0.12);
      final mid = Offset(
        center.dx + ((r1 + r2) / 2) * math.cos(midAngle),
        center.dy + ((r1 + r2) / 2) * math.sin(midAngle),
      );

      final end = Offset(
        center.dx + r2 * math.cos(angle),
        center.dy + r2 * math.sin(angle),
      );

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(end.dx, end.dy);

      canvas.drawPath(path, i.isEven ? goldSparkPaint : sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightningAuraPainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.progress != progress;
  }
}
