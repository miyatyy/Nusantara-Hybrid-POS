import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MenuImageBanner extends StatelessWidget {
  final String imageUrl;
  final String category;
  final String iconEmoji;
  final double height;
  final double? width;
  final double aspectRatio;
  final BorderRadiusGeometry? borderRadius;
  final bool isSoldOut;

  const MenuImageBanner({
    super.key,
    required this.imageUrl,
    required this.category,
    required this.iconEmoji,
    this.height = 130,
    this.width,
    this.aspectRatio = 4 / 3,
    this.borderRadius,
    this.isSoldOut = false,
  });

  // Grayscale matrix for sold-out food photography
  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ??
        const BorderRadius.vertical(top: Radius.circular(15));

    Widget imageContent;

    if (imageUrl.isEmpty) {
      imageContent = _buildOfflineFallback(effectiveBorderRadius);
    } else {
      imageContent = ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Image.network(
          imageUrl,
          height: height,
          width: width ?? double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            final totalBytes = loadingProgress.expectedTotalBytes;
            final downloadedBytes = loadingProgress.cumulativeBytesLoaded;
            final progress = totalBytes != null ? downloadedBytes / totalBytes : null;

            return Container(
              height: height,
              width: width ?? double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.blueSubtle.withAlpha(120),
                    AppTheme.yellowSubtle.withAlpha(120),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.2,
                    color: AppTheme.cobaltBlue,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildOfflineFallback(effectiveBorderRadius);
          },
        ),
      );
    }

    final isCompact = height < 75 || (width != null && width! < 80);

    if (isSoldOut) {
      return Stack(
        children: [
          ColorFiltered(
            colorFilter: _grayscaleFilter,
            child: imageContent,
          ),
          // Dark semi-transparent overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: effectiveBorderRadius,
                color: Colors.black.withAlpha(85),
              ),
            ),
          ),
          // Prominent SOLD OUT / HABIS badge overlay
          Positioned.fill(
            child: Center(
              child: isCompact
                  ? Icon(
                      Icons.block_rounded,
                      size: (height * 0.42).clamp(14.0, 22.0),
                      color: Colors.white,
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.roseRed,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(90),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block_rounded,
                                size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'SOLD OUT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      );
    }

    return imageContent;
  }

  Widget _buildOfflineFallback(BorderRadiusGeometry radius) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E3A8A), // Deep Royal Blue
            Color(0xFF2563EB), // Electric Cobalt
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: (height < 75 || (width != null && width! < 80))
          ? Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  iconEmoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            )
          : Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: Opacity(
                    opacity: 0.15,
                    child: Text(
                      iconEmoji,
                      style: const TextStyle(fontSize: 70),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        iconEmoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(40),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.brightYellow,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
