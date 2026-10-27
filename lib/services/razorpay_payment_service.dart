import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/razorpay_checkout.dart';

class RazorpayPaymentService {
  RazorpayPaymentService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<RazorpayOrderDetails> createOrder(String orderId) async {
    final response = await _supabase.functions.invoke(
      'create-razorpay-order',
      headers: {'Idempotency-Key': 'gocart-payment-order-$orderId'},
      body: {'order_id': orderId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw const RazorpayPaymentException(
        'Could not prepare the test payment. Your order remains unpaid.',
      );
    }
    return RazorpayOrderDetails.fromMap(_asMap(response.data));
  }

  Future<RazorpayVerificationResult> verifyPayment({
    required String orderId,
    required String providerOrderId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-payment',
      headers: {'Idempotency-Key': 'gocart-verify-payment-$orderId-$paymentId'},
      body: {
        'order_id': orderId,
        'razorpay_order_id': providerOrderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw const RazorpayPaymentException(
        'The payment could not be confirmed. Check your order status before retrying.',
      );
    }
    final result = RazorpayVerificationResult.fromMap(_asMap(response.data));
    if (result.orderId != orderId) {
      throw const RazorpayPaymentException(
        'The server returned a different order. Payment remains unconfirmed.',
      );
    }
    return result;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('Invalid payment server response.');
  }
}

class RazorpayPaymentException implements Exception {
  const RazorpayPaymentException(this.message);
  final String message;

  @override
  String toString() => message;
}
