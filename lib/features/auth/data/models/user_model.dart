class UserModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final int? branchId;
  final bool isActive;
  final List<String> permissions;
  final bool hasActiveLoading;
  final int truckStockCount;
  final bool salesNotificationsEnabled;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    required this.isActive,
    required this.permissions,
    required this.hasActiveLoading,
    required this.truckStockCount,
    this.salesNotificationsEnabled = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        branchId: json['branch_id'] as int?,
        isActive: json['is_active'] as bool? ?? true,
        permissions: List<String>.from(json['permissions'] ?? []),
        hasActiveLoading: json['has_active_loading'] as bool? ?? false,
        truckStockCount: json['truck_stock_count'] as int? ?? 0,
        salesNotificationsEnabled:
            json['sales_notifications_enabled'] as bool? ?? true,
      );

  bool get isDelegate => role == 'delegate';
  bool get isAdmin    => role == 'admin' || role == 'manager';
}

class AuthResponseModel {
  final String token;
  final UserModel user;

  const AuthResponseModel({required this.token, required this.user});

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) => AuthResponseModel(
        token: json['token'] as String,
        user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      );
}
