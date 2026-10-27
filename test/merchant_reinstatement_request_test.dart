import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/merchant_reinstatement_request.dart';

void main() {
  test('parses an open merchant account review request', () {
    final request = MerchantReinstatementRequest.fromRow({
      'request_id': 12,
      'request_status': 'open',
      'request_message': 'The requested documents are ready.',
      'created_at': '2026-10-27T09:30:00Z',
      'resolved_at': null,
      'resolution_reason': null,
    });

    expect(request.id, 12);
    expect(request.status, 'open');
    expect(request.isOpen, isTrue);
    expect(request.message, 'The requested documents are ready.');
    expect(request.resolvedAt, isNull);
  });

  test('parses an admin decision without changing request meaning', () {
    final request = MerchantReinstatementRequest.fromRow({
      'request_id': 15,
      'request_status': 'rejected',
      'request_message': 'Please review my account.',
      'created_at': '2026-10-27T09:30:00Z',
      'resolved_at': '2026-10-27T10:00:00Z',
      'resolution_reason': 'Please provide updated documents.',
    });

    expect(request.isOpen, isFalse);
    expect(request.status, 'rejected');
    expect(request.resolutionReason, 'Please provide updated documents.');
  });

  test('rejects malformed server responses', () {
    expect(
      () => MerchantReinstatementRequest.fromRow(const {}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MerchantReinstatementRequest.fromRow({
        'request_id': 1,
        'request_status': 'approved_by_client',
        'request_message': 'x',
        'created_at': '2026-10-27T09:30:00Z',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
