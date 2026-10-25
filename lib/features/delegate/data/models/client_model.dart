class ClientModel {
  final int id;
  final String name;
  final String phone;
  final String? address;
  final double balance;

  /// Customer region name (تسجيل موقع عميل panel). Null on older payloads.
  final String? regionName;

  /// Whether a GPS pin exists — the server never sends delegates the
  /// coordinates themselves.
  final bool hasLocation;
  final DateTime? locationRecordedAt;

  const ClientModel({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    required this.balance,
    this.regionName,
    this.hasLocation = false,
    this.locationRecordedAt,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) => ClientModel(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String?,
        balance: (json['balance'] as num? ?? 0).toDouble(),
        regionName: json['region_name'] as String? ?? (json['region'] is Map ? json['region']['name'] as String? : null),
        hasLocation: json['has_location'] == true || json['has_location'] == 1,
        locationRecordedAt: DateTime.tryParse(json['location_recorded_at'] as String? ?? '')?.toLocal(),
      );

  ClientModel copyWith({bool? hasLocation, DateTime? locationRecordedAt}) => ClientModel(
        id: id,
        name: name,
        phone: phone,
        address: address,
        balance: balance,
        regionName: regionName,
        hasLocation: hasLocation ?? this.hasLocation,
        locationRecordedAt: locationRecordedAt ?? this.locationRecordedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        if (address != null) 'address': address,
        'balance': balance,
        if (regionName != null) 'region_name': regionName,
        'has_location': hasLocation,
        if (locationRecordedAt != null) 'location_recorded_at': locationRecordedAt!.toUtc().toIso8601String(),
      };
}
