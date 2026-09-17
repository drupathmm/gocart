import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';

// ============================================================================
// GOCART BRAND COLORS
// ============================================================================

class _GoCartColors {
  static const Color purple = Color(0xFF6F4B9B);
  static const Color darkPurple = Color(0xFF4D2D73);
  static const Color lightPurple = Color(0xFFE9D8FF);
  static const Color softPurple = Color(0xFFF4ECFA);
  static const Color pearlWhite = Color(0xFFFFF9FF);
}

// ============================================================================
// PRODUCT DETAIL SCREEN
// ============================================================================

class ProductDetailScreen extends ConsumerWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOutOfStock = product.stock == 0;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 850;

    return Scaffold(
      backgroundColor: _GoCartColors.pearlWhite,

      appBar: AppBar(
        backgroundColor: _GoCartColors.pearlWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'Product Details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),

        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              Navigator.pop(context);
            },
          ),

          const SizedBox(width: 8),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 36 : 18,
            12,
            isDesktop ? 36 : 18,
            40,
          ),

          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),

              child: isDesktop
                  ? _DesktopLayout(
                      product: product,
                      isOutOfStock: isOutOfStock,
                      ref: ref,
                    )
                  : _MobileLayout(
                      product: product,
                      isOutOfStock: isOutOfStock,
                      ref: ref,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DESKTOP LAYOUT
// ============================================================================

class _DesktopLayout extends StatelessWidget {
  final Product product;
  final bool isOutOfStock;
  final WidgetRef ref;

  const _DesktopLayout({
    required this.product,
    required this.isOutOfStock,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Breadcrumb
        _Breadcrumb(),

        const SizedBox(height: 18),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==============================================================
            // LEFT: IMAGE
            // ==============================================================
            Expanded(flex: 11, child: _ProductGallery(product: product)),

            const SizedBox(width: 34),

            // ==============================================================
            // RIGHT: DETAILS
            // ==============================================================
            Expanded(
              flex: 9,
              child: _ProductInformation(
                product: product,
                isOutOfStock: isOutOfStock,
                ref: ref,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// MOBILE LAYOUT
// ============================================================================

class _MobileLayout extends StatelessWidget {
  final Product product;
  final bool isOutOfStock;
  final WidgetRef ref;

  const _MobileLayout({
    required this.product,
    required this.isOutOfStock,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Breadcrumb(),

        const SizedBox(height: 14),

        _ProductGallery(product: product),

        const SizedBox(height: 24),

        _ProductInformation(
          product: product,
          isOutOfStock: isOutOfStock,
          ref: ref,
        ),
      ],
    );
  }
}

// ============================================================================
// BREADCRUMB
// ============================================================================

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Home',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),

        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Colors.grey.shade500,
        ),

        Text(
          'Products',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),

        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Colors.grey.shade500,
        ),

        const Text(
          'Product Details',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _GoCartColors.darkPurple,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PRODUCT GALLERY
// ============================================================================

class _ProductGallery extends StatelessWidget {
  final Product product;

  const _ProductGallery({required this.product});

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl?.trim();

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ================================================================
        // MAIN IMAGE
        // ================================================================
        Container(
          width: double.infinity,

          height: 500,

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),

            color: _GoCartColors.darkPurple,

            boxShadow: [
              BoxShadow(
                color: _GoCartColors.purple.withValues(alpha: 0.12),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),

            child: hasImage
                ? Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: double.infinity,

                    // Contain keeps the complete product
                    // visible instead of brutally cropping it.
                    fit: BoxFit.contain,

                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      );
                    },

                    errorBuilder: (context, error, stackTrace) {
                      return const _ImageError();
                    },
                  )
                : const _ImagePlaceholder(),
          ),
        ),

        const SizedBox(height: 12),

        // ================================================================
        // IMAGE INDICATOR
        // ================================================================
        Row(
          children: [
            Container(
              width: 76,
              height: 64,

              decoration: BoxDecoration(
                color: _GoCartColors.softPurple,

                borderRadius: BorderRadius.circular(12),

                border: Border.all(color: _GoCartColors.purple, width: 2),
              ),

              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),

                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image_outlined,
                            color: _GoCartColors.purple,
                          );
                        },
                      )
                    : const Icon(
                        Icons.image_outlined,
                        color: _GoCartColors.purple,
                      ),
              ),
            ),

            const SizedBox(width: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

              decoration: BoxDecoration(
                color: _GoCartColors.softPurple,
                borderRadius: BorderRadius.circular(20),
              ),

              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 15,
                    color: _GoCartColors.purple,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Product image',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _GoCartColors.darkPurple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// PRODUCT INFORMATION
// ============================================================================

class _ProductInformation extends StatelessWidget {
  final Product product;
  final bool isOutOfStock;
  final WidgetRef ref;

  const _ProductInformation({
    required this.product,
    required this.isOutOfStock,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final description = product.description.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ================================================================
        // STOCK BADGE
        // ================================================================
        _StockBadge(stock: product.stock),

        const SizedBox(height: 16),

        // ================================================================
        // PRODUCT NAME
        // ================================================================
        Text(
          product.name,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),

        const SizedBox(height: 12),

        // ================================================================
        // PRICE
        // ================================================================
        Text(
          '₹${product.price.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _GoCartColors.purple,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 22),

        // ================================================================
        // PRODUCT META
        // ================================================================
        _ProductMeta(product: product),

        const SizedBox(height: 22),

        // ================================================================
        // DESCRIPTION
        // ================================================================
        _DescriptionCard(description: description),

        const SizedBox(height: 22),

        // ================================================================
        // ADD TO CART
        // ================================================================
        _AddToCartButton(
          product: product,
          isOutOfStock: isOutOfStock,
          ref: ref,
        ),

        const SizedBox(height: 14),

        // ================================================================
        // SMALL INFORMATION
        // ================================================================
        Container(
          width: double.infinity,

          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),

          decoration: BoxDecoration(
            color: _GoCartColors.softPurple,
            borderRadius: BorderRadius.circular(14),
          ),

          child: Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 19,
                color: _GoCartColors.purple,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  isOutOfStock
                      ? 'This product is currently unavailable.'
                      : 'Available now. Add it to your cart before stock runs out.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _GoCartColors.darkPurple,
                  ),
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
// STOCK BADGE
// ============================================================================

class _StockBadge extends StatelessWidget {
  final int stock;

  const _StockBadge({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isAvailable = stock > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),

      decoration: BoxDecoration(
        color: isAvailable ? _GoCartColors.lightPurple : Colors.red.shade50,

        borderRadius: BorderRadius.circular(10),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAvailable
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
            size: 16,
            color: isAvailable ? _GoCartColors.darkPurple : Colors.red.shade600,
          ),

          const SizedBox(width: 6),

          Text(
            isAvailable ? '$stock available' : 'Out of stock',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isAvailable
                  ? _GoCartColors.darkPurple
                  : Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRODUCT META
// ============================================================================

class _ProductMeta extends StatelessWidget {
  final Product product;

  const _ProductMeta({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Row(
        children: [
          Expanded(
            child: _MetaItem(
              icon: Icons.inventory_2_outlined,
              title: 'Stock',
              value: '${product.stock}',
            ),
          ),

          Container(width: 1, height: 38, color: Colors.grey.shade200),

          Expanded(
            child: _MetaItem(
              icon: Icons.sell_outlined,
              title: 'Price',
              value: '₹${product.price.toStringAsFixed(0)}',
            ),
          ),

          Container(width: 1, height: 38, color: Colors.grey.shade200),

          Expanded(
            child: _MetaItem(
              icon: Icons.shopping_bag_outlined,
              title: 'GoCart',
              value: 'Available',
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// META ITEM
// ============================================================================

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MetaItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: _GoCartColors.purple),

        const SizedBox(height: 6),

        Text(
          title,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),

        const SizedBox(height: 2),

        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ============================================================================
// DESCRIPTION CARD
// ============================================================================

class _DescriptionCard extends StatelessWidget {
  final String description;

  const _DescriptionCard({required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: _GoCartColors.softPurple,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: _GoCartColors.lightPurple),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,

                decoration: BoxDecoration(
                  color: _GoCartColors.purple,
                  borderRadius: BorderRadius.circular(10),
                ),

                child: const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),

              const SizedBox(width: 10),

              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _GoCartColors.darkPurple,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            description.isEmpty ? 'No description available.' : description,
            style: TextStyle(
              fontSize: 13,
              height: 1.65,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ADD TO CART BUTTON
// ============================================================================

class _AddToCartButton extends StatefulWidget {
  final Product product;
  final bool isOutOfStock;
  final WidgetRef ref;

  const _AddToCartButton({
    required this.product,
    required this.isOutOfStock,
    required this.ref,
  });

  @override
  State<_AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<_AddToCartButton> {
  bool isAdding = false;

  Future<void> _addToCart() async {
    if (widget.isOutOfStock || isAdding) {
      return;
    }

    setState(() {
      isAdding = true;
    });

    try {
      await widget.ref
          .read(cartProvider.notifier)
          .addToCart(productId: widget.product.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,

          backgroundColor: _GoCartColors.darkPurple,

          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),

              const SizedBox(width: 10),

              Expanded(child: Text('${widget.product.name} added to cart')),
            ],
          ),

          action: SnackBarAction(
            label: 'VIEW CART',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,

          backgroundColor: Colors.red.shade700,

          content: Text('Failed to add to cart: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isAdding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,

      child: FilledButton.icon(
        onPressed: widget.isOutOfStock ? null : _addToCart,

        style: FilledButton.styleFrom(
          backgroundColor: _GoCartColors.purple,

          foregroundColor: Colors.white,

          disabledBackgroundColor: Colors.grey.shade300,

          disabledForegroundColor: Colors.grey.shade600,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),

          elevation: 0,
        ),

        icon: isAdding
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.shopping_cart_rounded),

        label: Text(
          isAdding
              ? 'Adding to Cart...'
              : widget.isOutOfStock
              ? 'Out of Stock'
              : 'Add to Cart',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ============================================================================
// IMAGE PLACEHOLDER
// ============================================================================

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _GoCartColors.darkPurple,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 90, color: Colors.white70),
      ),
    );
  }
}

// ============================================================================
// IMAGE ERROR
// ============================================================================

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _GoCartColors.darkPurple,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 70, color: Colors.white70),
            SizedBox(height: 10),
            Text(
              'Image unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
