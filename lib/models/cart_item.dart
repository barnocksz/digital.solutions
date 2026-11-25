import 'catalog_item.dart';

class CartItem {
  final CatalogItem item;
  int quantity;

  CartItem({
    required this.item,
    this.quantity = 1,
  });

  double get totalPrice => item.basePrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'item': {
        'id': item.id,
        ...item.toFirestore(),
      },
      'quantity': quantity,
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    final itemData = Map<String, dynamic>.from(map['item'] as Map);
    return CartItem(
      item: CatalogItem.fromFirestore(itemData, itemData['id'] as String? ?? ''),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}