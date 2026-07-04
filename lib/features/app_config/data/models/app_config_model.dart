class AppConfigModel {
  final String companyName;
  final String? logoUrl;
  final double maxPriceOverridePct;

  const AppConfigModel({
    required this.companyName,
    this.logoUrl,
    this.maxPriceOverridePct = 10,
  });

  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
        companyName: json['company_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        maxPriceOverridePct:
            (json['max_price_override_pct'] as num?)?.toDouble() ?? 10,
      );
}
