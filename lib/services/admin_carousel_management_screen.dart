import 'package:flutter/material.dart';
import '../models/carousel_slide.dart';
import '../services/carousel_service.dart';

class AdminCarouselManagementScreen extends StatefulWidget {
  const AdminCarouselManagementScreen({super.key});

  @override
  State<AdminCarouselManagementScreen> createState() =>
      _AdminCarouselManagementScreenState();
}

class _AdminCarouselManagementScreenState
    extends State<AdminCarouselManagementScreen> {
  final CarouselService _carouselService = CarouselService();

  void _openSlideDialog([CarouselSlide? existingSlide, int nextOrder = 0]) {
    final titleController = TextEditingController(text: existingSlide?.title);
    final subtitleController = TextEditingController(text: existingSlide?.subtitle);
    final imageController = TextEditingController(text: existingSlide?.imageUrl);
    final buttonTextController = TextEditingController(text: existingSlide?.buttonText ?? 'Shop Now');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingSlide == null ? 'Add Carousel Slide' : 'Edit Slide'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title / Headline'),
                ),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(labelText: 'Subtitle / Special Tagline'),
                ),
                TextField(
                  controller: imageController,
                  decoration: const InputDecoration(labelText: 'Image URL'),
                ),
                TextField(
                  controller: buttonTextController,
                  decoration: const InputDecoration(labelText: 'Button Label'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newSlide = CarouselSlide(
                id: existingSlide?.id ?? '',
                title: titleController.text.trim(),
                subtitle: subtitleController.text.trim(),
                imageUrl: imageController.text.trim(),
                buttonText: buttonTextController.text.trim(),
                displayOrder: existingSlide?.displayOrder ?? nextOrder,
                isActive: existingSlide?.isActive ?? true,
              );
              if (existingSlide == null) {
                await _carouselService.addSlide(newSlide);
              } else {
                await _carouselService.updateSlide(newSlide);
              }
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carousel & Banner Manager'),
        actions: [
          IconButton(
            tooltip: 'Add Slide',
            icon: const Icon(Icons.add),
            onPressed: () => _openSlideDialog(),
          ),
        ],
      ),
      body: StreamBuilder<List<CarouselSlide>>(
        stream: _carouselService.getAllSlides(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final slides = snapshot.data ?? [];
          if (slides.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.view_carousel_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No carousel slides yet'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openSlideDialog(null, 0),
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Slide'),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: slides.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              final updatedList = List<CarouselSlide>.from(slides);
              final item = updatedList.removeAt(oldIndex);
              updatedList.insert(newIndex, item);
              await _carouselService.updateSlidePositions(updatedList);
            },
            itemBuilder: (context, index) {
              final slide = slides[index];
              return Card(
                key: ValueKey(slide.id),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      slide.imageUrl,
                      width: 60,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 40,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.image, size: 20),
                      ),
                    ),
                  ),
                  title: Text(slide.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Order: ${slide.displayOrder} • ${slide.subtitle}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: slide.isActive,
                        onChanged: (val) async {
                          await _carouselService.updateSlide(slide.copyWith(isActive: val));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openSlideDialog(slide, index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          await _carouselService.deleteSlide(slide.id);
                        },
                      ),
                      const ReorderableDragStartListener(
                        index: 0,
                        child: Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}