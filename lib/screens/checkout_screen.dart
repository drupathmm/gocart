import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../models/checkout_exception.dart';
import '../models/demo_order.dart';
import '../providers/cart_provider.dart';
import '../providers/order_provider.dart';
import '../services/checkout_attempt_store.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'order_history_screen.dart';
import 'razorpay_payment_screen.dart';
import 'user_home_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isPlacingOrder = false;
  final _offerController = TextEditingController();
  String? _restoredCartFingerprint;
  String? _restoringCartFingerprint;

  @override
  void dispose() {
    _offerController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (_isPlacingOrder) return;
    final buyerId = Supabase.instance.client.auth.currentUser?.id;
    if (buyerId == null) {
      _showMessage('Please sign in again before checkout.');
      return;
    }

    setState(() => _isPlacingOrder = true);
    try {
      final items = ref.read(cartProvider).asData?.value ?? const [];
      final cartFingerprint = CheckoutAttemptStore.cartFingerprint(
        items.map(
          (item) => (
            cartItemId: item.id,
            productId: item.productId,
            quantity: item.quantity,
          ),
        ),
      );
      final attemptStore = ref.read(checkoutAttemptStoreProvider);
      final attempt = await attemptStore.prepare(
        userId: buyerId,
        cartFingerprint: cartFingerprint,
        offerCode: _offerController.text,
      );
      final receipt = await ref
          .read(orderServiceProvider)
          .checkout(
            expectedBuyerId: buyerId,
            idempotencyKey: attempt.idempotencyKey,
            offerCode: attempt.offerCode,
          );
      await attemptStore.markCompleted(
        userId: buyerId,
        idempotencyKey: attempt.idempotencyKey,
      );

      if (!mounted) return;
      try {
        await ref.read(cartProvider.notifier).refreshCart();
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'Order was created, but the cart refresh failed: ${error.runtimeType}',
          );
        }
      }
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RazorpayPaymentScreen(orderId: receipt.id),
        ),
      );
      if (!mounted) return;
      ref.invalidate(myOrdersProvider(buyerId));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is CheckoutAttemptPersistenceException
          ? error.toString()
          : error is CheckoutException
          ? error.message
          : error is FunctionException
          ? CheckoutException.fromCode(error.details?.toString() ?? '').message
          : error is PostgrestException
          ? 'Could not complete checkout. Please try again.'
          : error is FormatException
          ? 'The checkout details are invalid. Please review them and try again.'
          : 'Could not complete checkout. Please try again.';
      _showMessage(message.isEmpty ? 'Could not complete checkout.' : message);
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        backgroundColor: GoCartTheme.canvas,
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: const Text('Sign in to continue'),
          ),
        ),
      );
    }

    final cartAsync = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: cartAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: GoCartTheme.brand),
          ),
          error: (error, stack) => _CheckoutMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your cart',
            message: 'Refresh the cart and try checkout again.',
            action: TextButton.icon(
              onPressed: () => ref.read(cartProvider.notifier).refreshCart(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _CheckoutMessage(
                icon: Icons.shopping_bag_outlined,
                title: 'Your cart is empty',
                message: 'Add something to your cart before checking out.',
                action: FilledButton.tonal(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const UserHomeScreen()),
                    (route) => false,
                  ),
                  child: const Text('Continue shopping'),
                ),
              );
            }
            final cartFingerprint = CheckoutAttemptStore.cartFingerprint(
              items.map(
                (item) => (
                  cartItemId: item.id,
                  productId: item.productId,
                  quantity: item.quantity,
                ),
              ),
            );
            if (_restoredCartFingerprint != cartFingerprint) {
              if (_restoringCartFingerprint != cartFingerprint) {
                _restoringCartFingerprint = cartFingerprint;
                _restoreOfferDraft(userId, cartFingerprint);
              }
              return const Center(
                child: CircularProgressIndicator(color: GoCartTheme.brand),
              );
            }
            return _CheckoutContent(
              items: items,
              isPlacingOrder: _isPlacingOrder,
              offerController: _offerController,
              onPlaceOrderWithPayment: _placeOrder,
              canUseRazorpay:
                  !kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS),
            );
          },
        ),
      ),
    );
  }

  Future<void> _restoreOfferDraft(String userId, String cartFingerprint) async {
    try {
      final attempt = await ref
          .read(checkoutAttemptStoreProvider)
          .pendingForCart(userId: userId, cartFingerprint: cartFingerprint);
      if (!mounted) return;
      if (attempt != null && _offerController.text.isEmpty) {
        _offerController.text = attempt.offerCode;
      }
    } catch (_) {
      // Checkout preparation will show a friendly storage error if saving the
      // retry key itself is unavailable. Do not display raw storage details.
    } finally {
      if (mounted) {
        setState(() {
          _restoredCartFingerprint = cartFingerprint;
          _restoringCartFingerprint = null;
        });
      }
    }
  }
}

class _CheckoutContent extends StatelessWidget {
  final List<CartItem> items;
  final bool isPlacingOrder;
  final TextEditingController offerController;
  final VoidCallback onPlaceOrderWithPayment;
  final bool canUseRazorpay;

  const _CheckoutContent({
    required this.items,
    required this.isPlacingOrder,
    required this.offerController,
    required this.onPlaceOrderWithPayment,
    required this.canUseRazorpay,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.totalPrice);
    final subtotal = items.fold<double>(
      0,
      (sum, item) => sum + item.originalTotalPrice,
    );
    final savings = items.fold<double>(
      0,
      (sum, item) => sum + item.totalSavings,
    );
    final unavailable = items.any(
      (item) =>
          item.product == null ||
          item.product!.stock <= 0 ||
          item.quantity > item.product!.stock,
    );
    final canPlaceOrder = !unavailable && total > 0 && !isPlacingOrder;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final summary = _CheckoutSummary(
      total: total,
      subtotal: subtotal,
      savings: savings,
      canPlaceOrder: canPlaceOrder,
      isPlacingOrder: isPlacingOrder,
      offerController: offerController,
      onPlaceOrderWithPayment: onPlaceOrderWithPayment,
      canUseRazorpay: canUseRazorpay,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 18, 20, isWide ? 32 : 18, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review your order',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'Your order total is calculated again securely when you place it.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              _PaymentAvailabilityBanner(canUseRazorpay: canUseRazorpay),
              const SizedBox(height: 18),
              if (unavailable) ...[
                const _StockWarning(),
                const SizedBox(height: 16),
              ],
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _ItemsCard(items: items)),
                    const SizedBox(width: 20),
                    SizedBox(width: 350, child: summary),
                  ],
                )
              else ...[
                _ItemsCard(items: items),
                const SizedBox(height: 16),
                summary,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentAvailabilityBanner extends StatelessWidget {
  final bool canUseRazorpay;

  const _PaymentAvailabilityBanner({required this.canUseRazorpay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: canUseRazorpay
            ? const Color(0xFFEAF6EE)
            : const Color(0xFFFFF2E2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: canUseRazorpay
              ? const Color(0xFFB5DCC2)
              : const Color(0xFFECC99D),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            canUseRazorpay ? Icons.lock_outline : Icons.info_outline,
            color: GoCartTheme.brand,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canUseRazorpay
                      ? 'Razorpay test checkout'
                      : 'Browser checkout is unavailable',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  canUseRazorpay
                      ? 'No real payment will be taken. GoCart confirms payment with the server before marking your order paid.'
                      : 'Razorpay checkout is currently supported in the Android and iOS apps. Your order has not been submitted.',
                  style: const TextStyle(height: 1.4, color: Color(0xFF685652)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockWarning extends StatelessWidget {
  const _StockWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3C9C9)),
      ),
      child: const Text(
        'One or more products are unavailable or have less stock than your cart quantity. Update your cart to continue.',
        style: TextStyle(color: Color(0xFF9D3030), height: 1.4),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final List<CartItem> items;

  const _ItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items (${items.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final item in items) ...[
            if (item.product != null)
              _OrderLine(
                name: item.product!.name,
                detail:
                    '${item.quantity} × ₹${item.product!.offerPrice.toStringAsFixed(2)}',
                total: item.totalPrice,
              )
            else
              _OrderLine(
                name: 'Unavailable product',
                detail: 'Remove from cart',
                total: 0,
              ),
            if (item != items.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  final String name;
  final String detail;
  final double total;

  const _OrderLine({
    required this.name,
    required this.detail,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF5E8E4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shopping_bag_outlined,
            color: GoCartTheme.brand,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '₹${total.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _CheckoutSummary extends StatelessWidget {
  final double total;
  final double subtotal;
  final double savings;
  final bool canPlaceOrder;
  final bool isPlacingOrder;
  final TextEditingController offerController;
  final VoidCallback onPlaceOrderWithPayment;
  final bool canUseRazorpay;

  const _CheckoutSummary({
    required this.total,
    required this.subtotal,
    required this.savings,
    required this.canPlaceOrder,
    required this.isPlacingOrder,
    required this.offerController,
    required this.onPlaceOrderWithPayment,
    required this.canUseRazorpay,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Payment summary',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _MoneyRow(label: 'Subtotal', value: subtotal),
          if (savings > 0) ...[
            const SizedBox(height: 9),
            _MoneyRow(label: 'Savings', value: -savings, isSaving: true),
          ],
          const SizedBox(height: 12),
          _MoneyRow(
            label: 'Payment method',
            valueText: canUseRazorpay ? 'Razorpay test mode' : 'Unavailable',
          ),
          const Divider(height: 24),
          _MoneyRow(label: 'Total', value: total, isTotal: true),
          const SizedBox(height: 14),
          TextField(
            controller: offerController,
            enabled: !isPlacingOrder,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Offer code (optional)',
              hintText: 'SAVE10',
            ),
          ),
          const SizedBox(height: 18),
          if (canUseRazorpay) ...[
            FilledButton.icon(
              onPressed: canPlaceOrder ? onPlaceOrderWithPayment : null,
              icon: isPlacingOrder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(
                isPlacingOrder ? 'Preparing payment…' : 'Pay with Razorpay',
              ),
            ),
          ],
          const SizedBox(height: 9),
          Text(
            canUseRazorpay
                ? 'The order is confirmed only after GoCart verifies the payment.'
                : 'Use the Android or iOS app to complete a Razorpay test payment.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final double? value;
  final String? valueText;
  final bool isSaving;
  final bool isTotal;

  const _MoneyRow({
    required this.label,
    this.value,
    this.valueText,
    this.isSaving = false,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayed = valueText ?? '₹${(value ?? 0).abs().toStringAsFixed(2)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        Text(
          isSaving && value != null ? '−$displayed' : displayed,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: isTotal ? 18 : 14,
            color: isSaving ? const Color(0xFF27804F) : GoCartTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GoCartTheme.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A541B3D),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CheckoutMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _CheckoutMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 50, color: GoCartTheme.brand),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class DemoOrderSuccessScreen extends StatelessWidget {
  final DemoOrderReceipt receipt;

  const DemoOrderSuccessScreen({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final status = receipt.paymentStatus;
    final paymentMessage = status == null || status.isEmpty
        ? 'No real payment was taken. The database did not return a payment status.'
        : status == 'unpaid'
        ? 'No real payment was taken. The database records this order as unpaid.'
        : 'No real payment was taken. The database records payment status as ${status.replaceAll('_', ' ')}.';

    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _CardShell(
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE7F5EC),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 42,
                        color: Color(0xFF24804D),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Order created',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(paymentMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    _MoneyRow(
                      label: 'Order total',
                      value: receipt.total,
                      isTotal: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Order ${receipt.id}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OrderHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('View my orders'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserHomeScreen(),
                        ),
                        (route) => false,
                      ),
                      child: const Text('Continue shopping'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
