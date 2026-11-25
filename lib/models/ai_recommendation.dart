class AiRecommendation {
  final String title;
  final String description;
  final String? recommendedMenuItemId;
  final String reason;
  final double discountPercent;
  final double? bundlePrice;
  final List<String> itemsIncluded;
  final String tag;

  const AiRecommendation({
    required this.title,
    required this.description,
    this.recommendedMenuItemId,
    required this.reason,
    this.discountPercent = 0.0,
    this.bundlePrice,
    this.itemsIncluded = const [],
    this.tag = 'Bestseller',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'recommendedMenuItemId': recommendedMenuItemId,
      'reason': reason,
      'discountPercent': discountPercent,
      'bundlePrice': bundlePrice,
      'itemsIncluded': itemsIncluded,
      'tag': tag,
    };
  }

  factory AiRecommendation.fromMap(Map<String, dynamic> map) {
    return AiRecommendation(
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      recommendedMenuItemId: map['recommendedMenuItemId'],
      reason: map['reason'] ?? '',
      discountPercent: (map['discountPercent'] as num?)?.toDouble() ?? 0.0,
      bundlePrice: (map['bundlePrice'] as num?)?.toDouble(),
      itemsIncluded: (map['itemsIncluded'] as List?)?.map((e) => e.toString()).toList() ?? [],
      tag: map['tag'] ?? 'AI Special',
    );
  }
}
