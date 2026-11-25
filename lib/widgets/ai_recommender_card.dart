import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/localization_service.dart';
import '../models/ai_recommendation.dart';
import '../models/menu_item.dart';
import '../state/pos_state.dart';
import '../theme/app_theme.dart';

class AiRecommenderCard extends StatelessWidget {
  final AiRecommendation recommendation;
  final List<MenuItem> menuItems;

  const AiRecommenderCard({
    super.key,
    required this.recommendation,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final matchedItem = recommendation.recommendedMenuItemId != null
        ? menuItems.firstWhere(
            (m) => m.id == recommendation.recommendedMenuItemId,
            orElse: () => menuItems.first,
          )
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFFBEB), // Soft warm amber cream
            Color(0xFFEFF6FF), // Soft ice blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.blueSubtle, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalBlue.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.goldenAmber.withAlpha(120)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.goldenAmber.withAlpha(30),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              matchedItem?.iconEmoji ?? '⭐',
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.goldenAmber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tr('recommender_badge'),
                        style: const TextStyle(
                          color: AppTheme.darkNavy,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      recommendation.tag,
                      style: const TextStyle(
                        color: AppTheme.cobaltBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  recommendation.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  recommendation.description,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (matchedItem != null)
                Text(
                  currencyFormatter.format(matchedItem.price),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
              const SizedBox(height: 4),
              ElevatedButton(
                onPressed: matchedItem == null
                    ? null
                    : () {
                        PosState().addToCart(matchedItem);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.royalBlue,
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              'Added ${matchedItem.name} to Cart!',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.goldenAmber,
                  foregroundColor: AppTheme.darkNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  minimumSize: const Size(0, 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  tr('add_to_cart'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkNavy,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
