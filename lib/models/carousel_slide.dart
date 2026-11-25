class CarouselSlide {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? buttonText;
  final String? targetSection;
  final int displayOrder;
  final bool isActive;

  const CarouselSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.buttonText,
    this.targetSection,
    required this.displayOrder,
    this.isActive = true,
  });

  factory CarouselSlide.fromFirestore(Map<String, dynamic> data, String documentId) {
    return CarouselSlide(
      id: documentId,
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      buttonText: data['buttonText'] as String?,
      targetSection: data['targetSection'] as String?,
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'buttonText': buttonText,
      'targetSection': targetSection,
      'displayOrder': displayOrder,
      'isActive': isActive,
    };
  }

  CarouselSlide copyWith({
    int? displayOrder,
    bool? isActive,
  }) {
    return CarouselSlide(
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      buttonText: buttonText,
      targetSection: targetSection,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}