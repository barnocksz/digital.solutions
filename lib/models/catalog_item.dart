enum CatalogType { hardware, softwareService, digitalSolution }

class CatalogItem {
  final String id;
  final String title;
  final String description;
  final double basePrice;
  final double costPrice;
  final int stockQuantity;
  final CatalogType type;
  final Map<String, dynamic> specifications;
  final bool isCustomizable;

  CatalogItem({
    required this.id,
    required this.title,
    required this.description,
    required this.basePrice,
    this.costPrice = 0.0,
    this.stockQuantity = 0,
    required this.type,
    this.specifications = const {},
    this.isCustomizable = false,
  });

  factory CatalogItem.fromFirestore(Map<String, dynamic> data, String id) {
    return CatalogItem(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      basePrice: (data['basePrice'] as num?)?.toDouble() ?? 0.0,
      costPrice: (data['costPrice'] as num?)?.toDouble() ?? 0.0,
      stockQuantity: (data['stockQuantity'] as num?)?.toInt() ?? 0,
      type: CatalogType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => CatalogType.hardware,
      ),
      specifications: Map<String, dynamic>.from(data['specifications'] as Map? ?? {}),
      isCustomizable: data['isCustomizable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'description': description,
    'basePrice': basePrice,
    'costPrice': costPrice,
    'stockQuantity': stockQuantity,
    'type': type.name,
    'specifications': specifications,
    'isCustomizable': isCustomizable,
  };
}