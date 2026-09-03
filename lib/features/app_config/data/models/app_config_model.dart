class AppConfigModel {
  final String companyName;
  // Greyscale — kept solely for thermal-receipt printing compatibility, not
  // for on-screen display. See logoColorUrl for anything shown in-app.
  final String? logoUrl;
  // Full-color logo for on-screen display (login, app bars, dashboards).
  // Backend falls back to logoUrl itself when no color logo is uploaded, so
  // this is never null when logoUrl isn't.
  final String? logoColorUrl;
  // Max allowed discount BELOW the resolved price (a delegate/admin
  // submitting a lower unit_price than resolved is rejected past this
  // percentage). There is deliberately no corresponding markup cap — a
  // price ABOVE resolved is always accepted server-side, no matter how
  // large — see DelegateInvoiceController::resolveBoundedPrice().
  final double maxPriceDiscountPct;
  final String headerText;
  final String footerText;
  final bool showPhone;
  // '58mm' or '80mm' — matches ReceiptSetting::paper_width on the backend.
  // Drives the printed receipt's raster width so it fills/centers on the
  // physical paper roll instead of always rendering at a fixed width.
  final String paperWidth;

  const AppConfigModel({
    required this.companyName,
    this.logoUrl,
    this.logoColorUrl,
    this.maxPriceDiscountPct = 20,
    this.headerText = '',
    this.footerText = '',
    this.showPhone = true,
    this.paperWidth = '80mm',
  });

  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
        companyName: json['company_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        logoColorUrl: json['logo_color_url'] as String?,
        maxPriceDiscountPct:
            (json['max_price_discount_pct'] as num?)?.toDouble() ?? 20,
        headerText: json['header_text'] as String? ?? '',
        footerText: json['footer_text'] as String? ?? '',
        showPhone: json['show_phone'] as bool? ?? true,
        paperWidth: json['paper_width'] as String? ?? '80mm',
      );

  // Mirrors fromJson's keys — used solely to persist the last-fetched config
  // to disk (see AppConfigLocalDataSource) so it can seed the next cold
  // launch instantly, before a fresh fetch completes.
  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'logo_url': logoUrl,
        'logo_color_url': logoColorUrl,
        'max_price_discount_pct': maxPriceDiscountPct,
        'header_text': headerText,
        'footer_text': footerText,
        'show_phone': showPhone,
        'paper_width': paperWidth,
      };
}
