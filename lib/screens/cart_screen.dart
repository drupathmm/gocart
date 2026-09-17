import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';
import '../providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartAsync = ref.watch(cartProvider);
    final cartTotal = ref.watch(cartTotalProvider);

    return RefreshIndicator(
      onRefresh: () {
        return ref.read(cartProvider.notifier).refreshCart();
      },
      child: cartAsync.when(
        loading: () {
          return const _LoadingView();
        },
        error: (error, stackTrace) {
          return _ErrorView(
            onRetry: () {
              ref.read(cartProvider.notifier).refreshCart();
            },
          );
        },
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyCartView();
          }

          return _CartContent(items: items, total: cartTotal, ref: ref);
        },
      ),
    );
  }
}

// ============================================================================
// CART CONTENT
// ============================================================================

class _CartContent extends StatelessWidget {
  final List<CartItem> items;
  final double total;
  final WidgetRef ref;

  const _CartContent({
    required this.items,
    required this.total,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 28 : 20,
            24,
            isDesktop ? 28 : 20,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ========================================================
                    // HEADER
                    // ========================================================
                    Text(
                      'Shopping Cart',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${items.length} item${items.length == 1 ? '' : 's'} in your cart',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 26),

                    // ========================================================
                    // DESKTOP
                    // ========================================================
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --------------------------------------------------
                          // CART ITEMS
                          // --------------------------------------------------
                          Expanded(
                            flex: 7,
                            child: _CartItemsList(items: items, ref: ref),
                          ),

                          const SizedBox(width: 24),

                          // --------------------------------------------------
                          // SUMMARY
                          // --------------------------------------------------
                          SizedBox(
                            width: 340,
                            child: _OrderSummaryCard(total: total),
                          ),
                        ],
                      )
                    // ========================================================
                    // MOBILE / TABLET
                    // ========================================================
                    else
                      Column(
                        children: [
                          _CartItemsList(items: items, ref: ref),

                          const SizedBox(height: 20),

                          _OrderSummaryCard(total: total),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// CART ITEMS LIST
// ============================================================================

class _CartItemsList extends StatelessWidget {
  final List<CartItem> items;
  final WidgetRef ref;

  const _CartItemsList({required this.items, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [for (final item in items) _CartItemCard(item: item, ref: ref)],
    );
  }
}

// ============================================================================
// CART ITEM CARD
// ============================================================================

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final WidgetRef ref;

  const _CartItemCard({required this.item, required this.ref});

  @override
  Widget build(BuildContext context) {
    final product = item.product;

    if (product == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    final itemTotal = product.price * item.quantity;

    final isAtMaxStock = item.quantity >= product.stock;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ================================================================
          // PRODUCT IMAGE
          // ================================================================
          _ProductImage(imageUrl: product.imageUrl),

          const SizedBox(width: 16),

          // ================================================================
          // PRODUCT DETAILS
          // ================================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  '₹${product.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),

                const SizedBox(height: 7),

                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${product.stock} available',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ==========================================================
                // QUANTITY
                // ==========================================================
                Row(
                  children: [
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QuantityButton(
                            icon: Icons.remove_rounded,
                            enabled: item.quantity > 1,
                            onPressed: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(
                                    cartItemId: item.id,
                                    quantity: item.quantity - 1,
                                  );
                            },
                          ),

                          Container(
                            constraints: const BoxConstraints(minWidth: 34),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.quantity}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          _QuantityButton(
                            icon: Icons.add_rounded,
                            enabled: !isAtMaxStock,
                            onPressed: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(
                                    cartItemId: item.id,
                                    quantity: item.quantity + 1,
                                  );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 14),

                    // ========================================================
                    // ITEM TOTAL
                    // ========================================================
                    Text(
                      '₹${itemTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ================================================================
          // DELETE
          // ================================================================
          IconButton(
            tooltip: 'Remove from cart',
            onPressed: () {
              _showRemoveDialog(context, ref, item, product.name);
            },
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.errorContainer.withValues(
                alpha: 0.55,
              ),
            ),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
    String productName,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove item?'),
          content: Text('Remove "$productName" from your cart?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                ref.read(cartProvider.notifier).removeFromCart(item.id);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// QUANTITY BUTTON
// ============================================================================

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _QuantityButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 17),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
      color: colorScheme.onSurface,
      disabledColor: colorScheme.onSurface.withValues(alpha: 0.25),
    );
  }
}

// ============================================================================
// ORDER SUMMARY
// ============================================================================

class _OrderSummaryCard extends StatelessWidget {
  final double total;

  const _OrderSummaryCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // ================================================================
          // TITLE
          // ================================================================
          Text(
            'Order Summary',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 22),

          // ================================================================
          // SUBTOTAL
          // ================================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              Text(
                '₹${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ================================================================
          // DELIVERY
          // ================================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Delivery',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              Text(
                'FREE',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Divider(color: colorScheme.outlineVariant),

          const SizedBox(height: 18),

          // ================================================================
          // TOTAL
          // ================================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                '₹${total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ================================================================
          // CHECKOUT
          // ================================================================
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Checkout will be available soon.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text(
                'Proceed to Checkout',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ================================================================
          // SECURE CHECKOUT NOTE
          // ================================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Secure checkout',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
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

    final placeholderColor = colorScheme.surfaceContainerHighest;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        width: 105,
        height: 105,
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        imageUrl!,
        width: 105,
        height: 105,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 105,
            height: 105,
            color: placeholderColor,
            child: Icon(
              Icons.broken_image_outlined,
              size: 38,
              color: colorScheme.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// EMPTY CART
// ============================================================================

class _EmptyCartView extends StatelessWidget {
  const _EmptyCartView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 110),

        Center(
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 52,
              color: colorScheme.primary,
            ),
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Your cart is empty',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Text(
          'Add products to your cart and they will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 280),
        Center(child: CircularProgressIndicator()),
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
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 130),

        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: colorScheme.error,
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Could not load your cart',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Text(
          'Please try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
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
