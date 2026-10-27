import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/merchant_reinstatement_request.dart';

class MerchantReinstatementService {
  MerchantReinstatementService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<MerchantReinstatementRequest?> getLatestRequest() async {
    final rows = await _client.rpc('merchant_get_reinstatement_request');
    final first = _firstRow(rows);
    return first == null ? null : MerchantReinstatementRequest.fromRow(first);
  }

  Future<MerchantReinstatementRequest> submitRequest(String message) async {
    final normalized = message.trim();
    if (normalized.isEmpty || normalized.length > 2000) {
      throw const FormatException('Enter a message of up to 2,000 characters.');
    }
    final rows = await _client.rpc(
      'merchant_request_reinstatement',
      params: {'p_message': normalized},
    );
    final first = _firstRow(rows);
    if (first == null) {
      throw const FormatException('The review request was not returned.');
    }
    return MerchantReinstatementRequest.fromRow(first);
  }

  static Map<String, dynamic>? _firstRow(dynamic response) {
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }
}
