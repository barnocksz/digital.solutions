import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/carousel_slide.dart';
import '../models/catalog_item.dart';
import '../models/quote.dart';
import '../services/cart_service.dart';
import '../services/carousel_service.dart';
import '../services/currency_service.dart';
import '../widgets/cart_drawer.dart';
import '../widgets/storefront_carousel.dart';

class CustomerStorefrontView extends StatefulWidget {
  const CustomerStorefrontView({super.key});

  @override
  State<CustomerStorefrontView> createState() => _CustomerStorefrontViewState();
}

class _CustomerStorefrontViewState extends State<CustomerStorefrontView> {
  final CarouselService _carouselService = CarouselService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _catalogSectionKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CatalogType? _selectedFilter;

  void _addToCart(BuildContext context, CatalogItem item) {
    try {
      context.read<CartService>().addItem(item);
    } catch (_) {
      // Provider pending hot-restart
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} added to cart'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'View Cart',
          textColor: Colors.white,
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ),
    );
  }

  void _scrollToCatalog() {
    final targetContext = _catalogSectionKey.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
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
    CartService? cart;
    try {
      cart = context.watch<CartService>();
    } catch (_) {
      cart = null;
    }
    final cartCount = cart?.totalCount ?? 0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;
    CurrencyService? currencyService;
    try { currencyService = context.watch<CurrencyService>(); } catch (_) {}
    const navBarBg = Color(0xFF574325); // Rich grey dark brown

    final query = _selectedFilter == null
        ? FirebaseFirestore.instance.collection('catalog')
        : FirebaseFirestore.instance
            .collection('catalog')
            .where('type', isEqualTo: _selectedFilter!.name);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF9FAFB),
      endDrawer: CartDrawer(
        onProceedToQuote: (summary) => _openQuoteModal(context, initialScope: summary),
      ),
      drawer: isMobile
          ? Drawer(
              backgroundColor: const Color(0xFF2B231E),
              child: SafeArea(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SizedBox(
                        height: 48,
                        child: Image.asset(
                          'assets/images/barnock_full_logo_grey.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Text(
                            'BARNOCK',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    ListTile(
                      leading: const Icon(Icons.home_outlined, color: Colors.white),
                      title: const Text('Home', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined, color: Colors.white70),
                      title: const Text('Products & Services', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToCatalog();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.request_quote_outlined, color: Colors.white70),
                      title: const Text('Request Quote', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                        Navigator.pop(context);
                        _openQuoteModal(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined, color: Colors.white70),
                      title: const Text('My Orders', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/orders');
                      },
                    ),
                    ListTile(
                      leading: Badge.count(
                        count: cartCount,
                        isLabelVisible: cartCount > 0,
                        backgroundColor: const Color(0xFF8D8D8F),
                        textColor: Colors.white,
                        child: const Icon(Icons.shopping_cart_outlined, color: Colors.white70),
                      ),
                      title: const Text('Cart', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                        Navigator.pop(context);
                        _scaffoldKey.currentState?.openEndDrawer();
                      },
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    if (currencyService != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Currency:', style: TextStyle(color: Colors.white70)),
                            DropdownButton<AppCurrency>(
                              value: currencyService.currentCurrency,
                              dropdownColor: const Color(0xFF2B231E),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              underline: const SizedBox.shrink(),
                              items: AppCurrency.values.map((c) => DropdownMenuItem(
                                value: c,
                                child: Text('${c.code} (${c.symbol})'),
                              )).toList(),
                              onChanged: (c) => c != null ? currencyService!.setCurrency(c) : null,
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white70),
                      title: const Text('Admin Portal', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/admin');
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Sticky Modern Web Navbar
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: navBarBg,
            elevation: 2,
            surfaceTintColor: Colors.transparent,
            titleSpacing: isMobile ? 16 : 24,
            title: Row(
              children: [
                SizedBox(
                  height: isMobile ? 44 : 50,
                  child: Image.asset(
                    'assets/images/barnock_full_logo_grey.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.memory, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'BARNOCK',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 32),
                  _buildNavLink('Home', isSelected: true, onTap: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                    );
                  }),
                  _buildNavLink('Products & Services', onTap: _scrollToCatalog),
                  _buildNavLink('Request Quote', onTap: () => _openQuoteModal(context)),
                  _buildNavLink('My Orders', onTap: () => Navigator.pushNamed(context, '/orders')),
                ],
              ],
            ),
            actions: [
              if (!isMobile) ...[
                if (currencyService != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AppCurrency>(
                        value: currencyService.currentCurrency,
                        dropdownColor: navBarBg,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        items: AppCurrency.values.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.code} (${c.symbol})'),
                        )).toList(),
                        onChanged: (c) => c != null ? currencyService!.setCurrency(c) : null,
                      ),
                    ),
                  ),
                Badge.count(
                  count: cartCount,
                  isLabelVisible: cartCount > 0,
                  backgroundColor: const Color(0xFF8D8D8F),
                  textColor: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                    tooltip: 'Shopping Cart',
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.request_quote_outlined, color: Colors.white),
                  tooltip: 'Request Custom Quote',
                  onPressed: () => _openQuoteModal(context),
                ),
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
                  tooltip: 'Admin Portal',
                  onPressed: () => Navigator.pushNamed(context, '/admin'),
                ),
                const SizedBox(width: 16),
              ] else ...[
                Badge.count(
                  count: cartCount,
                  isLabelVisible: cartCount > 0,
                  backgroundColor: const Color(0xFF8D8D8F),
                  textColor: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                    tooltip: 'Shopping Cart',
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.request_quote_outlined, color: Colors.white),
                  tooltip: 'Request Custom Quote',
                  onPressed: () => _openQuoteModal(context),
                ),
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  tooltip: 'Navigation Menu',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),

          // Hero Promotional Carousel Section
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

          // Feature Highlights Intro Banner
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: isMobile ? 16 : 32),
              color: const Color(0xFF574325).withOpacity(0.06),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                runSpacing: 16,
                spacing: 24,
                children: [
                  _buildFeatureHighlight(
                    Icons.memory_outlined,
                    'Programming Hardware',
                    'Dedicated hardware programmers, debuggers, and production tooling',
                  ),
                  _buildFeatureHighlight(
                    Icons.code_outlined,
                    'Tailor-Made Software',
                    'Custom firmware, bespoke software, and API integrations',
                  ),
                  _buildFeatureHighlight(
                    Icons.handshake_outlined,
                    'Turnkey Solutions',
                    'Customized hardware and software tailored to your specifications',
                  ),
                ],
              ),
            ),
          ),

          // Products and Services Catalog Header & Category Filters
          SliverToBoxAdapter(
            child: Padding(
              key: _catalogSectionKey,
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 24 : 40, isMobile ? 16 : 32, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hardware Products & Software Services',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Explore our programming hardware products and tailor-made software services.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All Offerings'),
                          selected: _selectedFilter == null,
                          selectedColor: const Color(0xFF574325).withOpacity(0.18),
                          checkmarkColor: const Color(0xFF574325),
                          onSelected: (_) => setState(() => _selectedFilter = null),
                        ),
                        const SizedBox(width: 8),
                        ...CatalogType.values.map((type) {
                          final label = switch (type) {
                            CatalogType.hardware => 'Programming Hardware',
                            CatalogType.softwareService => 'Tailor-Made Software',
                            CatalogType.digitalSolution => 'Digital Solutions',
                          };
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(label),
                              selected: _selectedFilter == type,
                              selectedColor: const Color(0xFF574325).withOpacity(0.18),
                              checkmarkColor: const Color(0xFF574325),
                              onSelected: (selected) {
                                setState(() => _selectedFilter = selected ? type : null);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Product Grid Flow
          StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(child: Text('No hardware products or software services found.')),
                  ),
                );
              }

              final items = snapshot.data!.docs
                  .map((doc) => CatalogItem.fromFirestore(
                        doc.data() as Map<String, dynamic>,
                        doc.id,
                      ))
                  .toList();

              return SliverPadding(
                padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, 8, isMobile ? 16 : 32, 48),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _CatalogCard(
                      item: items[index],
                      onAddToCart: () => _addToCart(context, items[index]),
                    ),
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(String title, {bool isSelected = false, VoidCallback? onTap}) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildFeatureHighlight(IconData icon, String title, String subtitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF574325).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF574325), size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
  void _openQuoteModal(BuildContext context, {String? initialScope}) {
    final scopeController = TextEditingController(text: initialScope);
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Custom Solution / Quote'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Work Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scopeController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Project Scope / Hardware & Software Requirements',
                  hintText: 'e.g. Dedicated programming hardware tools or tailor-made software specifications',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.isNotEmpty && scopeController.text.isNotEmpty) {
                final scopeText = scopeController.text.trim();
                final addressMatch = RegExp(r'Deposit Address:\s*([^\n]+)').firstMatch(scopeText);
                final indexMatch = RegExp(r'Address Index:\s*#?(\d+)').firstMatch(scopeText);
                final currencyMatch = RegExp(r'Settlement Currency:\s*([^\n]+)').firstMatch(scopeText);

                final newQuote = Quote(
                  id: '',
                  customerId: 'guest_or_current_user',
                  customerEmail: emailController.text.trim(),
                  projectScope: scopeText,
                  estimatedCost: 0.0,
                  status: 'pending',
                  createdAt: DateTime.now(),
                  paymentCurrency: currencyMatch?.group(1)?.trim(),
                  depositAddress: addressMatch?.group(1)?.trim(),
                  addressIndex: indexMatch != null ? int.tryParse(indexMatch.group(1)!) : null,
                );
                await FirebaseFirestore.instance.collection('quotes').add(newQuote.toFirestore());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    ).then((_) {
      scopeController.dispose();
      emailController.dispose();
    });
  }
}

class _CatalogCard extends StatefulWidget {
  final CatalogItem item;
  final VoidCallback onAddToCart;
  const _CatalogCard({required this.item, required this.onAddToCart});

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> {
  int _selectedTabIndex = 0;

  List<String> _parseSpecList(dynamic value, List<String> fallback) {
    if (value is List) {
      final list = value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    } else if (value is String && value.trim().isNotEmpty) {
      final list = value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isHardware = item.type == CatalogType.hardware;

    final protocols = _parseSpecList(
      item.specifications['protocols'] ?? item.specifications['supported_protocols'],
      isHardware ? const ['SWD', 'JTAG', 'UART', 'SPI', 'I2C'] : const [],
    );

    final mcus = _parseSpecList(
      item.specifications['target_mcus'] ?? item.specifications['microcontrollers'] ?? item.specifications['mcus'],
      isHardware ? const ['STM32', 'ESP32', 'nRF52', 'RP2040', 'ARM Cortex-M'] : const [],
    );

    final tabs = isHardware
        ? ['Overview', 'Protocols (${protocols.length})', 'Target MCUs (${mcus.length})']
        : ['Overview'];

    final activeIndex = _selectedTabIndex.clamp(0, tabs.length - 1);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF8D8D8F), width: 0.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(
                    switch (item.type) {
                      CatalogType.hardware => 'Programming Hardware',
                      CatalogType.softwareService => 'Tailor-Made Software',
                      CatalogType.digitalSolution => 'Digital Solution',
                    },
                    style: const TextStyle(fontSize: 10, color: Color(0xFF574325)),
                  ),
                  backgroundColor: const Color(0xFF8D8D8F).withOpacity(0.15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isHardware) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(tabs.length, (idx) {
                    final isSelected = activeIndex == idx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          tabs[idx],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFF574325),
                        backgroundColor: Colors.grey.shade100,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) => setState(() => _selectedTabIndex = idx),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: activeIndex == 1
                  ? _buildProtocolsView(protocols)
                  : activeIndex == 2
                      ? _buildMcusView(mcus)
                      : _buildOverviewView(item),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Builder(builder: (ctx) {
                  final currService = ctx.watch<CurrencyService>();
                  return Text(
                    currService.format(item.basePrice),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF574325),
                    fontWeight: FontWeight.bold,
                  ),
                  );
                }),
                ElevatedButton(
                  onPressed: widget.onAddToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF574325),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Order / Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewView(CatalogItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
        if (item.isCustomizable) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.tune, size: 14, color: Colors.brown.shade600),
              const SizedBox(width: 4),
              Text(
                'Custom hardware specs available on request',
                style: TextStyle(fontSize: 11, color: Colors.brown.shade700, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildProtocolsView(List<String> protocols) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: protocols
            .map(
              (proto) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF574325).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF574325).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cable, size: 12, color: Color(0xFF574325)),
                    const SizedBox(width: 4),
                    Text(
                      proto,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF574325),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildMcusView(List<String> mcus) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: mcus
            .map(
              (mcu) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.memory, size: 12, color: Colors.black87),
                    const SizedBox(width: 4),
                    Text(
                      mcu,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}