class AppConfigModel {
  final String companyName;
  // Greyscale — kept solely for thermal-receipt printing compatibility, not
  // for on-screen display. See logoColorUrl for anything shown in-app.
  final String? logoUrl;
  // Full-color logo for on-screen display (login, app bars, dashboards).
  // Backend falls back to logoUrl itself when no color logo is uploaded, so
  // this is never null when logoUrl isn't.
  final String? logoColorUrl;
  final double maxPriceOverridePct;

  const AppConfigModel({
    required this.companyName,
    this.logoUrl,
    this.logoColorUrl,
    this.maxPriceOverridePct = 10,
  });

  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
        companyName: json['company_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        logoColorUrl: json['logo_color_url'] as String?,
        maxPriceOverridePct:
            (json['max_price_override_pct'] as num?)?.toDouble() ?? 10,
      );
}
