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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.storefront_rounded,
                size: 21,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'GoCart',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileScreen()),
              );
            },
            icon: const Icon(Icons.account_circle_outlined, size: 28),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(myProductsProvider.notifier).refreshProducts();
        },
        child: productsAsync.when(
          loading: () {
            return const _LoadingView();
          },
          error: (error, stackTrace) {
            return _ErrorView(
              onRetry: () {
                ref.read(myProductsProvider.notifier).refreshProducts();
              },
            );
          },
          data: (products) {
            return _DashboardContent(
              products: products,
              onAddProduct: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddProductScreen()),
                );

                if (!context.mounted) {
                  return;
                }

                ref.read(myProductsProvider.notifier).refreshProducts();
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

                ref.read(myProductsProvider.notifier).refreshProducts();
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
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Product',
            style: TextStyle(fontWeight: FontWeight.w700),
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
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
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

class _DashboardContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final totalProducts = products.length;

    final totalStock = products.fold<int>(
      0,
      (total, product) => total + product.stock,
    );

    final lowStockCount = products.where((product) {
      return product.stock > 0 && product.stock <= 5;
    }).length;

    final outOfStockCount = products.where((product) {
      return product.stock == 0;
    }).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --------------------------------------------
                // HEADER
                // --------------------------------------------
                Text(
                  'Merchant Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Manage your products and keep your store up to date.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                // --------------------------------------------
                // QUICK ACTION
                // --------------------------------------------
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.add_business_rounded,
                          color: colorScheme.onPrimary,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add a new product',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Add products to your store catalog.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: onAddProduct,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // --------------------------------------------
                // STATISTICS
                // --------------------------------------------
                Text(
                  'Store Overview',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 12),

                _StatsGrid(
                  totalProducts: totalProducts,
                  totalStock: totalStock,
                  lowStockCount: lowStockCount,
                  outOfStockCount: outOfStockCount,
                ),

                const SizedBox(height: 30),

                // --------------------------------------------
                // PRODUCTS HEADER
                // --------------------------------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Products',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            products.isEmpty
                                ? 'Your product catalog is empty.'
                                : '$totalProducts ${totalProducts == 1 ? 'product' : 'products'} in your catalog',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // --------------------------------------------
                // PRODUCT LIST
                // --------------------------------------------
                if (products.isEmpty)
                  _EmptyProductsView(onAddProduct: onAddProduct)
                else
                  ...products.map((product) {
                    return _ProductCard(
                      product: product,
                      onEdit: () {
                        onEditProduct(product);
                      },
                      onDelete: () {
                        onDeleteProduct(product);
                      },
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final int totalProducts;
  final int totalStock;
  final int lowStockCount;
  final int outOfStockCount;

  const _StatsGrid({
    required this.totalProducts,
    required this.totalStock,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _StatCard(
          icon: Icons.inventory_2_outlined,
          title: 'Products',
          value: '$totalProducts',
        ),
        _StatCard(
          icon: Icons.warehouse_outlined,
          title: 'Total Stock',
          value: '$totalStock',
        ),
        _StatCard(
          icon: Icons.warning_amber_rounded,
          title: 'Low Stock',
          value: '$lowStockCount',
          highlight: lowStockCount > 0,
        ),
        _StatCard(
          icon: Icons.remove_shopping_cart_outlined,
          title: 'Out of Stock',
          value: '$outOfStockCount',
          highlight: outOfStockCount > 0,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool highlight;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final iconColor = highlight ? colorScheme.error : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;

    final stockStatus = _getStockStatus(context, product.stock);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ProductImage(imageUrl: product.imageUrl),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  '₹${product.price.toStringAsFixed(2)}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: stockStatus.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${stockStatus.label} • ${product.stock} units',
                    style: TextStyle(
                      fontSize: 12,
                      color: stockStatus.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          PopupMenuButton<String>(
            tooltip: 'Product actions',
            icon: const Icon(Icons.more_vert_rounded),
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
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      const Text('Delete'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  _StockStatus _getStockStatus(BuildContext context, int stock) {
    final colorScheme = Theme.of(context).colorScheme;

    if (stock == 0) {
      return _StockStatus(label: 'Out of stock', color: colorScheme.error);
    }

    if (stock <= 5) {
      return _StockStatus(label: 'Low stock', color: Colors.orange);
    }

    return _StockStatus(label: 'In stock', color: Colors.green);
  }
}

class _StockStatus {
  final String label;
  final Color color;

  const _StockStatus({required this.label, required this.color});
}

class _ProductImage extends StatelessWidget {
  final String? imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: placeholderColor,
        ),
        child: const Icon(Icons.image_outlined, size: 34),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        imageUrl!,
        width: 82,
        height: 82,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 82,
            height: 82,
            color: placeholderColor,
            child: const Icon(Icons.broken_image_outlined, size: 30),
          );
        },
      ),
    );
  }
}

class _EmptyProductsView extends StatelessWidget {
  final VoidCallback onAddProduct;

  const _EmptyProductsView({required this.onAddProduct});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 34),
          ),

          const SizedBox(height: 18),

          Text(
            'No products yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 7),

          Text(
            'Add your first product to start building your store catalog.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: onAddProduct,
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 180),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading your store...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),

        Center(
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: colorScheme.onErrorContainer,
            ),
          ),
        ),

        const SizedBox(height: 22),

        Text(
          'Could not load products',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),

        const SizedBox(height: 8),

        Text(
          'Something went wrong while loading your store.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),

        const SizedBox(height: 20),

        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ),
      ],
    );
  }
}
