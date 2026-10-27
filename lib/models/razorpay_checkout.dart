class RazorpayOrderDetails {
  const RazorpayOrderDetails({
    required this.orderId,
    required this.providerOrderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
  });

  final String orderId;
  final String providerOrderId;
  final String keyId;
  final int amountPaise;
  final String currency;

  factory RazorpayOrderDetails.fromMap(Map<String, dynamic> map) {
    final amount = map['amount'];
    final result = RazorpayOrderDetails(
      orderId: map['order_id'] as String? ?? '',
      providerOrderId: map['razorpay_order_id'] as String? ?? '',
      keyId: map['razorpay_key_id'] as String? ?? '',
      amountPaise: amount is num ? amount.toInt() : -1,
      currency: map['currency'] as String? ?? '',
    );
    if (result.orderId.isEmpty ||
        result.providerOrderId.isEmpty ||
        !result.keyId.startsWith('rzp_test_') ||
        result.amountPaise <= 0 ||
        result.currency != 'INR') {
      throw const FormatException('Invalid Razorpay test order response.');
    }
    return result;
  }
}

class RazorpayVerificationResult {
  const RazorpayVerificationResult({
    required this.orderId,
    required this.status,
    required this.paymentStatus,
    required this.result,
  });

  final String orderId;
  final String status;
  final String paymentStatus;
  final String result;

  bool get isPaid => status == 'paid' && paymentStatus == 'paid';

  factory RazorpayVerificationResult.fromMap(Map<String, dynamic> map) {
    final result = RazorpayVerificationResult(
      orderId: map['order_id'] as String? ?? '',
      status: map['status'] as String? ?? '',
      paymentStatus: map['payment_status'] as String? ?? '',
      result: map['verification_result'] as String? ?? '',
    );
    if (result.orderId.isEmpty) {
      throw const FormatException('Invalid payment verification response.');
    }
    return result;
  }
}
