class CheckoutException implements Exception {
  final String code;
  final String message;

  const CheckoutException(this.code, this.message);

  factory CheckoutException.fromCode(String code) {
    switch (code) {
      case 'OUT_OF_STOCK':
        return const CheckoutException(
          'OUT_OF_STOCK',
          'One or more items are out of stock. Update your cart and try again.',
        );
      case 'MERCHANT_UNAVAILABLE':
        return const CheckoutException(
          'MERCHANT_UNAVAILABLE',
          'A store in your cart is temporarily unavailable. Remove that item or try again later.',
        );
      case 'CART_EMPTY':
        return const CheckoutException('CART_EMPTY', 'Your cart is empty.');
      case 'OFFER_NOT_AVAILABLE':
        return const CheckoutException(
          'OFFER_NOT_AVAILABLE',
          'This offer code is not available for this order.',
        );
      case 'NOT_AUTHENTICATED':
        return const CheckoutException(
          'NOT_AUTHENTICATED',
          'Please sign in again before checkout.',
        );
      case 'INVALID_BODY':
        return const CheckoutException(
          'INVALID_BODY',
          'Checkout could not be submitted. Try again.',
        );
      case 'IDEMPOTENCY_CONFLICT':
        return const CheckoutException(
          'IDEMPOTENCY_CONFLICT',
          'This checkout attempt conflicts with an earlier request. Refresh your cart and start checkout again.',
        );
      case 'CHECKOUT_QUANTITY_ALREADY_RESERVED':
        return const CheckoutException(
          'CHECKOUT_QUANTITY_ALREADY_RESERVED',
          'This cart item is already being checked out. Wait a moment, refresh your cart, and retry.',
        );
      case 'CHECKOUT_TIMEOUT':
        return const CheckoutException(
          'CHECKOUT_TIMEOUT',
          'Checkout is taking longer than expected. Your order may still be processing. Retry safely in a moment.',
        );
      case 'ORDER_HISTORY_TIMEOUT':
        return const CheckoutException(
          'ORDER_HISTORY_TIMEOUT',
          'Loading orders took too long. Check your connection and retry.',
        );
      default:
        return CheckoutException(
          code,
          'Could not complete checkout. Please try again.',
        );
    }
  }

  @override
  String toString() => message;
}
