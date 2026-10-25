/// Response of POST /delegate/customers/{id}/location. Never carries
/// coordinates — only whether the pin was applied (false = a newer pin
/// recorded elsewhere won last-write-wins) and the customer's current state.
class CustomerLocationResult {
  final bool applied;
  final int customerId;
  final bool hasLocation;
  final DateTime? locationRecordedAt;

  const CustomerLocationResult({
    required this.applied,
    required this.customerId,
    required this.hasLocation,
    this.locationRecordedAt,
  });

  factory CustomerLocationResult.fromJson(Map<String, dynamic> json) {
    final c = (json['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CustomerLocationResult(
      applied: json['applied'] == true,
      customerId: (c['id'] as num?)?.toInt() ?? 0,
      hasLocation: c['has_location'] == true,
      locationRecordedAt: DateTime.tryParse(c['location_recorded_at'] as String? ?? '')?.toLocal(),
    );
  }
}
