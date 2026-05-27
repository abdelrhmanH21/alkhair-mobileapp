class LoadingItemModel {
  final int id;
  final int productId;
  final String productName;
  final String productUnit;
  final double quantityRequested;
  final double quantityConfirmed;

  const LoadingItemModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productUnit,
    required this.quantityRequested,
    required this.quantityConfirmed,
  });

  factory LoadingItemModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    return LoadingItemModel(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: product['name'] as String? ?? '',
      productUnit: product['unit'] as String? ?? '',
      quantityRequested: (json['quantity_requested'] as num).toDouble(),
      quantityConfirmed: (json['quantity_confirmed'] as num? ?? 0).toDouble(),
    );
  }
}

class LoadingModel {
  final int id;
  final int delegateId;
  final int warehouseId;
  final String warehouseName;
  final String status;
  final String? createdByName;
  final DateTime? loadedAt;
  final List<LoadingItemModel> items;

  const LoadingModel({
    required this.id,
    required this.delegateId,
    required this.warehouseId,
    required this.warehouseName,
    required this.status,
    this.createdByName,
    this.loadedAt,
    required this.items,
  });

  factory LoadingModel.fromJson(Map<String, dynamic> json) {
    final wh = json['warehouse'] as Map<String, dynamic>? ?? {};
    final createdBy = json['created_by'] as Map<String, dynamic>?;
    return LoadingModel(
      id: json['id'] as int,
      delegateId: json['delegate_id'] as int,
      warehouseId: json['warehouse_id'] as int,
      warehouseName: wh['name'] as String? ?? '',
      status: json['status'] as String,
      createdByName: createdBy?['name'] as String?,
      loadedAt: json['loaded_at'] != null
          ? DateTime.tryParse(json['loaded_at'] as String)
          : null,
      items: (json['items'] as List? ?? [])
          .map((e) => LoadingItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get isPendingPickup => status == 'pending_pickup';
  bool get isAccepted      => status == 'accepted';
}

class TruckStockModel {
  final int id;
  final int productId;
  final String productName;
  final String productUnit;
  final double currentStockQty;

  const TruckStockModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productUnit,
    required this.currentStockQty,
  });

  factory TruckStockModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    return TruckStockModel(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: product['name'] as String? ?? '',
      productUnit: product['unit'] as String? ?? '',
      currentStockQty: (json['current_stock_qty'] as num).toDouble(),
    );
  }
}
