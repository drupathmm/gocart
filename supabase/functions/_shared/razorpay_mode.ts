export function isRazorpayTestKeyId(keyId: string): boolean {
  return /^rzp_test_[A-Za-z0-9]+$/.test(keyId);
}
