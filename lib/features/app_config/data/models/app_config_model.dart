class AppConfigModel {
  final String companyName;
  final String? logoUrl;

  const AppConfigModel({required this.companyName, this.logoUrl});

  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
        companyName: json['company_name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
      );
}
