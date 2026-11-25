import 'package:cloud_firestore/cloud_firestore.dart';

class PromoCode {
  final String id;
  final String code;
  final double discountPercentage;
  final double minOrderValue;
  final bool isActive;
  final DateTime? expiresAt;

  PromoCode({
    required this.id,
    required this.code,
    required this.discountPercentage,
    this.minOrderValue = 0.0,
    this.isActive = true,
    this.expiresAt,
  });

  factory PromoCode.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime? expiry;
    if (data['expiresAt'] is Timestamp) {
      expiry = (data['expiresAt'] as Timestamp).toDate();
    } else if (data['expiresAt'] is String) {
      expiry = DateTime.tryParse(data['expiresAt'] as String);
    }

    return PromoCode(
      id: id,
      code: (data['code'] as String? ?? id).toUpperCase(),
      discountPercentage: (data['discountPercentage'] as num?)?.toDouble() ?? 0.0,
      minOrderValue: (data['minOrderValue'] as num?)?.toDouble() ?? 0.0,
      isActive: data['isActive'] as bool? ?? true,
      expiresAt: expiry,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'discountPercentage': discountPercentage,
        'minOrderValue': minOrderValue,
        'isActive': isActive,
        'expiresAt': expiresAt?.toIso8601String(),
      };
}