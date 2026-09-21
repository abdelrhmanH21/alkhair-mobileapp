/// Mirrors DelegateDashboardController::priceVarianceSummary()'s
/// data.by_loading[].lines[] rows — one sold item's reference vs. charged
/// price. Never shown to the customer (self-service delegate view only).
class PriceVarianceLineModel {
  final int invoiceId;
  final String invoiceNumber;
  final String? customerName;
  final String? productName;
  final double quantity;
  final double referencePrice;
  final double chargedPrice;
  final double variance;

  const PriceVarianceLineModel({
    required this.invoiceId,
    required this.invoiceNumber,
    this.customerName,
    this.productName,
    required this.quantity,
    required this.referencePrice,
    required this.chargedPrice,
    required this.variance,
  });

  factory PriceVarianceLineModel.fromJson(Map<String, dynamic> json) => PriceVarianceLineModel(
        invoiceId: json['invoice_id'] as int,
        invoiceNumber: json['invoice_number'] as String? ?? '',
        customerName: json['customer_name'] as String?,
        productName: json['product_name'] as String?,
        quantity: (json['quantity'] as num? ?? 0).toDouble(),
        referencePrice: (json['reference_price'] as num? ?? 0).toDouble(),
        chargedPrice: (json['charged_price'] as num? ?? 0).toDouble(),
        variance: (json['variance'] as num? ?? 0).toDouble(),
      );
}

/// Mirrors data.by_loading[] — one تحميلة (loading/shipment) with every sold
/// line across all its invoices.
class PriceVarianceLoadingModel {
  final int loadingId;
  final String? date;
  final String status;
  final List<PriceVarianceLineModel> lines;
  final double loadingVarianceTotal;

  const PriceVarianceLoadingModel({
    required this.loadingId,
    this.date,
    required this.status,
    required this.lines,
    required this.loadingVarianceTotal,
  });

  factory PriceVarianceLoadingModel.fromJson(Map<String, dynamic> json) => PriceVarianceLoadingModel(
        loadingId: json['loading_id'] as int,
        date: json['date'] as String?,
        status: json['status'] as String? ?? '',
        lines: (json['lines'] as List? ?? [])
            .map((e) => PriceVarianceLineModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        loadingVarianceTotal: (json['loading_variance_total'] as num? ?? 0).toDouble(),
      );
}

/// Mirrors GET /v1/mobile/delegate/price-variance-summary's whole response —
/// replaces DashboardModel entirely for a "مندوب حر السعر" delegate.
class PriceVarianceSummaryModel {
  final double priceVarianceBalance;
  final List<PriceVarianceLoadingModel> byLoading;

  const PriceVarianceSummaryModel({
    required this.priceVarianceBalance,
    required this.byLoading,
  });

  factory PriceVarianceSummaryModel.fromJson(Map<String, dynamic> json) => PriceVarianceSummaryModel(
        priceVarianceBalance: (json['price_variance_balance'] as num? ?? 0).toDouble(),
        byLoading: (json['by_loading'] as List? ?? [])
            .map((e) => PriceVarianceLoadingModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
