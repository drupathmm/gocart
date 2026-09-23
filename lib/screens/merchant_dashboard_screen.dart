import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../providers/product_provider.dart';
import 'add_product_screen.dart';
import 'edit_product_screen.dart';
import 'profile_screen.dart';

class MerchantDashboardScreen extends ConsumerWidget {
  const MerchantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(myProductsProvider);

    return Scaffold(
      backgroundColor: _GoCartColors.background,
      appBar: AppBar(
        backgroundColor: _GoCartColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const _MerchantTopBar(),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            icon: const Icon(Icons.account_circle_outlined, size: 27),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: RefreshIndicator(
        color: _GoCartColors.primary,
        backgroundColor: Colors.white,
        onRefresh: () async {
          await ref.read(myProductsProvider.notifier).refreshProducts();
        },
        child: productsAsync.when(
          loading: () => const _LoadingView(),
          error: (error, stackTrace) => _ErrorView(
            onRetry: () {
              ref.read(myProductsProvider.notifier).refreshProducts();
            },
          ),
          data: (products) {
            return _DashboardContent(
              products: products,
              onAddProduct: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddProductScreen(),
                  ),
                );

                if (!context.mounted) {
                  return;
                }

                await ref.read(myProductsProvider.notifier).refreshProducts();
              },
              onEditProduct: (product) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProductScreen(product: product),
                  ),
                );

                if (!context.mounted) {
                  return;
                }

                await ref.read(myProductsProvider.notifier).refreshProducts();
              },
              onDeleteProduct: (product) async {
                await _deleteProduct(context, ref, product);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteProduct(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Delete Product',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text('Are you sure you want to delete "${product.name}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _GoCartColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref.read(myProductsProvider.notifier).deleteProduct(product.id);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product deleted successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete product: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ============================================================================
// COLORS
// ============================================================================

const List<String> _merchantCategories = [
  'Electronics',
  'Fashion',
  'Beauty',
  'Home',
  'Groceries',
  'Sports',
  'Books',
  'Toys & Games',
  'Health & Wellness',
  'Other',
];

class _GoCartColors {
  static const Color background = Color(0xFFFFF9FF);

  static const Color primary = Color(0xFF6F4B9B);

  static const Color primarySoft = Color(0xFFF1E8FA);
  static const Color primaryLighter = Color(0xFFF8F2FC);

  static const Color text = Color(0xFF201A24);
  static const Color muted = Color(0xFF766F7C);
  static const Color border = Color(0xFFE9E0ED);

  static const Color success = Color(0xFF29965A);
  static const Color successSoft = Color(0xFFEAF8F0);

  static const Color warning = Color(0xFFE08A24);
  static const Color warningSoft = Color(0xFFFFF3E3);

  static const Color error = Color(0xFFD84A4A);
  static const Color errorSoft = Color(0xFFFFEBEB);

  static const Color blue = Color(0xFF4B72C8);
  static const Color blueSoft = Color(0xFFEDF2FF);
}

// ============================================================================
// TOP BAR
// ============================================================================

class _MerchantTopBar extends StatelessWidget {
  const _MerchantTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _GoCartColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            size: 21,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 11),
        const Text(
          'GoCart',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: _GoCartColors.text,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// DASHBOARD
// ============================================================================

class _DashboardContent extends StatefulWidget {
  final List<Product> products;
  final VoidCallback onAddProduct;
  final Future<void> Function(Product product) onEditProduct;
  final Future<void> Function(Product product) onDeleteProduct;

  const _DashboardContent({
    required this.products,
    required this.onAddProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
  });

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  String? _selectedCategory;

  @override
  void didUpdateWidget(covariant _DashboardContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_selectedCategory != null &&
        !widget.products.any(
          (product) => product.category == _selectedCategory,
        )) {
      _selectedCategory = null;
    }
  }

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final totalProducts = products.length;

    final totalStock = products.fold<int>(
      0,
      (total, product) => total + product.stock,
    );

    final lowStockProducts = products
        .where((product) => product.stock > 0 && product.stock <= 5)
        .toList();

    final outOfStockProducts = products
        .where((product) => product.stock <= 0)
        .toList();

    final totalInventoryValue = products.fold<double>(
      0,
      (total, product) => total + (product.offerPrice * product.stock),
    );

    final discountedProducts = products
        .where((product) => product.hasDiscount)
        .length;

    final filteredProducts = _selectedCategory == null
        ? products
        : products
              .where((product) => product.category == _selectedCategory)
              .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ==========================================================
                // HEADER
                // ==========================================================
                _DashboardHeader(
                  productCount: totalProducts,
                  onAddProduct: widget.onAddProduct,
                ),

                const SizedBox(height: 22),

                // ==========================================================
                // KPI CARDS
                // ==========================================================
                _KpiGrid(
                  totalProducts: totalProducts,
                  totalStock: totalStock,
                  lowStockCount: lowStockProducts.length,
                  outOfStockCount: outOfStockProducts.length,
                ),

                const SizedBox(height: 22),

                // ==========================================================
                // INVENTORY SUMMARY
                // ==========================================================
                _InventorySummary(
                  inventoryValue: totalInventoryValue,
                  discountedProducts: discountedProducts,
                  totalProducts: totalProducts,
                ),

                const SizedBox(height: 26),

                // ==========================================================
                // ANALYTICS
                // ==========================================================
                const _SectionHeader(
                  title: 'Store Analytics',
                  subtitle:
                      'Understand your catalog and inventory at a glance.',
                ),

                const SizedBox(height: 12),

                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          _CategoryStockChart(products: products),
                          const SizedBox(height: 14),
                          _InventoryValueChart(products: products),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _CategoryStockChart(products: products),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _InventoryValueChart(products: products),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 26),

                // ==========================================================
                // SALES ANALYTICS
                // ==========================================================
                const _SalesAnalyticsCard(),

                const SizedBox(height: 28),

                // ==========================================================
                // LOW STOCK
                // ==========================================================
                if (lowStockProducts.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Low Stock Alerts',
                    subtitle:
                        '${lowStockProducts.length} ${lowStockProducts.length == 1 ? 'product needs' : 'products need'} attention.',
                    trailing: _AlertBadge(count: lowStockProducts.length),
                  ),
                  const SizedBox(height: 12),
                  _LowStockSection(
                    products: lowStockProducts,
                    onEditProduct: widget.onEditProduct,
                  ),
                  const SizedBox(height: 26),
                ],

                // ==========================================================
                // OUT OF STOCK
                // ==========================================================
                if (outOfStockProducts.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Out of Stock',
                    subtitle:
                        '${outOfStockProducts.length} ${outOfStockProducts.length == 1 ? 'product is' : 'products are'} unavailable.',
                    trailing: _AlertBadge(
                      count: outOfStockProducts.length,
                      error: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _OutOfStockSection(
                    products: outOfStockProducts,
                    onEditProduct: widget.onEditProduct,
                  ),
                  const SizedBox(height: 26),
                ],

                // ==========================================================
                // CATEGORIES
                // ==========================================================
                const _SectionHeader(
                  title: 'My Product Categories',
                  subtitle: 'Organize and understand your product catalog.',
                ),

                const SizedBox(height: 12),

                _CategoryOverview(
                  products: products,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: _selectCategory,
                ),

                const SizedBox(height: 28),

                // ==========================================================
                // PRODUCTS
                // ==========================================================
                _SectionHeader(
                  title: _selectedCategory == null
                      ? 'My Products'
                      : '$_selectedCategory Products',
                  subtitle: _selectedCategory == null
                      ? (products.isEmpty
                            ? 'Your product catalog is empty.'
                            : '$totalProducts ${totalProducts == 1 ? 'product' : 'products'} in your catalog.')
                      : (filteredProducts.isEmpty
                            ? 'No products in this category.'
                            : '${filteredProducts.length} ${filteredProducts.length == 1 ? 'product' : 'products'} in $_selectedCategory.'),
                  trailing: FilledButton.icon(
                    onPressed: widget.onAddProduct,
                    style: FilledButton.styleFrom(
                      backgroundColor: _GoCartColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'Add Product',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (filteredProducts.isEmpty)
                  _EmptyProductsView(
                    onAddProduct: widget.onAddProduct,
                    message: _selectedCategory == null
                        ? 'Add your first product to start building your store catalog.'
                        : 'There are no products in this category yet.',
                    buttonLabel: _selectedCategory == null
                        ? 'Add Product'
                        : 'Add Product',
                  )
                else
                  ...filteredProducts.map(
                    (product) => _ProductCard(
                      product: product,
                      onEdit: () {
                        widget.onEditProduct(product);
                      },
                      onDelete: () {
                        widget.onDeleteProduct(product);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// DASHBOARD HEADER
// ============================================================================

class _DashboardHeader extends StatelessWidget {
  final int productCount;
  final VoidCallback onAddProduct;

  const _DashboardHeader({
    required this.productCount,
    required this.onAddProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3E9FB), Color(0xFFFFF9FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7D9EF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 570;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderIcon(),
                const SizedBox(height: 16),
                _HeaderText(productCount: productCount),
                const SizedBox(height: 18),
                _AddProductButton(onPressed: onAddProduct, expanded: true),
              ],
            );
          }

          return Row(
            children: [
              const _HeaderIcon(),
              const SizedBox(width: 16),
              Expanded(child: _HeaderText(productCount: productCount)),
              const SizedBox(width: 16),
              _AddProductButton(onPressed: onAddProduct),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _GoCartColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.dashboard_customize_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  final int productCount;

  const _HeaderText({required this.productCount});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Merchant Dashboard',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _GoCartColors.text,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Manage your store, products and inventory in one place.',
          style: const TextStyle(fontSize: 13, color: _GoCartColors.muted),
        ),
        const SizedBox(height: 9),
        Text(
          '$productCount ${productCount == 1 ? 'product' : 'products'} currently in your catalog',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _GoCartColors.primary,
          ),
        ),
      ],
    );
  }
}

class _AddProductButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool expanded;

  const _AddProductButton({required this.onPressed, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _GoCartColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: const Icon(Icons.add_rounded, size: 19),
      label: const Text(
        'Add Product',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}

// ============================================================================
// KPI GRID
// ============================================================================

class _KpiGrid extends StatelessWidget {
  final int totalProducts;
  final int totalStock;
  final int lowStockCount;
  final int outOfStockCount;

  const _KpiGrid({
    required this.totalProducts,
    required this.totalStock,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int columns;

        if (width >= 900) {
          columns = 4;
        } else if (width >= 560) {
          columns = 2;
        } else {
          columns = 1;
        }

        const spacing = 12.0;

        final cardWidth = (width - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.inventory_2_outlined,
                title: 'Products',
                value: '$totalProducts',
                subtitle: 'In your catalog',
                iconColor: _GoCartColors.primary,
                iconBackground: _GoCartColors.primarySoft,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.warehouse_outlined,
                title: 'Total Stock',
                value: '$totalStock',
                subtitle: 'Units available',
                iconColor: _GoCartColors.blue,
                iconBackground: _GoCartColors.blueSoft,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.warning_amber_rounded,
                title: 'Low Stock',
                value: '$lowStockCount',
                subtitle: lowStockCount == 0
                    ? 'Everything looks good'
                    : 'Needs attention',
                iconColor: _GoCartColors.warning,
                iconBackground: _GoCartColors.warningSoft,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.remove_shopping_cart_outlined,
                title: 'Out of Stock',
                value: '$outOfStockCount',
                subtitle: outOfStockCount == 0
                    ? 'All products available'
                    : 'Unavailable products',
                iconColor: _GoCartColors.error,
                iconBackground: _GoCartColors.errorSoft,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color iconColor;
  final Color iconBackground;

  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.iconColor,
    required this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _GoCartColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: _GoCartColors.text,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _GoCartColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _GoCartColors.muted),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// INVENTORY SUMMARY
// ============================================================================

class _InventorySummary extends StatelessWidget {
  final double inventoryValue;
  final int discountedProducts;
  final int totalProducts;

  const _InventorySummary({
    required this.inventoryValue,
    required this.discountedProducts,
    required this.totalProducts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: BoxDecoration(
        color: _GoCartColors.primaryLighter,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9DDF2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;

          final items = [
            _SummaryItem(
              icon: Icons.payments_outlined,
              label: 'Inventory value',
              value: '₹${inventoryValue.toStringAsFixed(0)}',
            ),
            _SummaryItem(
              icon: Icons.local_offer_outlined,
              label: 'Products on offer',
              value: '$discountedProducts',
            ),
            _SummaryItem(
              icon: Icons.storefront_outlined,
              label: 'Catalog size',
              value: '$totalProducts',
            ),
          ];

          if (compact) {
            return Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i < items.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 11),
                      child: Divider(height: 1, color: _GoCartColors.border),
                    ),
                ],
              ],
            );
          }

          return Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                Expanded(child: items[i]),
                if (i < items.length - 1)
                  const SizedBox(
                    height: 38,
                    child: VerticalDivider(
                      width: 1,
                      color: _GoCartColors.border,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: _GoCartColors.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: _GoCartColors.muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _GoCartColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SECTION HEADER
// ============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _GoCartColors.text,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: _GoCartColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

// ============================================================================
// INTERACTIVE CATEGORY STOCK CHART
// ============================================================================

class _CategoryStockChart extends StatefulWidget {
  final List<Product> products;

  const _CategoryStockChart({required this.products});

  @override
  State<_CategoryStockChart> createState() => _CategoryStockChartState();
}

class _CategoryStockChartState extends State<_CategoryStockChart> {
  int? _hoveredIndex;
  Offset? _pointerPosition;

  void _updateHover(Offset localPosition, int entryCount) {
    if (entryCount == 0) {
      return;
    }

    const chartSize = 190.0;
    final center = const Offset(chartSize / 2, chartSize / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt((dx * dx) + (dy * dy));

    if (distance > 87 || distance < 28) {
      if (_hoveredIndex != null) {
        setState(() {
          _hoveredIndex = null;
          _pointerPosition = null;
        });
      }
      return;
    }

    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) {
      angle += math.pi * 2;
    }

    final categoryStock = <String, int>{};
    for (final product in widget.products) {
      categoryStock.update(
        product.category,
        (value) => value + product.stock,
        ifAbsent: () => product.stock,
      );
    }

    final entries =
        categoryStock.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total <= 0) {
      return;
    }

    var accumulated = 0.0;
    int? index;

    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / total) * math.pi * 2;
      if (angle >= accumulated && angle < accumulated + sweep) {
        index = i;
        break;
      }
      accumulated += sweep;
    }

    if (index != _hoveredIndex || _pointerPosition != localPosition) {
      setState(() {
        _hoveredIndex = index;
        _pointerPosition = localPosition;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryStock = <String, int>{};

    for (final product in widget.products) {
      categoryStock.update(
        product.category,
        (value) => value + product.stock,
        ifAbsent: () => product.stock,
      );
    }

    final entries =
        categoryStock.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final totalStock = entries.fold<int>(0, (sum, entry) => sum + entry.value);

    return _AnalyticsCard(
      title: 'Stock by Category',
      subtitle: 'Hover over a segment for details',
      icon: Icons.pie_chart_outline_rounded,
      child: entries.isEmpty
          ? const _ChartEmptyState(message: 'No stock data available yet.')
          : SizedBox(
              height: 210,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onHover: (event) {
                      _updateHover(event.localPosition, entries.length);
                    },
                    onExit: (_) {
                      if (_hoveredIndex != null) {
                        setState(() {
                          _hoveredIndex = null;
                          _pointerPosition = null;
                        });
                      }
                    },
                    child: Row(
                      children: [
                        SizedBox(
                          width: 190,
                          height: 190,
                          child: CustomPaint(
                            painter: _PieChartPainter(
                              values: entries
                                  .map((entry) => entry.value.toDouble())
                                  .toList(),
                              colors: _chartColors(entries.length),
                              hoveredIndex: _hoveredIndex,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < entries.length && i < 5; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: _LegendItem(
                                    color: _chartColors(entries.length)[i],
                                    label: entries[i].key,
                                    value: '${entries[i].value}',
                                  ),
                                ),
                              if (entries.length > 5)
                                const Text(
                                  '+ more categories',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _GoCartColors.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hoveredIndex != null &&
                      _hoveredIndex! < entries.length &&
                      _pointerPosition != null)
                    Positioned(
                      left: (_pointerPosition!.dx + 12).clamp(0.0, 340.0),
                      top: (_pointerPosition!.dy - 8).clamp(0.0, 160.0),
                      child: IgnorePointer(
                        child: _ChartHoverTooltip(
                          title: entries[_hoveredIndex!].key,
                          lines: [
                            '${entries[_hoveredIndex!].value} units in stock',
                            '${_categoryProductCount(widget.products, entries[_hoveredIndex!].key)} products',
                            totalStock > 0
                                ? '${((entries[_hoveredIndex!].value / totalStock) * 100).toStringAsFixed(1)}% of stock'
                                : '0% of stock',
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ============================================================================
// INTERACTIVE INVENTORY VALUE BAR CHART
// ============================================================================

class _InventoryValueChart extends StatefulWidget {
  final List<Product> products;

  const _InventoryValueChart({required this.products});

  @override
  State<_InventoryValueChart> createState() => _InventoryValueChartState();
}

class _InventoryValueChartState extends State<_InventoryValueChart> {
  int? _hoveredIndex;
  Offset? _pointerPosition;

  @override
  Widget build(BuildContext context) {
    final categoryValue = <String, double>{};

    for (final product in widget.products) {
      final value = product.offerPrice * product.stock;
      categoryValue.update(
        product.category,
        (current) => current + value,
        ifAbsent: () => value,
      );
    }

    final entries = categoryValue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final chartEntries = entries.take(6).toList();

    return _AnalyticsCard(
      title: 'Inventory Value',
      subtitle: 'Hover over a bar for details',
      icon: Icons.bar_chart_rounded,
      child: chartEntries.isEmpty
          ? const _ChartEmptyState(message: 'No inventory data available yet.')
          : SizedBox(
              height: 235,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onHover: (event) {
                          const leftPadding = 12.0;
                          const rightPadding = 8.0;
                          const barSpacing = 12.0;
                          final width = constraints.maxWidth;
                          final chartWidth = width - leftPadding - rightPadding;
                          final barWidth =
                              (chartWidth -
                                  ((chartEntries.length - 1) * barSpacing)) /
                              chartEntries.length;

                          final x = event.localPosition.dx - leftPadding;
                          final step = barWidth + barSpacing;
                          final index = (x / step).floor();

                          int? nextIndex;
                          if (index >= 0 && index < chartEntries.length) {
                            final barStart = index * step;
                            if (x >= barStart && x <= barStart + barWidth) {
                              nextIndex = index;
                            }
                          }

                          if (nextIndex != _hoveredIndex ||
                              _pointerPosition != event.localPosition) {
                            setState(() {
                              _hoveredIndex = nextIndex;
                              _pointerPosition = event.localPosition;
                            });
                          }
                        },
                        onExit: (_) {
                          if (_hoveredIndex != null) {
                            setState(() {
                              _hoveredIndex = null;
                              _pointerPosition = null;
                            });
                          }
                        },
                        child: CustomPaint(
                          painter: _BarChartPainter(
                            entries: chartEntries,
                            hoveredIndex: _hoveredIndex,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      if (_hoveredIndex != null &&
                          _hoveredIndex! < chartEntries.length &&
                          _pointerPosition != null)
                        Positioned(
                          left: (_pointerPosition!.dx + 12).clamp(
                            0.0,
                            math.max(0.0, constraints.maxWidth - 190),
                          ),
                          top: (_pointerPosition!.dy - 20).clamp(0.0, 185.0),
                          child: IgnorePointer(
                            child: _ChartHoverTooltip(
                              title: chartEntries[_hoveredIndex!].key,
                              lines: [
                                'Inventory value: ${_formatFullCurrency(chartEntries[_hoveredIndex!].value)}',
                                '${_categoryProductCount(widget.products, chartEntries[_hoveredIndex!].key)} products',
                                '${_categoryStockCount(widget.products, chartEntries[_hoveredIndex!].key)} units in stock',
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _ChartHoverTooltip extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _ChartHoverTooltip({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2133),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines) ...[
              Text(
                line,
                style: const TextStyle(
                  color: Color(0xFFE9DFF0),
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

int _categoryProductCount(List<Product> products, String category) {
  return products.where((product) => product.category == category).length;
}

int _categoryStockCount(List<Product> products, String category) {
  return products
      .where((product) => product.category == category)
      .fold<int>(0, (sum, product) => sum + product.stock);
}

String _formatFullCurrency(double value) {
  return '₹${value.toStringAsFixed(2)}';
}

// ============================================================================
// ANALYTICS CARD
// ============================================================================

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _AnalyticsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _GoCartColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _GoCartColors.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: _GoCartColors.primary, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _GoCartColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: _GoCartColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  final String message;

  const _ChartEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _GoCartColors.primaryLighter,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: _GoCartColors.muted),
      ),
    );
  }
}

// ============================================================================
// SALES ANALYTICS
// ============================================================================

class _SalesAnalyticsCard extends StatelessWidget {
  const _SalesAnalyticsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4ECFB), Color(0xFFFFFBFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6D8EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _GoCartColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sales Analytics',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _GoCartColors.text,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Sales graphs will become available once orders and completed purchases are connected to the dashboard.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: _GoCartColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'Coming next',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _GoCartColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LOW STOCK
// ============================================================================

class _LowStockSection extends StatelessWidget {
  final List<Product> products;
  final Future<void> Function(Product product) onEditProduct;

  const _LowStockSection({required this.products, required this.onEditProduct});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: products.map((product) {
        return _AlertProductCard(
          product: product,
          isOutOfStock: false,
          onEdit: () {
            onEditProduct(product);
          },
        );
      }).toList(),
    );
  }
}

// ============================================================================
// OUT OF STOCK
// ============================================================================

class _OutOfStockSection extends StatelessWidget {
  final List<Product> products;
  final Future<void> Function(Product product) onEditProduct;

  const _OutOfStockSection({
    required this.products,
    required this.onEditProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: products.map((product) {
        return _AlertProductCard(
          product: product,
          isOutOfStock: true,
          onEdit: () {
            onEditProduct(product);
          },
        );
      }).toList(),
    );
  }
}

class _AlertProductCard extends StatelessWidget {
  final Product product;
  final bool isOutOfStock;
  final VoidCallback onEdit;

  const _AlertProductCard({
    required this.product,
    required this.isOutOfStock,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOutOfStock ? _GoCartColors.error : _GoCartColors.warning;

    final background = isOutOfStock
        ? _GoCartColors.errorSoft
        : _GoCartColors.warningSoft;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          _ProductImage(imageUrl: product.imageUrl, size: 58),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _GoCartColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.category,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _GoCartColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    isOutOfStock
                        ? 'Out of stock'
                        : 'Only ${product.stock} units left',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              foregroundColor: _GoCartColors.primary,
              side: const BorderSide(color: _GoCartColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ALERT BADGE
// ============================================================================

class _AlertBadge extends StatelessWidget {
  final int count;
  final bool error;

  const _AlertBadge({required this.count, this.error = false});

  @override
  Widget build(BuildContext context) {
    final color = error ? _GoCartColors.error : _GoCartColors.warning;

    final background = error
        ? _GoCartColors.errorSoft
        : _GoCartColors.warningSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================================
// CATEGORY OVERVIEW
// ============================================================================

class _CategoryOverview extends StatelessWidget {
  final List<Product> products;
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  const _CategoryOverview({
    required this.products,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final categories = <String, int>{
      for (final category in _merchantCategories) category: 0,
    };

    for (final product in products) {
      if (_merchantCategories.contains(product.category)) {
        categories[product.category] = categories[product.category]! + 1;
      }
    }

    final entries = categories.entries.toList();

    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _GoCartColors.border),
        ),
        child: const Text(
          'Categories will appear here when you add products.',
          style: TextStyle(fontSize: 12, color: _GoCartColors.muted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CategoryFilterChip(
                label: 'All Categories',
                icon: Icons.grid_view_rounded,
                selected: selectedCategory == null,
                color: _GoCartColors.primary,
                onTap: () => onCategorySelected(null),
              ),
              const SizedBox(width: 8),
              ...entries.asMap().entries.map((item) {
                final index = item.key;
                final entry = item.value;
                final color = _categoryColors[index % _categoryColors.length];

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CategoryFilterChip(
                    label: '${entry.key} • ${entry.value}',
                    icon: _categoryIcon(entry.key),
                    selected: selectedCategory == entry.key,
                    color: color,
                    onTap: () => onCategorySelected(entry.key),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: entries.asMap().entries.map((item) {
            final index = item.key;
            final entry = item.value;
            final colorIndex = index % _categoryColors.length;
            final selected = selectedCategory == entry.key;

            return InkWell(
              onTap: () => onCategorySelected(selected ? null : entry.key),
              borderRadius: BorderRadius.circular(15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 185,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: selected
                      ? _categoryColors[colorIndex].withValues(alpha: 0.09)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: selected
                        ? _categoryColors[colorIndex]
                        : _GoCartColors.border,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _categoryColors[colorIndex].withValues(
                              alpha: 0.10,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _categoryColors[colorIndex].withValues(
                          alpha: 0.11,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _categoryIcon(entry.key),
                        size: 18,
                        color: _categoryColors[colorIndex],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _GoCartColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${entry.value} ${entry.value == 1 ? 'product' : 'products'}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _GoCartColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 17,
                        color: _categoryColors[colorIndex],
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : _GoCartColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : _GoCartColors.text,
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
// PRODUCT CARD
// ============================================================================

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = _getStockStatus(product.stock);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _GoCartColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.018),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    _ProductImage(imageUrl: product.imageUrl, size: 72),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ProductInfo(product: product, status: status),
                    ),
                    _ProductMenu(onEdit: onEdit, onDelete: onDelete),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              _ProductImage(imageUrl: product.imageUrl, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: _ProductInfo(product: product, status: status),
              ),
              const SizedBox(width: 14),
              _ProductMenu(onEdit: onEdit, onDelete: onDelete),
            ],
          );
        },
      ),
    );
  }

  _StockStatus _getStockStatus(int stock) {
    if (stock <= 0) {
      return const _StockStatus(
        label: 'Out of stock',
        color: _GoCartColors.error,
        background: _GoCartColors.errorSoft,
      );
    }

    if (stock <= 5) {
      return const _StockStatus(
        label: 'Low stock',
        color: _GoCartColors.warning,
        background: _GoCartColors.warningSoft,
      );
    }

    return const _StockStatus(
      label: 'In stock',
      color: _GoCartColors.success,
      background: _GoCartColors.successSoft,
    );
  }
}

class _ProductInfo extends StatelessWidget {
  final Product product;
  final _StockStatus status;

  const _ProductInfo({required this.product, required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _GoCartColors.text,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          product.category,
          style: const TextStyle(fontSize: 10, color: _GoCartColors.muted),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              '₹${product.offerPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _GoCartColors.primary,
              ),
            ),
            if (product.hasDiscount) ...[
              const SizedBox(width: 7),
              Text(
                '₹${product.originalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: _GoCartColors.muted,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${product.discountPercentage.round()}% OFF',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _GoCartColors.success,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: status.background,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '${status.label} • ${product.stock} units',
            style: TextStyle(
              fontSize: 10,
              color: status.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StockStatus {
  final String label;
  final Color color;
  final Color background;

  const _StockStatus({
    required this.label,
    required this.color,
    required this.background,
  });
}

class _ProductMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Product actions',
      icon: const Icon(Icons.more_vert_rounded, color: _GoCartColors.muted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        }

        if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 19),
                SizedBox(width: 10),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: _GoCartColors.error,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Delete',
                  style: TextStyle(color: _GoCartColors.error),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }
}

// ============================================================================
// PRODUCT IMAGE
// ============================================================================

class _ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _ProductImage({required this.imageUrl, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: size,
        height: size,
        color: _GoCartColors.primaryLighter,
        child: hasImage
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: _GoCartColors.muted,
                    ),
                  );
                },
              )
            : const Center(
                child: Icon(Icons.image_outlined, color: _GoCartColors.muted),
              ),
      ),
    );
  }
}

// ============================================================================
// EMPTY PRODUCTS
// ============================================================================

class _EmptyProductsView extends StatelessWidget {
  final VoidCallback onAddProduct;
  final String message;
  final String buttonLabel;

  const _EmptyProductsView({
    required this.onAddProduct,
    this.message =
        'Add your first product to start building your store catalog.',
    this.buttonLabel = 'Add Product',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _GoCartColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _GoCartColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 31,
              color: _GoCartColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No products yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _GoCartColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: _GoCartColors.muted,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAddProduct,
            style: OutlinedButton.styleFrom(
              foregroundColor: _GoCartColors.primary,
              side: const BorderSide(color: _GoCartColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _GoCartColors.primary,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Loading your store...',
                  style: TextStyle(fontSize: 12, color: _GoCartColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: _GoCartColors.errorSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      size: 32,
                      color: _GoCartColors.error,
                    ),
                  ),
                  const SizedBox(height: 17),
                  const Text(
                    'Could not load products',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _GoCartColors.text,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Something went wrong while loading your store.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _GoCartColors.muted),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _GoCartColors.primary,
                      side: const BorderSide(color: _GoCartColors.primary),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// LEGEND
// ============================================================================

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _GoCartColors.muted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _GoCartColors.text,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PIE CHART PAINTER
// ============================================================================

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final int? hoveredIndex;

  const _PieChartPainter({
    required this.values,
    required this.colors,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    final total = values.fold<double>(0, (sum, value) => sum + value);

    if (total <= 0) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);

    final radius = math.min(size.width, size.height) / 2 - 8;

    final paint = Paint()..style = PaintingStyle.fill;

    double startAngle = -math.pi / 2;

    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * math.pi * 2;

      paint.color = colors[i % colors.length];

      final isHovered = hoveredIndex == i;
      final currentRadius = isHovered ? radius + 5 : radius;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: currentRadius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    }

    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.57, centerPaint);

    final totalText = total.toInt().toString();

    final textPainter = TextPainter(
      text: TextSpan(
        text: totalText,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: _GoCartColors.text,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2 - 5,
      ),
    );

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'units',
        style: TextStyle(fontSize: 9, color: _GoCartColors.muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + 10),
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}

// ============================================================================
// BAR CHART PAINTER
// ============================================================================

class _BarChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final int? hoveredIndex;

  const _BarChartPainter({required this.entries, this.hoveredIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) {
      return;
    }

    const leftPadding = 12.0;
    const rightPadding = 8.0;
    const topPadding = 10.0;
    const bottomPadding = 42.0;

    final chartWidth = size.width - leftPadding - rightPadding;

    final chartHeight = size.height - topPadding - bottomPadding;

    final maxValue = entries.map((entry) => entry.value).reduce(math.max);

    if (maxValue <= 0) {
      return;
    }

    final barSpacing = 12.0;

    final barWidth =
        (chartWidth - ((entries.length - 1) * barSpacing)) / entries.length;

    final gridPaint = Paint()
      ..color = _GoCartColors.border
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + (chartHeight / 3) * i;

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];

      final ratio = entry.value / maxValue;

      final barHeight = chartHeight * ratio;

      final x = leftPadding + i * (barWidth + barSpacing);

      final y = topPadding + chartHeight - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(7),
      );

      final paint = Paint()
        ..color = _categoryColors[i % _categoryColors.length];

      if (hoveredIndex == i) {
        paint.color = _categoryColors[i % _categoryColors.length].withValues(
          alpha: 0.78,
        );
      }

      canvas.drawRRect(rect, paint);

      final label = _shortCategory(entry.key);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 8,
            color: _GoCartColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: barWidth + 10);

      labelPainter.paint(
        canvas,
        Offset(x + (barWidth - labelPainter.width) / 2, size.height - 28),
      );

      final valueLabel = _compactCurrency(entry.value);

      final valuePainter = TextPainter(
        text: TextSpan(
          text: valueLabel,
          style: const TextStyle(
            fontSize: 8,
            color: _GoCartColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWidth + 16);

      valuePainter.paint(
        canvas,
        Offset(x + (barWidth - valuePainter.width) / 2, math.max(0, y - 13)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}

// ============================================================================
// CHART HELPERS
// ============================================================================

const List<Color> _categoryColors = [
  Color(0xFF7652A5),
  Color(0xFF9A78C2),
  Color(0xFFB995D7),
  Color(0xFF5E83C6),
  Color(0xFF65A58A),
  Color(0xFFE19A51),
  Color(0xFFD16B83),
];

List<Color> _chartColors(int count) {
  if (count <= 0) {
    return const [Color(0xFF7652A5)];
  }

  return List<Color>.generate(
    count,
    (index) => _categoryColors[index % _categoryColors.length],
  );
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'electronics':
      return Icons.devices_outlined;

    case 'fashion':
      return Icons.checkroom_outlined;

    case 'beauty':
      return Icons.spa_outlined;

    case 'home':
      return Icons.home_outlined;

    case 'groceries':
      return Icons.local_grocery_store_outlined;

    case 'sports':
      return Icons.sports_soccer_outlined;

    default:
      return Icons.category_outlined;
  }
}

String _shortCategory(String category) {
  if (category.length <= 9) {
    return category;
  }

  return '${category.substring(0, 8)}…';
}

String _compactCurrency(double value) {
  if (value >= 10000000) {
    return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
  }

  if (value >= 100000) {
    return '₹${(value / 100000).toStringAsFixed(1)}L';
  }

  if (value >= 1000) {
    return '₹${(value / 1000).toStringAsFixed(1)}K';
  }

  return '₹${value.toStringAsFixed(0)}';
}
