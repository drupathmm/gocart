class MerchantReinstatementRequest {
  const MerchantReinstatementRequest({
    required this.id,
    required this.status,
    required this.message,
    required this.createdAt,
    this.resolvedAt,
    this.resolutionReason,
  });

  final int id;
  final String status;
  final String message;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolutionReason;

  bool get isOpen => status == 'open';

  factory MerchantReinstatementRequest.fromRow(Map<String, dynamic> row) {
    final id = row['request_id'];
    final status = row['request_status'];
    final message = row['request_message'];
    final createdAt = row['created_at'];
    if (id is! num ||
        status is! String ||
        message is! String ||
        createdAt is! String) {
      throw const FormatException('Invalid merchant reinstatement response.');
    }
    final parsedStatus = status;
    if (!const {'open', 'approved', 'rejected'}.contains(parsedStatus)) {
      throw const FormatException('Unknown merchant reinstatement status.');
    }
    return MerchantReinstatementRequest(
      id: id.toInt(),
      status: parsedStatus,
      message: message,
      createdAt: DateTime.parse(createdAt),
      resolvedAt: row['resolved_at'] is String
          ? DateTime.tryParse(row['resolved_at'] as String)
          : null,
      resolutionReason: row['resolution_reason'] as String?,
    );
  }
}
