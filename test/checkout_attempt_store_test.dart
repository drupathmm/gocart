import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/services/checkout_attempt_store.dart';

class _MemoryAttemptStorage implements CheckoutAttemptStorage {
  final Map<String, String> values = {};
  bool allowWrites = true;

  @override
  Future<String?> read(String userId) async => values[userId];

  @override
  Future<bool> write(String userId, String value) async {
    if (!allowWrites) return false;
    values[userId] = value;
    return true;
  }

  @override
  Future<bool> remove(String userId) async => values.remove(userId) != null;
}

const _cartFingerprint = '41:9:2';

void main() {
  test('an unfinished attempt is reused after recreating the store', () async {
    final storage = _MemoryAttemptStorage();
    final firstStore = CheckoutAttemptStore(
      storage: storage,
      createKey: () => 'first-key-12345678',
    );
    final firstAttempt = await firstStore.prepare(
      userId: 'buyer-1',
      cartFingerprint: _cartFingerprint,
      offerCode: ' SAVE10 ',
    );

    // No completion marker represents a failed or interrupted request.
    final recreatedStore = CheckoutAttemptStore(
      storage: storage,
      createKey: () => 'second-key-12345678',
    );
    final retry = await recreatedStore.prepare(
      userId: 'buyer-1',
      cartFingerprint: _cartFingerprint,
      offerCode: 'save10',
    );

    expect(retry.idempotencyKey, firstAttempt.idempotencyKey);
    expect(retry.offerCode, 'SAVE10');
  });

  test(
    'changed cart rows, quantities, or offers receive a fresh key',
    () async {
      final storage = _MemoryAttemptStorage();
      var nextKey = 0;
      final store = CheckoutAttemptStore(
        storage: storage,
        createKey: () => 'key-${++nextKey}-12345678',
      );
      final original = await store.prepare(
        userId: 'buyer-1',
        cartFingerprint: _cartFingerprint,
        offerCode: '',
      );

      final changedCartRow = await store.prepare(
        userId: 'buyer-1',
        cartFingerprint: '42:9:2',
        offerCode: '',
      );
      final changedQuantity = await store.prepare(
        userId: 'buyer-1',
        cartFingerprint: '42:9:3',
        offerCode: '',
      );
      final changedOffer = await store.prepare(
        userId: 'buyer-1',
        cartFingerprint: '42:9:3',
        offerCode: 'SAVE10',
      );

      expect(changedCartRow.idempotencyKey, isNot(original.idempotencyKey));
      expect(
        changedQuantity.idempotencyKey,
        isNot(changedCartRow.idempotencyKey),
      );
      expect(
        changedOffer.idempotencyKey,
        isNot(changedQuantity.idempotencyKey),
      );
    },
  );

  test('completed attempts are never reused for a new order', () async {
    final storage = _MemoryAttemptStorage();
    var nextKey = 0;
    final store = CheckoutAttemptStore(
      storage: storage,
      createKey: () => 'key-${++nextKey}-12345678',
    );
    final original = await store.prepare(
      userId: 'buyer-1',
      cartFingerprint: _cartFingerprint,
      offerCode: '',
    );

    expect(
      await store.markCompleted(
        userId: 'buyer-1',
        idempotencyKey: original.idempotencyKey,
      ),
      isTrue,
    );
    final nextOrder = await store.prepare(
      userId: 'buyer-1',
      cartFingerprint: _cartFingerprint,
      offerCode: '',
    );

    expect(nextOrder.idempotencyKey, isNot(original.idempotencyKey));
  });

  test('attempts are isolated by user', () async {
    final storage = _MemoryAttemptStorage();
    var nextKey = 0;
    final store = CheckoutAttemptStore(
      storage: storage,
      createKey: () => 'key-${++nextKey}-12345678',
    );

    final first = await store.prepare(
      userId: 'buyer-1',
      cartFingerprint: _cartFingerprint,
      offerCode: '',
    );
    final second = await store.prepare(
      userId: 'buyer-2',
      cartFingerprint: _cartFingerprint,
      offerCode: '',
    );

    expect(second.idempotencyKey, isNot(first.idempotencyKey));
  });

  test('checkout is blocked when the retry key cannot be saved', () async {
    final storage = _MemoryAttemptStorage()..allowWrites = false;
    final store = CheckoutAttemptStore(
      storage: storage,
      createKey: () => 'unsaved-key-12345678',
    );

    await expectLater(
      store.prepare(
        userId: 'buyer-1',
        cartFingerprint: _cartFingerprint,
        offerCode: '',
      ),
      throwsA(isA<CheckoutAttemptPersistenceException>()),
    );
  });
}
