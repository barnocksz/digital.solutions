class Quote {
  final String id;
  final String customerId;
  final String customerEmail;
  final String projectScope;
  final double estimatedCost;
  final String status;
  final DateTime createdAt;
  final String? paymentTxHash;
  final String? paymentCurrency;
  final String? verificationStatus;
  final bool stockDecremented;
  final String? depositAddress;
  final int? addressIndex;

  Quote({
    required this.id,
    required this.customerId,
    required this.customerEmail,
    required this.projectScope,
    required this.estimatedCost,
    required this.status,
    required this.createdAt,
    this.paymentTxHash,
    this.paymentCurrency,
    this.verificationStatus,
    this.stockDecremented = false,
    this.depositAddress,
    this.addressIndex,
  });

  factory Quote.fromFirestore(Map<String, dynamic> data, String id) {
    return Quote(
      id: id,
      customerId: data['customerId'] as String? ?? '',
      customerEmail: data['customerEmail'] as String? ?? '',
      projectScope: data['projectScope'] as String? ?? '',
      estimatedCost: (data['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] as String? ?? 'pending',
      createdAt: (data['createdAt'] != null)
          ? DateTime.tryParse(data['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentTxHash: data['paymentTxHash'] as String?,
      paymentCurrency: data['paymentCurrency'] as String?,
      verificationStatus: data['verificationStatus'] as String?,
      stockDecremented: data['stockDecremented'] as bool? ?? false,
      depositAddress: data['depositAddress'] as String?,
      addressIndex: (data['addressIndex'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'customerId': customerId,
    'customerEmail': customerEmail,
    'projectScope': projectScope,
    'estimatedCost': estimatedCost,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'paymentTxHash': paymentTxHash,
    'paymentCurrency': paymentCurrency,
    'verificationStatus': verificationStatus,
    'stockDecremented': stockDecremented,
    'depositAddress': depositAddress,
    'addressIndex': addressIndex,
  };
}