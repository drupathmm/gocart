import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../models/product_category.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/gocart_footer.dart';
import '../widgets/product_cart_quantity_badge.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'profile_screen.dart';
import 'user_notifications_screen.dart';

class UserHomeScreen extends ConsumerStatefulWidget {
  const UserHomeScreen({super.key});

  @override
  ConsumerState<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends ConsumerState<UserHomeScreen> {
  int currentIndex = 0;

  final TextEditingController searchController = TextEditingController();

  Timer? searchTimer;

  @override
  void dispose() {
    searchTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void searchProducts(String value) {
    searchTimer?.cancel();
    ref.read(productsProvider.notifier).cancelPendingRequests();

    searchTimer = Timer(const Duration(milliseconds: 300), () {
      final query = value.trim();

      if (query.isEmpty) {
        ref.read(productsProvider.notifier).refreshProducts();
        return;
      }

      ref.read(productsProvider.notifier).search(query);
    });
  }

  void clearSearch() {
    searchController.clear();

    ref.read(productsProvider.notifier).refreshProducts();

    setState(() {});
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void changePage(int index) {
    setState(() {
      currentIndex = index;
    });

    if (index != 0) {
      clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _UserProductsPage(),
      const CartScreen(),
      ProfileScreen(onBuyerBack: () => changePage(0)),
    ];

    return Scaffold(
      backgroundColor: GoCartTheme.canvas,

      // ==========================================================
      // TOP NAVIGATION
      // ==========================================================
      appBar: AppBar(
        backgroundColor: GoCartTheme.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    // ==================================================
                    // LOGO
                    // ==================================================
                    const _GoCartLogo(),

                    const SizedBox(width: 28),

                    // ==================================================
                    // SEARCH
                    // ==================================================
                    if (constraints.maxWidth >= 600)
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: _SearchBar(
                              controller: searchController,
                              onChanged: searchProducts,
                              onClear: clearSearch,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),

                    const SizedBox(width: 24),

                    // ==================================================
                    // NAVIGATION
                    // ==================================================
                    if (constraints.maxWidth >= 850)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TopNavItem(
                            icon: Icons.home_outlined,
                            selectedIcon: Icons.home_rounded,
                            label: 'Home',
                            selected: currentIndex == 0,
                            onTap: () {
                              changePage(0);
                            },
                          ),
                          const SizedBox(width: 6),
                          _TopNavItem(
                            icon: Icons.shopping_cart_outlined,
                            selectedIcon: Icons.shopping_cart_rounded,
                            label: 'Cart',
                            selected: currentIndex == 1,
                            onTap: () {
                              changePage(1);
                            },
                          ),
                          const SizedBox(width: 6),
                          _TopNavItem(
                            icon: Icons.person_outline_rounded,
                            selectedIcon: Icons.person_rounded,
                            label: 'Profile',
                            selected: currentIndex == 2,
                            onTap: () {
                              changePage(2);
                            },
                          ),
                        ],
                      )
                    else
                      PopupMenuButton<int>(
                        tooltip: 'Navigation',
                        icon: const Icon(Icons.menu_rounded),
                        onSelected: changePage,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Row(
                              children: [
                                Icon(Icons.home_outlined),
                                SizedBox(width: 12),
                                Text('Home'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 1,
                            child: Row(
                              children: [
                                Icon(Icons.shopping_cart_outlined),
                                SizedBox(width: 12),
                                Text('Cart'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 2,
                            child: Row(
                              children: [
                                Icon(Icons.person_outline_rounded),
                                SizedBox(width: 12),
                                Text('Profile'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserNotificationsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),

      // ==========================================================
      // BODY
      // ==========================================================
      body: Column(
        children: [
          if (MediaQuery.of(context).size.width < 600)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _SearchBar(
                controller: searchController,
                onChanged: searchProducts,
                onClear: clearSearch,
              ),
            ),
          Expanded(child: pages[currentIndex]),
        ],
      ),
    );
  }
}

// ============================================================================
// GOCART LOGO
// ============================================================================

class _GoCartLogo extends StatelessWidget {
  const _GoCartLogo();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.shopping_bag_rounded,
            size: 22,
            color: colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'GoCart',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SEARCH BAR
// ============================================================================

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search products...',
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 21,
            color: colorScheme.primary,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 19),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 13,
            horizontal: 4,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// TOP NAV ITEM
// ============================================================================

class _TopNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 19,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// USER PRODUCTS PAGE
// ============================================================================

class _UserProductsPage extends ConsumerStatefulWidget {
  const _UserProductsPage();

  @override
  ConsumerState<_UserProductsPage> createState() {
    return _UserProductsPageState();
  }
}

class _UserProductsPageState extends ConsumerState<_UserProductsPage> {
  String selectedCategory = 'All';

  // ============================================================
  // CATEGORY FILTER
  // ============================================================

  Future<void> selectCategory(String category) async {
    if (selectedCategory == category) {
      return;
    }

    setState(() {
      selectedCategory = category;
    });

    if (category == 'All') {
      await ref.read(productsProvider.notifier).refreshProducts();

      return;
    }

    await ref.read(productsProvider.notifier).filterByCategory(category);
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> refreshProducts() async {
    if (selectedCategory == 'All') {
      await ref.read(productsProvider.notifier).refreshProducts();

      return;
    }

    await ref
        .read(productsProvider.notifier)
        .filterByCategory(selectedCategory);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return RefreshIndicator(
      onRefresh: refreshProducts,
      child: productsAsync.when(
        loading: () => const _LoadingView(),
        error: (error, stackTrace) => _ErrorView(onRetry: refreshProducts),
        data: (products) {
          final notifier = ref.read(productsProvider.notifier);
          return _HomeContent(
            products: products,
            selectedCategory: selectedCategory,
            onCategorySelected: selectCategory,
            hasMoreProducts: notifier.hasMore,
            isLoadingMore: notifier.isLoadingMore,
            loadMoreError: notifier.loadMoreError,
            onLoadMore: notifier.loadMoreProducts,
          );
        },
      ),
    );
  }
}

// ============================================================================
// HOME CONTENT
// ============================================================================

class _HomeContent extends StatelessWidget {
  final List<Product> products;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final bool hasMoreProducts;
  final bool isLoadingMore;
  final String? loadMoreError;
  final Future<void> Function() onLoadMore;

  const _HomeContent({
    required this.products,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.hasMoreProducts,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ========================================================
                // WELCOME
                // ========================================================
                Text(
                  'Welcome to GoCart 👋',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Discover products from our merchants.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                // ========================================================
                // PROMOTIONAL BANNER
                // ========================================================
                _HomeBannerCarousel(products: products),

                const SizedBox(height: 28),

                // ========================================================
                // CATEGORIES HEADER
                // ========================================================
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shop by Category',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            selectedCategory == 'All'
                                ? 'Explore products by category'
                                : 'Showing $selectedCategory products',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (selectedCategory != 'All')
                      TextButton(
                        onPressed: () {
                          onCategorySelected('All');
                        },
                        child: const Text('Clear'),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                // ========================================================
                // CATEGORY CARDS
                // ========================================================
                _CategoryRow(
                  selectedCategory: selectedCategory,
                  onCategorySelected: onCategorySelected,
                ),

                const SizedBox(height: 32),

                // ========================================================
                // PRODUCTS HEADER
                // ========================================================
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedCategory == 'All'
                                ? 'Popular Products'
                                : '$selectedCategory Products',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            products.isEmpty
                                ? 'No products available'
                                : '${products.length} products available',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (selectedCategory != 'All')
                      TextButton.icon(
                        onPressed: () {
                          onCategorySelected('All');
                        },
                        icon: const Icon(Icons.grid_view_rounded, size: 17),
                        label: const Text('All Products'),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                // ========================================================
                // PRODUCTS
                // ========================================================
                if (products.isEmpty)
                  const _EmptyProductsView()
                else
                  _ProductGrid(products: products),

                if (hasMoreProducts || isLoadingMore || loadMoreError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Center(
                      child: loadMoreError != null
                          ? TextButton(
                              onPressed: onLoadMore,
                              child: const Text('Could not load more. Retry'),
                            )
                          : isLoadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton(
                              onPressed: onLoadMore,
                              child: const Text('Load more products'),
                            ),
                    ),
                  ),

                const SizedBox(height: 50),
              ],
            ),
          ),
        ),

        // ==============================================================
        // FOOTER
        // ==============================================================
        GoCartFooter(onCategorySelected: onCategorySelected),
      ],
    );
  }
}

// ============================================================================
// HOME PROMOTIONAL BANNER
// ============================================================================

class _HomeBannerCarousel extends StatefulWidget {
  final List<Product> products;

  const _HomeBannerCarousel({required this.products});

  @override
  State<_HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<_HomeBannerCarousel> {
  final PageController _pageController = PageController();

  Timer? _autoPlayTimer;

  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.products != widget.products) {
      final slides = _buildSlides();

      if (slides.isEmpty) {
        _currentPage = 0;
        return;
      }

      if (_currentPage >= slides.length) {
        _currentPage = 0;

        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      }

      _startAutoPlay();
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();

    if (_buildSlides().length <= 1) {
      return;
    }

    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }

      final slides = _buildSlides();

      if (slides.length <= 1) {
        return;
      }

      final nextPage = (_currentPage + 1) % slides.length;

      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  List<_HomeBannerData> _buildSlides() {
    if (widget.products.isEmpty) {
      return const [];
    }

    final slides = <_HomeBannerData>[];

    final discountedProducts =
        widget.products.where((product) => product.hasDiscount).toList()..sort(
          (a, b) => b.discountPercentage.compareTo(a.discountPercentage),
        );

    if (discountedProducts.isNotEmpty) {
      final product = discountedProducts.first;

      slides.add(
        _HomeBannerData(
          eyebrow: 'MEGA OFFERS',
          title: 'Save up to ${product.discountPercentage.round()}% OFF',
          subtitle: 'Special prices are waiting for you on selected products.',
          buttonText: 'Shop Offers',
          product: product,
          icon: Icons.local_offer_rounded,
        ),
      );
    }

    final newProducts = List<Product>.from(widget.products)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (newProducts.isNotEmpty) {
      final product = newProducts.first;

      slides.add(
        _HomeBannerData(
          eyebrow: 'NEW ARRIVALS',
          title: 'Fresh products, just added',
          subtitle: product.name,
          buttonText: 'Explore New',
          product: product,
          icon: Icons.auto_awesome_rounded,
        ),
      );
    }

    return slides;
  }

  void _openProduct(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides();

    if (slides.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 620;
        final bannerHeight = isMobile ? 210.0 : 205.0;

        return Column(
          children: [
            SizedBox(
              height: bannerHeight,
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (index) {
                  if (mounted) {
                    setState(() {
                      _currentPage = index;
                    });
                  }
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _HomeBannerCard(
                      data: slides[index],
                      isMobile: isMobile,
                      onTap: () => _openProduct(slides[index].product),
                    ),
                  );
                },
              ),
            ),
            if (slides.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slides.length, (index) {
                  final selected = index == _currentPage;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ============================================================================
// HOME BANNER DATA
// ============================================================================

class _HomeBannerData {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String buttonText;
  final Product product;
  final IconData icon;

  const _HomeBannerData({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.product,
    required this.icon,
  });
}

// ============================================================================
// HOME BANNER CARD
// ============================================================================

class _HomeBannerCard extends StatelessWidget {
  final _HomeBannerData data;
  final bool isMobile;
  final VoidCallback onTap;

  const _HomeBannerCard({
    required this.data,
    required this.isMobile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colorScheme.primary,
                Color.lerp(colorScheme.primary, Colors.black, 0.16) ??
                    colorScheme.primary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                top: -70,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 58,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 20 : 30,
                        22,
                        12,
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(
                                data.icon,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  data.eyebrow,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            data.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 22 : 28,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            data.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data.buttonText,
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 42,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: _BannerProductImage(
                          imageUrl: data.product.imageUrl,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// BANNER PRODUCT IMAGE
// ============================================================================

class _BannerProductImage extends StatelessWidget {
  final String? imageUrl;

  const _BannerProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: Colors.white.withValues(alpha: 0.12),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 52,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.white.withValues(alpha: 0.12),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return Container(
          color: colorScheme.primaryContainer.withValues(alpha: 0.45),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// PRODUCT GRID
// ============================================================================

class _ProductGrid extends StatelessWidget {
  final List<Product> products;

  const _ProductGrid({required this.products});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int columns;

        if (width >= 1000) {
          columns = 4;
        } else if (width >= 700) {
          columns = 3;
        } else if (width < 320) {
          columns = 1;
        } else {
          columns = 2;
        }

        final isPhone = width < 600;
        final spacing = isPhone ? 10.0 : 14.0;

        final itemWidth = (width - ((columns - 1) * spacing)) / columns;

        // Reduced from 0.72.
        // This makes the product cards more compact.
        final imageHeight = itemWidth * (isPhone ? 0.60 : 0.64);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,

            // Reduced from imageHeight + 142.
            // The previous height combined with Spacer()
            // created the large empty area.
            mainAxisExtent: imageHeight + (isPhone ? 104 : 112),
          ),
          itemBuilder: (context, index) {
            return _ProductCard(
              product: products[index],
              imageHeight: imageHeight,
              isCompact: isPhone,
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// PRODUCT CARD
// ============================================================================

class _ProductCard extends ConsumerWidget {
  final Product product;
  final double imageHeight;
  final bool isCompact;

  const _ProductCard({
    required this.product,
    required this.imageHeight,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final cartQuantity = ref.watch(
      cartProvider.select(
        (items) => (items.asData?.value ?? const [])
            .where((item) => item.productId == product.id)
            .fold<int>(0, (total, item) => total + item.quantity),
      ),
    );

    final isOutOfStock = product.stock <= 0;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isOutOfStock
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(product: product),
                  ),
                );
              },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================================
              // IMAGE
              // ==========================================================
              SizedBox(
                width: double.infinity,
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductImage(imageUrl: product.imageUrl),

                    // ------------------------------------------------------
                    // OUT OF STOCK
                    // ------------------------------------------------------
                    if (isOutOfStock)
                      Container(
                        color: Colors.black.withValues(alpha: 0.38),
                        child: const Center(
                          child: Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                    // ------------------------------------------------------
                    // DISCOUNT BADGE
                    // ------------------------------------------------------
                    if (product.hasDiscount && !isOutOfStock)
                      Positioned(
                        top: 9,
                        left: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${product.discountPercentage.round()}% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (cartQuantity > 0)
                      Positioned(
                        top: 9,
                        right: 9,
                        child: ProductCartQuantityBadge(quantity: cartQuantity),
                      ),
                  ],
                ),
              ),

              // ==========================================================
              // DETAILS
              // ==========================================================
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 9 : 12,
                    isCompact ? 8 : 9,
                    isCompact ? 9 : 12,
                    isCompact ? 8 : 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ----------------------------------------------------
                      // PRODUCT NAME
                      // ----------------------------------------------------
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 5),

                      // ----------------------------------------------------
                      // PRICE
                      // ----------------------------------------------------
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '₹${product.offerPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),

                          if (product.hasDiscount) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '₹${product.originalPrice.toStringAsFixed(2)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      // ----------------------------------------------------
                      // CONTROLLED GAP
                      // ----------------------------------------------------
                      const SizedBox(height: 8),

                      // ----------------------------------------------------
                      // STOCK + CART
                      // ----------------------------------------------------
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOutOfStock
                                  ? colorScheme.error
                                  : Colors.green,
                            ),
                          ),

                          const SizedBox(width: 5),

                          Expanded(
                            child: Text(
                              isOutOfStock
                                  ? 'Unavailable'
                                  : '${product.stock} available',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),

                          const SizedBox(width: 6),

                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.shopping_cart_outlined,
                              size: 17,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PRODUCT IMAGE
// ============================================================================

class _ProductImage extends StatelessWidget {
  final String? imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 50,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// CATEGORY ROW
// ============================================================================

class _CategoryRow extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const _CategoryRow({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: ProductCategory.all.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          // First item = All Products
          if (index == 0) {
            return _CategoryCard(
              name: 'All Products',
              icon: Icons.grid_view_rounded,
              selected: selectedCategory == 'All',
              onTap: () {
                onCategorySelected('All');
              },
            );
          }

          final category = ProductCategory.all[index - 1];

          return _CategoryCard(
            name: category.name,
            icon: category.icon,
            selected: selectedCategory == category.name,
            onTap: () {
              onCategorySelected(category.name);
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// CATEGORY CARD
// ============================================================================

class _CategoryCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 112,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 23,
                  color: selected ? Colors.white : colorScheme.primary,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : colorScheme.onSurface,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LOADING
// ============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: CircularProgressIndicator(color: colorScheme.primary),
      ),
    );
  }
}

// ============================================================================
// ERROR
// ============================================================================

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 55,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load products',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EMPTY PRODUCTS
// ============================================================================

class _EmptyProductsView extends StatelessWidget {
  const _EmptyProductsView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 55,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text(
            'No products available',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'Products added by merchants will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
