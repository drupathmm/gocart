import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../services/razorpay_payment_service.dart';
import '../theme/app_theme.dart';

class RazorpayPaymentScreen extends StatefulWidget {
  const RazorpayPaymentScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<RazorpayPaymentScreen> createState() => _RazorpayPaymentScreenState();
}

class _RazorpayPaymentScreenState extends State<RazorpayPaymentScreen> {
  final _razorpay = Razorpay();
  final _payments = RazorpayPaymentService();
  bool _working = false;
  bool _paid = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startPayment() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final order = await _payments.createOrder(widget.orderId);
      if (!mounted) return;
      _razorpay.open({
        'key': order.keyId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'order_id': order.providerOrderId,
        'name': 'GoCart',
        'description': 'Order ${widget.orderId}',
        'retry': {'enabled': true, 'max_count': 3},
        'send_sms_hash': true,
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _message =
              error is RazorpayPaymentException || error is FormatException
              ? error.toString()
              : 'Could not prepare payment. The order remains unpaid.';
        });
      }
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final paymentId = response.paymentId;
    final providerOrderId = response.orderId;
    final signature = response.signature;
    if (paymentId == null || providerOrderId == null || signature == null) {
      if (mounted) {
        setState(() {
          _working = false;
          _message =
              'Payment details were incomplete. Check order status before retrying.';
        });
      }
      return;
    }

    setState(() {
      _working = true;
      _message = 'Confirming payment securely…';
    });
    try {
      final result = await _payments.verifyPayment(
        orderId: widget.orderId,
        providerOrderId: providerOrderId,
        paymentId: paymentId,
        signature: signature,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _paid = result.isPaid;
        _message = result.isPaid
            ? 'Payment confirmed by GoCart.'
            : 'Payment needs review. The order is not marked paid.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _message = error is RazorpayPaymentException
              ? error.message
              : 'Payment confirmation is unavailable. Check order status before retrying.';
        });
      }
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() {
      _working = false;
      _message =
          'No payment was confirmed. The order remains unpaid unless GoCart later confirms otherwise.';
    });
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() {
      _working = false;
      _message =
          'External wallet selected. Check order status after completing payment.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final supportedPlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(title: const Text('Test payment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _paid ? Icons.check_circle_outline : Icons.lock_outline,
                  size: 56,
                  color: GoCartTheme.brand,
                ),
                const SizedBox(height: 16),
                Text(
                  _paid ? 'Payment confirmed' : 'Razorpay test mode',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _message ??
                      'Use Razorpay test credentials only. The amount and currency come from the saved GoCart order.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                if (_working)
                  const CircularProgressIndicator()
                else if (!_paid && supportedPlatform)
                  FilledButton(
                    onPressed: _startPayment,
                    child: const Text('Continue with test payment'),
                  )
                else if (!_paid)
                  const Text(
                    'Razorpay Checkout is available in the Android and iOS app.',
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_paid),
                  child: Text(_paid ? 'Return to orders' : 'Back to orders'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
