import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/demo_order.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'user_home_screen.dart';
import 'razorpay_payment_screen.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authUserIdProvider);
    final buyerId =
        authState.asData?.value ??
        Supabase.instance.client.auth.currentUser?.id;

    if (buyerId == null) {
      return Scaffold(
        backgroundColor: GoCartTheme.canvas,
        appBar: AppBar(title: const Text('My Orders')),
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: const Text('Sign in to view orders'),
          ),
        ),
      );
    }

    final orders = ref.watch(myOrdersProvider(buyerId));
    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(title: const Text('My Orders')),
      body: orders.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: GoCartTheme.brand),
        ),
        error: (error, stackTrace) => _OrdersMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load orders',
          message: 'Please check your connection and try again.',
          action: TextButton.icon(
            onPressed: () => ref.invalidate(myOrdersProvider(buyerId)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (items) => items.isEmpty
            ? _OrdersMessage(
                icon: Icons.receipt_long_outlined,
                title: 'No orders yet',
                message: 'Orders you place will appear here.',
                action: FilledButton.tonal(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const UserHomeScreen()),
                    (route) => false,
                  ),
                  child: const Text('Browse products'),
                ),
              )
            : RefreshIndicator(
                color: GoCartTheme.brand,
                onRefresh: () async =>
                    ref.invalidate(myOrdersProvider(buyerId)),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final order = items[index];
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: _OrderCard(
                          order: order,
                          canResumePayment:
                              !kIsWeb &&
                              (defaultTargetPlatform ==
                                      TargetPlatform.android ||
                                  defaultTargetPlatform ==
                                      TargetPlatform.iOS) &&
                              order.status == 'pending' &&
                              order.paymentStatus == 'unpaid',
                          onResumePayment: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RazorpayPaymentScreen(orderId: order.id),
                              ),
                            );
                            ref.invalidate(myOrdersProvider(buyerId));
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final DemoOrder order;
  final bool canResumePayment;
  final VoidCallback onResumePayment;

  const _OrderCard({
    required this.order,
    required this.canResumePayment,
    required this.onResumePayment,
  });

  String get _paymentLabel => switch (order.paymentStatus) {
    'paid' => 'PAID · TEST',
    'unpaid' => 'UNPAID',
    'cancelled' => 'CANCELLED',
    'payment_review' => 'REVIEW REQUIRED',
    'refund_pending' => 'REFUND PENDING',
    'partially_refunded' => 'PARTIALLY REFUNDED',
    'refunded' => 'REFUNDED',
    'refund_failed' => 'REFUND FAILED',
    final status => status.replaceAll('_', ' ').toUpperCase(),
  };

  String get _paymentMessage => switch (order.paymentStatus) {
    'paid' => 'Payment confirmed in test mode · no real charge',
    'unpaid' => 'No successful payment recorded.',
    'cancelled' => 'Payment was cancelled before it was completed.',
    'payment_review' =>
      'Captured payment needs review. Contact GoCart support.',
    'refund_pending' => 'Refund is pending with the payment provider.',
    'partially_refunded' => 'A partial refund has been confirmed.',
    'refunded' => 'Refund confirmed.',
    'refund_failed' => 'Refund failed. Contact GoCart support.',
    final status => 'Payment status: ${status.replaceAll('_', ' ')}.',
  };

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GoCartTheme.outline),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF5E8E4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.receipt_long_outlined,
            color: GoCartTheme.brand,
          ),
        ),
        title: Text(
          'Order ${order.displayCode}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatDate(order.createdAt)} · ${order.items.length} items',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${order.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              _paymentLabel,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                color: GoCartTheme.brand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        children: [
          const Divider(height: 12),
          for (final item in order.items) ...[
            _OrderItemRow(item: item),
            if (item != order.items.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6EE),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _paymentMessage,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF28764A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (canResumePayment) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onResumePayment,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Continue test payment'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final DemoOrderItem item;
  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            item.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Text('${item.quantity} × ₹${item.unitPrice.toStringAsFixed(2)}'),
        const SizedBox(width: 14),
        Text(
          '₹${item.lineTotal.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _OrdersMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _OrdersMessage({
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
