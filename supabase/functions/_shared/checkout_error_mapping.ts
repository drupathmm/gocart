export function mapPlaceOrderError(message: string): { status: number; code: string } {
  const code = message.split(':').pop()?.trim() ?? message;
  if (code === 'INVALID_IDEMPOTENCY_KEY') {
    return { status: 400, code };
  }
  if (
    code === 'OUT_OF_STOCK' ||
    code === 'MERCHANT_UNAVAILABLE' ||
    code === 'CART_EMPTY' ||
    code === 'OFFER_NOT_AVAILABLE' ||
    code === 'IDEMPOTENCY_CONFLICT' ||
    code === 'IDEMPOTENCY_IN_PROGRESS' ||
    code === 'CHECKOUT_QUANTITY_ALREADY_RESERVED'
  ) {
    return { status: 409, code };
  }
  if (code === 'NOT_AUTHENTICATED') {
    return { status: 401, code };
  }
  return { status: 500, code: 'CHECKOUT_FAILED' };
}
