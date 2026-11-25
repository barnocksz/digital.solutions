import 'package:flutter/material.dart';
import '../models/carousel_slide.dart';
import '../services/carousel_service.dart';
import '../widgets/storefront_carousel.dart';

class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({super.key});

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  final CarouselService _carouselService = CarouselService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _catalogSectionKey = GlobalKey();
  String _selectedCategory = 'All';

  void _scrollToCatalog() {
    final context = _catalogSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Modern Web Navigation Bar
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 1,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 32,
            title: Row(
              children: [
                Image.asset(
                  'assets/images/barnock_logo_brown.png',
                  height: 38,
                  errorBuilder: (_, __, ___) => const Text(
                    'BARNOCK',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.brown,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
                _buildNavLink('Home', isSelected: true),
                _buildNavLink('Products', onTap: _scrollToCatalog),
                _buildNavLink('Services', onTap: _scrollToCatalog),
                _buildNavLink('Specials', onTap: _scrollToCatalog),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.black87),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined, color: Colors.black87),
                onPressed: () {},
              ),
              Padding(
                padding: const EdgeInsets.only(right: 32, left: 8),
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Account'),
                ),
              ),
            ],
          ),

          // Hero Carousel Section
          SliverToBoxAdapter(
            child: StreamBuilder<List<CarouselSlide>>(
              stream: _carouselService.getActiveSlides(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 420,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final slides = snapshot.data ?? [];
                if (slides.isEmpty) {
                  return const SizedBox.shrink();
                }
                return StorefrontCarousel(
                  slides: slides,
                  onCtaPressed: _scrollToCatalog,
                );
              },
            ),
          ),

          // Seamless Intro Flow Banner
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              color: Colors.brown.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFeatureBadge(Icons.memory_outlined, 'Programming Hardware', 'High-reliability tools'),
                  _buildFeatureBadge(Icons.code_outlined, 'Tailor-Made Software', 'Bespoke engineered solutions'),
                  _buildFeatureBadge(Icons.support_agent_outlined, 'Technical Support', 'Direct engineer consultations'),
                ],
              ),
            ),
          ),

          // Products and Services Catalog Section
          SliverToBoxAdapter(
            child: Padding(
              key: _catalogSectionKey,
              padding: const EdgeInsets.fromLTRB(48, 48, 48, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Programming Hardware & Software Services',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse our programming hardware products and tailor-made software services.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    children: ['All', 'Hardware Programmers', 'Embedded Tools', 'Tailor-Made Software', 'Custom Solutions']
                        .map((cat) => ChoiceChip(
                              label: Text(cat),
                              selected: _selectedCategory == cat,
                              onSelected: (_) => setState(() => _selectedCategory = cat),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

          // Products Grid Flow
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Barnock Product #${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('\$${(index + 1) * 25}.00',
                                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
                childCount: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(String title, {bool isSelected = false, VoidCallback? onTap}) {
    return TextButton(
      onPressed: onTap ?? () {},
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.brown : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: Colors.brown, size: 28),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}