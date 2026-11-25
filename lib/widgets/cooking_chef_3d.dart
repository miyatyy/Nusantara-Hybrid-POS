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

      // 2. Instantiate ImageCodec
      final codec = await ui.instantiateImageCodec(byteData.buffer.asUint8List());
      final frameInfo = await codec.getNextFrame();
      final sourceImage = frameInfo.image;

      final srcWidth = sourceImage.width;
      final srcHeight = sourceImage.height;

      // 3. If image width is wider than height * 1.3 (meaning colored & B&W are side-by-side), crop only left 50%
      final bool isSideBySide = srcWidth > (srcHeight * 1.3);
      final int targetWidth = isSideBySide ? (srcWidth ~/ 2) : srcWidth;
      final int targetHeight = srcHeight;

      // 4. Extract raw RGBA pixel buffer
      final rawByteData = await sourceImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rawByteData == null) {
        transparentChefImage = sourceImage;
        return sourceImage;
      }

      final srcPixels = rawByteData.buffer.asUint8List();
      final outputPixels = Uint8List(targetWidth * targetHeight * 4);

      // 5. Convert all background pixels to full transparency (100% transparent background)
      // Detected circular emblem center & radius for left 50% logo:
      // When side-by-side: cx=264, cy=284, radius=196. Everything outside circle is background checkerboard.
      final double cx = isSideBySide ? 264.0 : (targetWidth / 2.0);
      final double cy = isSideBySide ? 284.0 : (targetHeight / 2.0);
      final double radius = isSideBySide ? 196.0 : (math.min(targetWidth, targetHeight) / 2.0);

      // Copy cropped left 50% into output buffer first
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final srcIndex = ((y * srcWidth) + x) * 4;
          final dstIndex = ((y * targetWidth) + x) * 4;
          outputPixels[dstIndex] = srcPixels[srcIndex];
          outputPixels[dstIndex + 1] = srcPixels[srcIndex + 1];
          outputPixels[dstIndex + 2] = srcPixels[srcIndex + 2];
          outputPixels[dstIndex + 3] = srcPixels[srcIndex + 3];
        }
      }

      // BFS Flood-fill from the four corners and borders to eliminate white and light-gray checkerboard pixels
      final visited = Uint8List(targetWidth * targetHeight);
      final List<int> queue = [];

      void checkAndEnqueue(int x, int y) {
        if (x < 0 || x >= targetWidth || y < 0 || y >= targetHeight) return;
        final idx = y * targetWidth + x;
        if (visited[idx] != 0) return;
        visited[idx] = 1;

        final pIdx = idx * 4;
        final r = outputPixels[pIdx];
        final g = outputPixels[pIdx + 1];
        final b = outputPixels[pIdx + 2];
        final a = outputPixels[pIdx + 3];

        final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        final bool isOutsideCircle = dist > (radius + 1.0);
        // Matches both white (255) and light-gray checkerboard squares (175-235)
        final bool isCheckerOrWhite = (r - g).abs() < 14 && (g - b).abs() < 14 && r > 175;

        if (a < 20 || isOutsideCircle || isCheckerOrWhite) {
          outputPixels[pIdx] = 0;
          outputPixels[pIdx + 1] = 0;
          outputPixels[pIdx + 2] = 0;
          outputPixels[pIdx + 3] = 0;
          queue.add(idx);
        }
      }

      // Enqueue all four border edges
      for (int x = 0; x < targetWidth; x++) {
        checkAndEnqueue(x, 0);
        checkAndEnqueue(x, targetHeight - 1);
      }
      for (int y = 0; y < targetHeight; y++) {
        checkAndEnqueue(0, y);
        checkAndEnqueue(targetWidth - 1, y);
      }

      int head = 0;
      while (head < queue.length) {
        final current = queue[head++];
        final cxPos = current % targetWidth;
        final cyPos = current ~/ targetWidth;

        checkAndEnqueue(cxPos + 1, cyPos);
        checkAndEnqueue(cxPos - 1, cyPos);
        checkAndEnqueue(cxPos, cyPos + 1);
        checkAndEnqueue(cxPos, cyPos - 1);
      }

      // Second cleanup pass: ensure any pixel outside the circular emblem is 100% transparent
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final idx = y * targetWidth + x;
          final pIdx = idx * 4;
          final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          final r = outputPixels[pIdx];
          final g = outputPixels[pIdx + 1];
          final b = outputPixels[pIdx + 2];

          if (dist > (radius + 0.5) || (dist > (radius - 3.5) && (r - g).abs() < 14 && (g - b).abs() < 14 && r > 175)) {
            outputPixels[pIdx] = 0;
            outputPixels[pIdx + 1] = 0;
            outputPixels[pIdx + 2] = 0;
            outputPixels[pIdx + 3] = 0;
          }
        }
      }

      // 6. Reconstruct clean transparent ui.Image via decodeImageFromPixels
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        outputPixels,
        targetWidth,
        targetHeight,
        ui.PixelFormat.rgba8888,
        (ui.Image result) {
          transparentChefImage = result;
          completer.complete(result);
        },
      );

      return await completer.future;
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Subtle Golden Amber and Royal Blue Aura Halo
                  Container(
                    width: s * 0.90,
                    height: s * 0.90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.goldenAmber.withAlpha(90),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: AppTheme.royalBlue.withAlpha(50),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),

                  // Mascot Image or Canvas with Transparent Render & Golden Sparkles
                  if (_decodedImage != null)
                    CustomPaint(
                      size: Size(s, s),
                      painter: _TransparentChefSparklesPainter(
                        image: _decodedImage!,
                        progress: progress,
                      ),
                    )
                  else
                    // Fallback while decoding
                    Image.asset(
                      'assets/images/chef_logo.png',
                      width: s,
                      height: s,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackLogo(s),
                    ),
                ],
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
