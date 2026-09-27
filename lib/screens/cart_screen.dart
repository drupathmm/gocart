import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';
import 'product_detail_screen.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  static const Color purple = Color(0xFF541B3D);
  static const Color pearlWhite = Color(0xFFFBF6F0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;

    // ------------------------------------------------------------
    // GUEST CART
    // ------------------------------------------------------------
    // Guests are allowed to open the cart.
    // We simply don't query the private cart_items table.
    // ------------------------------------------------------------
    if (user == null) {
      return const _GuestCartView();
    }

    final cartAsync = ref.watch(cartProvider);
    final cartTotal = ref.watch(cartTotalProvider);
    final cartSavings = ref.watch(cartSavingsProvider);

    final showBackButton = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: pearlWhite,
      appBar: showBackButton
          ? AppBar(
              backgroundColor: pearlWhite,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                tooltip: 'Back to Profile',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              title: const Text(
                'Your Cart',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          color: purple,
          onRefresh: () {
            return ref.read(cartProvider.notifier).refreshCart();
          },
          child: cartAsync.when(
            loading: () {
              return const _LoadingView();
            },
            error: (error, stackTrace) {
              debugPrint('Cart error: $error');

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

              return _CartContent(
                items: items,
                total: cartTotal,
                savings: cartSavings,
                ref: ref,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// GUEST CART
// ============================================================================

class _GuestCartView extends StatelessWidget {
  const _GuestCartView();

  static const Color purple = Color(0xFF541B3D);
  static const Color pearlWhite = Color(0xFFFBF6F0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pearlWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),

                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4E8E7),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      size: 50,
                      color: purple,
                    ),
                  ),

                  const SizedBox(height: 26),

                  const Text(
                    'Your cart is empty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'You can browse products as a guest. '
                    'Login or create an account to add products '
                    'and save them to your cart.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 28),

                  FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Login / Sign Up',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LOGGED-IN CART CONTENT
// ============================================================================

class _CartContent extends StatelessWidget {
  final List<CartItem> items;
  final double total;
  final double savings;
  final WidgetRef ref;

  const _CartContent({
    required this.items,
    required this.total,
    required this.savings,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 980;
        final horizontalPadding = isDesktop ? 32.0 : 18.0;
        final itemCards = items
            .map((item) => _CartItemCard(item: item, ref: ref))
            .toList();
        final checkoutButton = SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutScreen()),
            ),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Proceed to Checkout'),
          ),
        );

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isDesktop ? 36 : 24,
            horizontalPadding,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Cart',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${items.length} product${items.length == 1 ? '' : 's'} in your cart',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (savings > 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF8F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD9EFDF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_offer_outlined,
                              size: 20,
                              color: Color(0xFF258453),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You are saving ₹${savings.toStringAsFixed(2)} on this order.',
                                style: const TextStyle(
                                  color: Color(0xFF258453),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: itemCards)),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 320,
                            child: Column(
                              children: [
                                _OrderSummary(total: total, savings: savings),
                                const SizedBox(height: 14),
                                checkoutButton,
                                const SizedBox(height: 12),
                                const _CheckoutNote(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      ...itemCards,
                      const SizedBox(height: 8),
                      _OrderSummary(total: total, savings: savings),
                      const SizedBox(height: 14),
                      checkoutButton,
                      const SizedBox(height: 12),
                      const _CheckoutNote(),
                    ],
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

class _CheckoutNote extends StatelessWidget {
  const _CheckoutNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Demo checkout only · no real payment will be taken',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CART ITEM
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

    final hasDiscount = product.hasDiscount;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(product: product),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            product.category,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '₹${product.offerPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF541B3D),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (hasDiscount) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '₹${product.originalPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Decrease quantity',
                          onPressed: item.canDecreaseQuantity
                              ? () {
                                  ref
                                      .read(cartProvider.notifier)
                                      .decreaseQuantity(item.id);
                                }
                              : null,
                          icon: const Icon(Icons.remove_rounded, size: 18),
                        ),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: item.canIncreaseQuantity
                              ? 'Increase quantity'
                              : 'Maximum available stock',
                          onPressed: item.canIncreaseQuantity
                              ? () {
                                  ref
                                      .read(cartProvider.notifier)
                                      .increaseQuantity(item.id);
                                }
                              : null,
                          icon: const Icon(Icons.add_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Remove from cart',
                    onPressed: () {
                      ref.read(cartProvider.notifier).removeFromCart(item.id);
                    },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
              child: Text(
                item.isOutOfStock
                    ? 'Out of stock'
                    : '${product.stock} available',
                style: TextStyle(
                  fontSize: 11,
                  color: item.isOutOfStock
                      ? Colors.red.shade600
                      : Colors.grey.shade600,
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
// PRODUCT IMAGE
// ============================================================================

class _ProductImage extends StatelessWidget {
  final String? imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = const Color(0xFFF4EBE7);

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(Icons.image_outlined, size: 36, color: Colors.grey),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        imageUrl!,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 96,
            height: 96,
            color: placeholderColor,
            child: const Icon(
              Icons.broken_image_outlined,
              size: 34,
              color: Colors.grey,
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// ORDER SUMMARY
// ============================================================================

class _OrderSummary extends StatelessWidget {
  final double total;
  final double savings;

  const _OrderSummary({required this.total, required this.savings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Subtotal', value: '₹${total.toStringAsFixed(2)}'),

          if (savings > 0) ...[
            const SizedBox(height: 10),
            _SummaryRow(
              label: 'You save',
              value: '₹${savings.toStringAsFixed(2)}',
              valueColor: Colors.green.shade700,
            ),
          ],

          const SizedBox(height: 14),

          Divider(color: Colors.grey.shade200),

          const SizedBox(height: 14),

          _SummaryRow(
            label: 'Total',
            value: '₹${total.toStringAsFixed(2)}',
            large: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool large;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: large ? 17 : 14,
            fontWeight: large ? FontWeight.w800 : FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 19 : 14,
            fontWeight: FontWeight.w800,
            color:
                valueColor ??
                (large ? const Color(0xFF541B3D) : Colors.black87),
          ),
        ),
      ],
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 150),

        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFF4E8E7),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: Color(0xFF541B3D),
            ),
          ),
        ),

        const SizedBox(height: 22),

        const Text(
          'Your cart is empty',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Text(
          'Add products to your cart and they will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
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
        Center(child: CircularProgressIndicator(color: Color(0xFF541B3D))),
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
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 150),

        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.red.shade600,
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
          'Something went wrong while loading your cart.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
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
