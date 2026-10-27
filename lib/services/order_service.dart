import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checkout_exception.dart';
import '../models/demo_order.dart';

typedef OrderRowsLoader =
    Future<List<Map<String, dynamic>>> Function({
      required String buyerId,
      required String buyerColumn,
      required String totalColumn,
    });

class OrderService {
  final SupabaseClient? _supabaseClient;
  final OrderRowsLoader? _orderRowsLoader;
  final String? Function()? _currentUserId;

  OrderService({
    SupabaseClient? supabaseClient,
    OrderRowsLoader? orderRowsLoader,
    String? Function()? currentUserId,
  }) : _supabaseClient = supabaseClient,
       _orderRowsLoader = orderRowsLoader,
       _currentUserId = currentUserId;

  SupabaseClient get _supabase => _supabaseClient ?? Supabase.instance.client;

  void _requireExpectedBuyer(String expectedBuyerId) {
    final currentUserId =
        _currentUserId?.call() ?? _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != expectedBuyerId) {
      throw const CheckoutException(
        'NOT_AUTHENTICATED',
        'Your session changed. Please sign in again.',
      );
    }
  }

  Future<DemoOrderReceipt> checkout({
    required String expectedBuyerId,
    required String idempotencyKey,
    String? offerCode,
  }) async {
    _requireExpectedBuyer(expectedBuyerId);

    late final FunctionResponse response;
    try {
      response = await _supabase.functions
          .invoke(
            'checkout',
            headers: {'Idempotency-Key': idempotencyKey},
            body: {
              if (offerCode != null && offerCode.trim().isNotEmpty)
                'offer_code': offerCode.trim(),
            },
          )
          .timeout(const Duration(seconds: 30));
    } on FunctionException catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Checkout function failed: status=${error.status}, '
          'code=${_errorCode(_asMap(error.details), error.status)}',
        );
      }
      throw CheckoutException.fromCode(
        _errorCode(_asMap(error.details), error.status),
      );
    } on TimeoutException {
      throw const CheckoutException(
        'CHECKOUT_TIMEOUT',
        'Checkout is taking longer than expected. Your order may still be processing. Retry safely in a moment.',
      );
    }

    final data = _asMap(response.data);
    if (response.status >= 400) {
      throw CheckoutException.fromCode(_errorCode(data, response.status));
    }

    try {
      return DemoOrderReceipt.fromMap(data);
    } catch (_) {
      throw const CheckoutException(
        'CHECKOUT_FAILED',
        'The order could not be confirmed.',
      );
    }
  }

  Future<List<DemoOrder>> getMyOrders(String expectedBuyerId) async {
    _requireExpectedBuyer(expectedBuyerId);

    try {
      var totalColumn = 'total_amount';
      var buyerColumn = 'user_id';
      late final List<Map<String, dynamic>> response;
      while (true) {
        try {
          response = await _loadOrderRows(
            buyerId: expectedBuyerId,
            buyerColumn: buyerColumn,
            totalColumn: totalColumn,
          );
          break;
        } on PostgrestException catch (error) {
          // The repository migration renames total to total_amount and
          // buyer_id to user_id. Some hosted environments still expose the
          // original columns. Retry only an explicitly reported missing
          // legacy/current column; unrelated errors remain visible.
          if (error.code != '42703') rethrow;
          final message = error.message.toLowerCase();
          if (totalColumn == 'total_amount' &&
              message.contains('total_amount')) {
            totalColumn = 'total';
            continue;
          }
          if (buyerColumn == 'user_id' && message.contains('user_id')) {
            buyerColumn = 'buyer_id';
            continue;
          }
          rethrow;
        }
      }

      return response.map((row) => DemoOrder.fromMap(row)).toList();
    } on PostgrestException catch (error) {
      if (kDebugMode) {
        final message = error.message.replaceAll(RegExp(r'\s+'), ' ');
        debugPrint(
          'Order history query failed: code=${error.code}, '
          'message=${message.substring(0, message.length.clamp(0, 240).toInt())}',
        );
      }
      rethrow;
    } on CheckoutException {
      rethrow;
    } on TimeoutException {
      throw const CheckoutException(
        'ORDER_HISTORY_TIMEOUT',
        'Loading orders took too long. Check your connection and retry.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrderRows({
    required String buyerId,
    required String buyerColumn,
    required String totalColumn,
  }) async {
    final loader = _orderRowsLoader;
    if (loader != null) {
      return loader(
        buyerId: buyerId,
        buyerColumn: buyerColumn,
        totalColumn: totalColumn,
      ).timeout(const Duration(seconds: 20));
    }

    final response = await _supabase
        .from('orders')
        .select(
          'id, status, payment_status, $totalColumn, created_at, '
          'order_items(product_name, unit_price, quantity, line_total)',
        )
        .eq(buyerColumn, buyerId)
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 20));

    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  String _errorCode(dynamic data, int status) {
    const known = {
      'OUT_OF_STOCK',
      'CART_EMPTY',
      'OFFER_NOT_AVAILABLE',
      'NOT_AUTHENTICATED',
      'INVALID_BODY',
      'IDEMPOTENCY_CONFLICT',
      'CHECKOUT_QUANTITY_ALREADY_RESERVED',
    };
    if (data is String) {
      for (final code in known) {
        if (data.contains(code)) return code;
      }
    }
    final map = _asMap(data);
    final error = map['error'];
    if (error is Map && error['code'] is String) {
      return error['code'] as String;
    }
    if (map['code'] is String) return map['code'] as String;
    if (status == 401) return 'NOT_AUTHENTICATED';
    return 'CHECKOUT_FAILED';
  }
}
