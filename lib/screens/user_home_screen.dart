import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../providers/product_provider.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'profile_screen.dart';

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

    searchTimer = Timer(const Duration(milliseconds: 450), () {
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
    final colorScheme = Theme.of(context).colorScheme;

    final pages = [
      const _UserProductsPage(),
      const CartScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,

      // ==========================================================
      // TOP NAVIGATION
      // ==========================================================
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                // ==================================================
                // LOGO
                // ==================================================
                const _GoCartLogo(),

                const SizedBox(width: 28),

                // ==================================================
                // SEARCH BAR
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
                // TOP NAVIGATION
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
              ],
            );
          },
        ),
      ),

      // ==========================================================
      // BODY
      // ==========================================================
      body: Column(
        children: [
          // Search bar for smaller screens
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

class _UserProductsPage extends ConsumerWidget {
  const _UserProductsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(productsProvider.notifier).refreshProducts();
      },
      child: productsAsync.when(
        loading: () => const _LoadingView(),

        error: (error, stackTrace) => _ErrorView(
          onRetry: () {
            ref.read(productsProvider.notifier).refreshProducts();
          },
        ),

        data: (products) => _HomeContent(products: products),
      ),
    );
  }
}

// ============================================================================
// HOME CONTENT
// ============================================================================

class _HomeContent extends StatelessWidget {
  final List<Product> products;

  const _HomeContent({required this.products});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ==========================================================
                // WELCOME
                // ==========================================================
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

                const SizedBox(height: 28),

                // ==========================================================
                // CATEGORIES
                // ==========================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Categories',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: const Text('Browse all'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                const _CategoryRow(),

                const SizedBox(height: 32),

                // ==========================================================
                // PRODUCTS HEADER
                // ==========================================================
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Popular Products',
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

                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: const Text('View all'),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ==========================================================
                // PRODUCTS
                // ==========================================================
                if (products.isEmpty)
                  const _EmptyProductsView()
                else
                  _ProductGrid(products: products),
              ],
            ),
          ),
        ),
      ],
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

        if (width >= 1050) {
          columns = 4;
        } else if (width >= 720) {
          columns = 3;
        } else {
          columns = 2;
        }

        const spacing = 14.0;

        final itemWidth = (width - ((columns - 1) * spacing)) / columns;

        final imageHeight = itemWidth * 0.72;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: imageHeight + 142,
          ),
          itemBuilder: (context, index) {
            return _ProductCard(
              product: products[index],
              imageHeight: imageHeight,
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

class _ProductCard extends StatelessWidget {
  final Product product;
  final double imageHeight;

  const _ProductCard({required this.product, required this.imageHeight});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isOutOfStock = product.stock == 0;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============================================================
              // IMAGE
              // ============================================================
              SizedBox(
                width: double.infinity,
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductImage(imageUrl: product.imageUrl),

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
                  ],
                ),
              ),

              // ============================================================
              // DETAILS
              // ============================================================
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        '₹${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),

                      const Spacer(),

                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOutOfStock
                                  ? colorScheme.error
                                  : Colors.green,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            child: Text(
                              isOutOfStock
                                  ? 'Unavailable'
                                  : '${product.stock} available',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),

                          const SizedBox(width: 6),

                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.shopping_cart_outlined,
                              size: 18,
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
  const _CategoryRow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final categories = [
      ('Electronics', Icons.devices_outlined),
      ('Fashion', Icons.checkroom_outlined),
      ('Home', Icons.home_outlined),
      ('Sports', Icons.sports_soccer_outlined),
    ];

    return Row(
      children: [
        for (int i = 0; i < categories.length; i++) ...[
          Expanded(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      categories[i].$2,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    categories[i].$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (i < categories.length - 1) const SizedBox(width: 12),
        ],
      ],
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
