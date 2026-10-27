import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CheckoutAttemptStorage {
  Future<String?> read(String userId);
  Future<bool> write(String userId, String value);
  Future<bool> remove(String userId);
}

class SharedPreferencesCheckoutAttemptStorage
    implements CheckoutAttemptStorage {
  const SharedPreferencesCheckoutAttemptStorage();

  String _storageKey(String userId) => 'checkout_attempt_v1_$userId';

  @override
  Future<String?> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_storageKey(userId));
  }

  @override
  Future<bool> write(String userId, String value) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(_storageKey(userId), value);
  }

  @override
  Future<bool> remove(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.remove(_storageKey(userId));
  }
}

class CheckoutAttempt {
  final String idempotencyKey;
  final String cartFingerprint;
  final String offerCode;
  final bool completed;

  const CheckoutAttempt({
    required this.idempotencyKey,
    required this.cartFingerprint,
    required this.offerCode,
    required this.completed,
  });

  factory CheckoutAttempt.fromJson(Map<String, dynamic> json) {
    return CheckoutAttempt(
      idempotencyKey: json['idempotency_key'] as String,
      cartFingerprint: json['cart_fingerprint'] as String,
      offerCode: json['offer_code'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'idempotency_key': idempotencyKey,
    'cart_fingerprint': cartFingerprint,
    'offer_code': offerCode,
    'completed': completed,
  };
}

class CheckoutAttemptPersistenceException implements Exception {
  const CheckoutAttemptPersistenceException();

  @override
  String toString() =>
      'Checkout could not be prepared safely. Check your device storage and try again.';
}

class CheckoutAttemptStore {
  CheckoutAttemptStore({
    required CheckoutAttemptStorage storage,
    String Function()? createKey,
  }) : _storage = storage,
       _createKey = createKey ?? _createSecureKey;

  final CheckoutAttemptStorage _storage;
  final String Function() _createKey;

  static String _createSecureKey() {
    final random = Random.secure();
    return List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String cartFingerprint(
    Iterable<({int cartItemId, int productId, int quantity})> items,
  ) {
    final sortedItems = items.toList()
      ..sort((a, b) => a.cartItemId.compareTo(b.cartItemId));
    return sortedItems
        .map((item) => '${item.cartItemId}:${item.productId}:${item.quantity}')
        .join('|');
  }

  Future<CheckoutAttempt?> load(String userId) async {
    final value = await _storage.read(userId);
    if (value == null) return null;

    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      return CheckoutAttempt.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<CheckoutAttempt> prepare({
    required String userId,
    required String cartFingerprint,
    required String offerCode,
  }) async {
    try {
      final normalizedOffer = offerCode.trim();
      final existing = await load(userId);
      if (existing != null &&
          !existing.completed &&
          existing.cartFingerprint == cartFingerprint &&
          existing.offerCode.toLowerCase() == normalizedOffer.toLowerCase()) {
        return existing;
      }

      final attempt = CheckoutAttempt(
        idempotencyKey: _createKey(),
        cartFingerprint: cartFingerprint,
        offerCode: normalizedOffer,
        completed: false,
      );
      final saved = await _storage.write(userId, jsonEncode(attempt.toJson()));
      if (!saved) throw const CheckoutAttemptPersistenceException();
      return attempt;
    } on CheckoutAttemptPersistenceException {
      rethrow;
    } catch (_) {
      throw const CheckoutAttemptPersistenceException();
    }
  }

  Future<CheckoutAttempt?> pendingForCart({
    required String userId,
    required String cartFingerprint,
  }) async {
    final attempt = await load(userId);
    if (attempt == null ||
        attempt.completed ||
        attempt.cartFingerprint != cartFingerprint) {
      return null;
    }
    return attempt;
  }

  Future<bool> markCompleted({
    required String userId,
    required String idempotencyKey,
  }) async {
    try {
      final attempt = await load(userId);
      if (attempt == null || attempt.idempotencyKey != idempotencyKey) {
        return false;
      }

      final completed = CheckoutAttempt(
        idempotencyKey: attempt.idempotencyKey,
        cartFingerprint: attempt.cartFingerprint,
        offerCode: attempt.offerCode,
        completed: true,
      );
      final saved = await _storage.write(
        userId,
        jsonEncode(completed.toJson()),
      );
      if (saved) return true;

      // If the completion marker cannot be saved, removing the stale key is
      // also safe: the next checkout must begin with a fresh key.
      return _storage.remove(userId);
    } catch (_) {
      return false;
    }
  }
}
