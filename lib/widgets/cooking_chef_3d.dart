import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Global in-memory cache for processed transparent Chef Logo ui.Image
class ChefMascotImageCache {
  static ui.Image? transparentChefImage;
  static Future<ui.Image?>? loadingFuture;

  static Future<ui.Image?> getTransparentImage() {
    if (transparentChefImage != null) {
      return Future.value(transparentChefImage);
    }
    if (loadingFuture != null) {
      return loadingFuture!;
    }
    loadingFuture = _processChefImage();
    return loadingFuture!;
  }

  static Future<ui.Image?> _processChefImage() async {
    try {
      // 1. Load ByteData from assets
      ByteData byteData;
      try {
        byteData = await rootBundle.load('assets/images/chef_cooking_3d.png');
      } catch (_) {
        byteData = await rootBundle.load('assets/images/chef_logo.png');
      }

      // 2. Instantiate ImageCodec (already clean transparent 512x512 PNG)
      final codec = await ui.instantiateImageCodec(byteData.buffer.asUint8List());
      final frameInfo = await codec.getNextFrame();
      final sourceImage = frameInfo.image;
      transparentChefImage = sourceImage;
      return sourceImage;
    } catch (e) {
      debugPrint('ChefMascotImageCache error: $e');
      return null;
    }
  }
}

/// Transparent Colored Chef Mascot Widget
/// - Crops ONLY the colored female chef logo (ignoring B&W)
/// - Converts near-white pixels (r>232, g>232, b>232) to 100% true transparency
/// - Reconstructs ui.Image via decodeImageFromPixels
/// - Smooth floating AnimationController with subtle golden steam sparkles
class CookingChef3DWidget extends StatefulWidget {
  final double size;
  final bool animate;
  final VoidCallback? onToggleMascot;
  final bool showGatotkaca;

  const CookingChef3DWidget({
    super.key,
    this.size = 120,
    this.animate = true,
    this.onToggleMascot,
    this.showGatotkaca = false,
  });

  @override
  State<CookingChef3DWidget> createState() => _CookingChef3DWidgetState();
}

class _CookingChef3DWidgetState extends State<CookingChef3DWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _decodedImage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    if (widget.animate) {
      _controller.repeat();
    }

    _initImage();
  }

  void _initImage() {
    if (ChefMascotImageCache.transparentChefImage != null) {
      _decodedImage = ChefMascotImageCache.transparentChefImage;
    } else {
      ChefMascotImageCache.getTransparentImage().then((img) {
        if (mounted && img != null) {
          setState(() {
            _decodedImage = img;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CookingChef3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
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
    final s = widget.size;

    return GestureDetector(
      onTap: widget.onToggleMascot,
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            final bob = widget.animate ? math.sin(progress * 2 * math.pi) * 3.5 : 0.0;

            return Transform.translate(
              offset: Offset(0, bob),
              child: _decodedImage != null
                  ? CustomPaint(
                      size: Size(s, s),
                      painter: _TransparentChefSparklesPainter(
                        image: _decodedImage!,
                        progress: progress,
                      ),
                    )
                  : Image.asset(
                      'assets/images/chef_cooking_3d.png',
                      width: s,
                      height: s,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackLogo(s),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFallbackLogo(double s) {
    return Container(
      width: s,
      height: s,
      decoration: const BoxDecoration(
        color: AppTheme.royalBlue,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.restaurant_rounded, color: AppTheme.brightYellow, size: 40),
      ),
    );
  }
}

/// CustomPainter that renders the transparent ui.Image and subtle golden steam sparkles
class _TransparentChefSparklesPainter extends CustomPainter {
  final ui.Image image;
  final double progress;

  _TransparentChefSparklesPainter({
    required this.image,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Transparent Chef Emblem
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..filterQuality = FilterQuality.high;

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    // 2. Draw Subtle Golden Steam Sparkles
    final sparkPaint = Paint()
      ..color = const Color(0xFFFBBF24) // Warm Golden Amber
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Twinkling steam sparkles floating above the skillet
    for (int i = 0; i < 4; i++) {
      final t = (progress + (i / 4.0)) % 1.0;
      final sparkleY = (cy - 10) - (t * 30.0);
      final sparkleX = (cx - 15) + (math.sin(t * 2 * math.pi + i) * 12.0);
      final sparkleRadius = math.sin(t * math.pi) * 2.2;

      if (sparkleRadius > 0.2) {
        sparkPaint.color = const Color(0xFFFBBF24).withAlpha((math.sin(t * math.pi) * 220).toInt());
        canvas.drawCircle(Offset(sparkleX, sparkleY), sparkleRadius, sparkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TransparentChefSparklesPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.image != image;
  }
}

/// Reusable Blue Chef Logo Widget
class ChefLogoWidget extends StatelessWidget {
  final double size;
  final bool animate;

  const ChefLogoWidget({
    super.key,
    this.size = 120,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    return CookingChef3DWidget(size: size, animate: animate);
  }
}
