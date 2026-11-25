import 'dart:math' as math;
import 'package:flutter/material.dart';

class QrisPainter extends CustomPainter {
  final String data;
  final Color color;

  QrisPainter({
    required this.data,
    this.color = const Color(0xFF0F172A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const int matrixSize = 25; // 25x25 grid
    final double cellSize = size.width / matrixSize;

    // Deterministic pseudo-random seed from input string
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = (hash * 31 + data.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final rnd = math.Random(hash);

    // Matrix representation: true = black module
    final List<List<bool>> grid = List.generate(
      matrixSize,
      (_) => List.generate(matrixSize, (_) => false),
    );

    // 1. Draw 3 Corner Position Detection Patterns (7x7)
    _drawFinderPattern(grid, 0, 0);
    _drawFinderPattern(grid, matrixSize - 7, 0);
    _drawFinderPattern(grid, 0, matrixSize - 7);

    // 2. Alignment pattern (5x5) at (matrixSize - 9, matrixSize - 9)
    _drawAlignmentPattern(grid, matrixSize - 9, matrixSize - 9);

    // 3. Timing patterns
    for (int i = 8; i < matrixSize - 8; i++) {
      grid[6][i] = (i % 2 == 0);
      grid[i][6] = (i % 2 == 0);
    }

    // 4. Fill data areas with deterministic pattern
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Skip finder zones
        if ((r < 8 && c < 8) ||
            (r < 8 && c >= matrixSize - 8) ||
            (r >= matrixSize - 8 && c < 8)) {
          continue;
        }
        // Skip alignment zone
        if (r >= matrixSize - 9 &&
            r <= matrixSize - 5 &&
            c >= matrixSize - 9 &&
            c <= matrixSize - 5) {
          continue;
        }
        // Skip center logo zone (9x9 in center)
        final centerStart = (matrixSize ~/ 2) - 2;
        final centerEnd = (matrixSize ~/ 2) + 2;
        if (r >= centerStart && r <= centerEnd && c >= centerStart && c <= centerEnd) {
          continue;
        }

        grid[r][c] = rnd.nextBool();
      }
    }

    // Draw the modules onto canvas
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (grid[r][c]) {
          final rect = Rect.fromLTWH(
            c * cellSize,
            r * cellSize,
            cellSize,
            cellSize,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.15)),
            paint,
          );
        }
      }
    }
  }

  void _drawFinderPattern(List<List<bool>> grid, int startX, int startY) {
    for (int r = 0; r < 7; r++) {
      for (int c = 0; c < 7; c++) {
        final isBorder = (r == 0 || r == 6 || c == 0 || c == 6);
        final isCenter = (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        grid[startY + r][startX + c] = isBorder || isCenter;
      }
    }
  }

  void _drawAlignmentPattern(List<List<bool>> grid, int startX, int startY) {
    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 5; c++) {
        final isBorder = (r == 0 || r == 4 || c == 0 || c == 4);
        final isCenter = (r == 2 && c == 2);
        grid[startY + r][startX + c] = isBorder || isCenter;
      }
    }
  }

  @override
  bool shouldRepaint(covariant QrisPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
