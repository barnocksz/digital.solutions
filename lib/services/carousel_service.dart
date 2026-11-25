import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/carousel_slide.dart';

class CarouselService {
  final CollectionReference _carouselRef =
      FirebaseFirestore.instance.collection('promotional_banners');

  static const List<CarouselSlide> _defaultSlides = [
    CarouselSlide(
      id: 'default_1',
      title: 'Programming Hardware Products',
      subtitle: 'Engineered hardware programmers, debuggers, and production flashing tools built for reliability.',
      imageUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1600&q=80',
      buttonText: 'Explore Hardware',
      displayOrder: 0,
      isActive: true,
    ),
    CarouselSlide(
      id: 'default_2',
      title: 'Tailor-Made Software Services',
      subtitle: 'Custom firmware, enterprise toolchains, and bespoke software built to your exact specifications.',
      imageUrl: 'https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=1600&q=80',
      buttonText: 'Request Software Quote',
      displayOrder: 1,
      isActive: true,
    ),
  ];

  /// Real-time stream of active slides ordered by display order (safe against missing Firestore composite indexes)
  Stream<List<CarouselSlide>> getActiveSlides() {
    return _carouselRef.snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return _defaultSlides;
      }
      final slides = snapshot.docs
          .map((doc) => CarouselSlide.fromFirestore(
              doc.data() as Map<String, dynamic>, doc.id))
          .where((s) => s.isActive)
          .toList();
      slides.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return slides.isEmpty ? _defaultSlides : slides;
    });
  }

  /// Real-time stream of all slides for admin management
  Stream<List<CarouselSlide>> getAllSlides() {
    return _carouselRef.snapshots().map((snapshot) {
      final slides = snapshot.docs
          .map((doc) => CarouselSlide.fromFirestore(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      slides.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return slides;
    });
  }

  Future<void> addSlide(CarouselSlide slide) async {
    await _carouselRef.add(slide.toMap());
  }

  Future<void> updateSlide(CarouselSlide slide) async {
    await _carouselRef.doc(slide.id).update(slide.toMap());
  }

  Future<void> deleteSlide(String slideId) async {
    await _carouselRef.doc(slideId).delete();
  }

  /// Atomically updates positions for all reordered slides
  Future<void> updateSlidePositions(List<CarouselSlide> reorderedSlides) async {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < reorderedSlides.length; i++) {
      final docRef = _carouselRef.doc(reorderedSlides[i].id);
      batch.update(docRef, {'displayOrder': i});
    }
    await batch.commit();
  }
}