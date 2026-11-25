import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/catalog_item.dart';
import '../models/promo_code.dart';

class CartService extends ChangeNotifier {
  static const String _storageKey = 'barnock_cart_items';
  final Map<String, CartItem> _items = {};
  PromoCode? _appliedPromo;
  bool _isInitialized = false;

  CartService() {
    _loadFromStorage();
  }

  List<CartItem> get items => _items.values.toList();

  int get totalCount =>
      _items.values.fold(0, (sum, cartItem) => sum + cartItem.quantity);

  double get subtotal =>
      _items.values.fold(0.0, (sum, cartItem) => sum + cartItem.totalPrice);

  String? get appliedPromoCode => _appliedPromo?.code;

  double get discountPercentage => _appliedPromo?.discountPercentage ?? 0.0;

  double get minOrderValue => _appliedPromo?.minOrderValue ?? 0.0;

  bool get isMinOrderMet =>
      _appliedPromo == null || subtotal >= _appliedPromo!.minOrderValue;

  double get discountAmount {
    if (_appliedPromo == null || !isMinOrderMet) return 0.0;
    return subtotal * _appliedPromo!.discountPercentage;
  }

  double get total => (subtotal - discountAmount).clamp(0.0, double.infinity);

  bool get isEmpty => _items.isEmpty;

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
        _items.clear();
        for (final entry in decoded) {
          final cartItem = CartItem.fromMap(Map<String, dynamic>.from(entry as Map));
          _items[cartItem.item.id] = cartItem;
        }
      }
      final savedPromoJson = prefs.getString('${_storageKey}_promo_data');
      if (savedPromoJson != null && savedPromoJson.isNotEmpty) {
        final decodedPromo = jsonDecode(savedPromoJson) as Map<String, dynamic>;
        _appliedPromo = PromoCode.fromFirestore(
          decodedPromo,
          decodedPromo['code'] as String? ?? '',
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error restoring cart from localStorage: $e');
    } finally {
      _isInitialized = true;
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.values.map((item) => item.toMap()).toList());
      await prefs.setString(_storageKey, encoded);
      if (_appliedPromo != null) {
        await prefs.setString(
          '${_storageKey}_promo_data',
          jsonEncode(_appliedPromo!.toMap()),
        );
      } else {
        await prefs.remove('${_storageKey}_promo_data');
      }
    } catch (e) {
      debugPrint('Error persisting cart to localStorage: $e');
    }
  }

  Future<String?> applyPromoCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      return 'Please enter a promo code';
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final query = await firestore
          .collection('promo_codes')
          .where('code', isEqualTo: normalized)
          .limit(1)
          .get();

      DocumentSnapshot doc;
      if (query.docs.isNotEmpty) {
        doc = query.docs.first;
      } else {
        doc = await firestore.collection('promo_codes').doc(normalized).get();
      }

      if (!doc.exists || doc.data() == null) {
        return 'Invalid promo code';
      }

      final promo = PromoCode.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      if (!promo.isActive) {
        return 'This promo code is no longer active';
      }

      if (promo.expiresAt != null && promo.expiresAt!.isBefore(DateTime.now())) {
        return 'This promo code has expired';
      }

      if (subtotal < promo.minOrderValue) {
        final diff = (promo.minOrderValue - subtotal).toStringAsFixed(2);
        return 'Add \$$diff more to use this code (Min order \$${promo.minOrderValue.toStringAsFixed(2)})';
      }

      _appliedPromo = promo;
      notifyListeners();
      await _saveToStorage();
      return null;
    } catch (e) {
      debugPrint('Error validating promo code: $e');
      return 'Failed to validate promo code. Please try again.';
    }
  }

  void removePromoCode() {
    _appliedPromo = null;
    notifyListeners();
    _saveToStorage();
  }

  void addItem(CatalogItem catalogItem) {
    if (_items.containsKey(catalogItem.id)) {
      _items[catalogItem.id]!.quantity += 1;
    } else {
      _items[catalogItem.id] = CartItem(item: catalogItem, quantity: 1);
    }
    notifyListeners();
    _saveToStorage();
  }

  void incrementQuantity(String itemId) {
    if (_items.containsKey(itemId)) {
      _items[itemId]!.quantity += 1;
      notifyListeners();
      _saveToStorage();
    }
  }

  void decrementQuantity(String itemId) {
    if (!_items.containsKey(itemId)) return;
    if (_items[itemId]!.quantity > 1) {
      _items[itemId]!.quantity -= 1;
    } else {
      _items.remove(itemId);
    }
    notifyListeners();
    _saveToStorage();
  }

  CartItem? removeItem(String itemId) {
    final removed = _items.remove(itemId);
    if (removed != null) {
      notifyListeners();
      _saveToStorage();
    }
    return removed;
  }

  void restoreItem(CartItem cartItem) {
    _items[cartItem.item.id] = cartItem;
    notifyListeners();
    _saveToStorage();
  }

  void clearCart() {
    _items.clear();
    _appliedPromo = null;
    notifyListeners();
    _saveToStorage();
  }
}