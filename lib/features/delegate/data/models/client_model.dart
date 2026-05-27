class ClientModel {
  final int id;
  final String name;
  final String phone;
  final String? address;
  final double balance;

  const ClientModel({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    required this.balance,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) => ClientModel(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String?,
        balance: (json['balance'] as num? ?? 0).toDouble(),
      );
}
