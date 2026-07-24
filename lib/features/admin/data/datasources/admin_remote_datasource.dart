import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../delegate/data/models/breakdown_models.dart';
import '../../../delegate/data/models/client_model.dart';
import '../models/admin_models.dart';

abstract class AdminRemoteDataSource {
  Future<DashboardStatsModel> fetchDashboard();
  Future<List<DelegateModel>> fetchDelegates();
  Future<ShiftSummaryModel> fetchShiftSummary(int delegateId);
  Future<Map<String, dynamic>> settleDelegate({
    required int delegateId,
    required int treasuryId,
    required int settlementRequestId,
    required double physicalCash,
    String? notes,
  });
  Future<List<SimpleProductModel>> fetchProducts();
  Future<List<SimpleWarehouseModel>> fetchWarehouses();
  Future<void> createLoading({
    required int delegateId,
    required int warehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
  });
  Future<void> updateNotificationPreference(bool enabled);

  // ── Expenses & Treasuries ──────────────────────────────────────────────
  Future<ExpensePageModel> fetchExpenses({
    String? dateFrom,
    String? dateTo,
    int? categoryId,
    int? treasuryId,
    int page = 1,
  });
  Future<List<TreasuryModel>> fetchTreasuries();
  Future<List<ExpenseCategoryModel>> fetchExpenseCategories();
  Future<void> createExpense({
    int? categoryId,
    required int treasuryId,
    required String description,
    required double amount,
    required String expenseDate,
    String? notes,
  });

  // ── Customers & Suppliers ──────────────────────────────────────────────
  Future<CustomerPageModel> fetchCustomers({String? search, int page = 1});
  Future<SupplierPageModel> fetchSuppliers({String? search, int page = 1});

  // ── Sales & collections (المبيعات والتحصيلات) ───────────────────────────
  Future<SalesCombinedPageModel> fetchSalesCombined({
    String? dateFrom,
    String? dateTo,
    int page = 1,
  });
  Future<CollectionPageModel> fetchCollections({
    String? dateFrom,
    String? dateTo,
    int page = 1,
  });

  // ── Payroll (العمالة) ─────────────────────────────────────────────────
  Future<List<PayrollSummaryRowModel>> fetchPayrollSummary({String? month});
  Future<List<PenaltyModel>> fetchRepPenalties(int repId);
  Future<List<AdvanceModel>> fetchRepAdvances(int repId);
  Future<List<CommissionDayModel>> fetchRepCommissionBreakdown(int repId);
  Future<void> setRepTarget({
    required int repId,
    required String month,
    required double targetAmount,
    String? notes,
  });

  // ── Production ("بدء تشغيلة جديدة" / "استلام إنتاج تام") ────────────────
  Future<List<IdNameModel>> fetchProductCategories();
  Future<List<IdNameModel>> fetchLabs();
  Future<List<RecipeModel>> fetchRecipes({int? categoryId});
  Future<List<ProductionBatchSummaryModel>> fetchInProgressBatches();
  Future<List<ProductionBatchSummaryModel>> fetchRecentlyCompletedBatches();
  Future<ProductionBatchDetailModel> fetchBatchDetail(int id);
  Future<String?> startProductionBatch({
    required int recipeId,
    int? categoryId,
    int? labId,
    String? notes,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> outputs,
    List<Map<String, dynamic>>? reentryMaterials,
    double? additionalExpense,
    int? expenseTreasuryId,
  });
  Future<void> completeProductionBatch({
    required int batchId,
    double? overheadFixed,
    double? overheadVariable,
    required List<Map<String, dynamic>> outputs,
  });

  // ── Customer search (shared by "عملية بيع" and "تحصيل من عميل") ──────────
  Future<List<ClientModel>> searchCustomers(String query);

  // ── Admin sale ("عملية بيع") ─────────────────────────────────────────────
  Future<AdminSaleResultModel> submitAdminSale({
    required int customerId,
    required int treasuryId,
    int? warehouseId,
    required double cashReceived,
    String? notes,
    required List<Map<String, dynamic>> salesItems,
  });

  // ── Price edit ("تعديل سعر") ─────────────────────────────────────────────
  Future<List<RawMaterialModel>> fetchRawMaterials();
  Future<PriceUpdateResultModel> updateProductPrice(int productId, double newPrice);
  Future<PriceUpdateResultModel> updateRawMaterialPrice(int rawMaterialId, double newPrice);

  // ── تحصيل/سداد من عميل (admin-initiated) ─────────────────────────────────
  Future<void> submitCustomerCollection({
    required int customerId,
    required int treasuryId,
    required double amount,
    String? notes,
  });
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final ApiClient _client;
  AdminRemoteDataSourceImpl(this._client);

  @override
  Future<DashboardStatsModel> fetchDashboard() async {
    final res = await _client.dio.get(ApiEndpoints.adminDashboard);
    return DashboardStatsModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<List<DelegateModel>> fetchDelegates() async {
    final res = await _client.dio.get(ApiEndpoints.adminDelegates);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => DelegateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ShiftSummaryModel> fetchShiftSummary(int delegateId) async {
    final res = await _client.dio.get(
      ApiEndpoints.adminShiftSummary,
      queryParameters: {'delegate_id': delegateId},
    );
    return ShiftSummaryModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>> settleDelegate({
    required int delegateId,
    required int treasuryId,
    required int settlementRequestId,
    required double physicalCash,
    String? notes,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.adminSettle, data: {
      'delegate_id': delegateId,
      'treasury_id': treasuryId,
      'settlement_request_id': settlementRequestId,
      'physical_cash': physicalCash,
      if (notes != null) 'notes': notes,
    });
    return res.data as Map<String, dynamic>;
  }

  @override
  Future<List<SimpleProductModel>> fetchProducts() async {
    final res = await _client.dio.get(ApiEndpoints.adminProducts);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => SimpleProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SimpleWarehouseModel>> fetchWarehouses() async {
    final res = await _client.dio.get(ApiEndpoints.adminWarehouses);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => SimpleWarehouseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createLoading({
    required int delegateId,
    required int warehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.adminLoadings, data: {
      'delegate_id': delegateId,
      'warehouse_id': warehouseId,
      'items': items,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  @override
  Future<void> updateNotificationPreference(bool enabled) async {
    await _client.dio.put(ApiEndpoints.notificationPreferences, data: {
      'sales_notifications_enabled': enabled,
    });
  }

  // ── Expenses & Treasuries ──────────────────────────────────────────────

  @override
  Future<ExpensePageModel> fetchExpenses({
    String? dateFrom,
    String? dateTo,
    int? categoryId,
    int? treasuryId,
    int page = 1,
  }) async {
    final res = await _client.dio.get(ApiEndpoints.expenses, queryParameters: {
      'page': page,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
      if (categoryId != null) 'category_id': categoryId,
      if (treasuryId != null) 'treasury_id': treasuryId,
    });
    return ExpensePageModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<List<TreasuryModel>> fetchTreasuries() async {
    final res = await _client.dio.get(ApiEndpoints.treasuries);
    final list = res.data as List? ?? [];
    return list
        .map((e) => TreasuryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ExpenseCategoryModel>> fetchExpenseCategories() async {
    // Paginated response (per_page defaults to 50 server-side, comfortably
    // covering the full category list in one page).
    final res = await _client.dio
        .get(ApiEndpoints.expenseItems, queryParameters: {'per_page': 100});
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list
        .map((e) => ExpenseCategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createExpense({
    int? categoryId,
    required int treasuryId,
    required String description,
    required double amount,
    required String expenseDate,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.expenses, data: {
      if (categoryId != null) 'category_id': categoryId,
      'treasury_id': treasuryId,
      'description': description,
      'amount': amount,
      'expense_date': expenseDate,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  // ── Customers & Suppliers ──────────────────────────────────────────────

  @override
  Future<CustomerPageModel> fetchCustomers({String? search, int page = 1}) async {
    final res = await _client.dio.get(ApiEndpoints.customers, queryParameters: {
      'page': page,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return CustomerPageModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<SupplierPageModel> fetchSuppliers({String? search, int page = 1}) async {
    final res = await _client.dio.get(ApiEndpoints.suppliers, queryParameters: {
      'page': page,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return SupplierPageModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Sales & collections (المبيعات والتحصيلات) ───────────────────────────

  @override
  Future<SalesCombinedPageModel> fetchSalesCombined({
    String? dateFrom,
    String? dateTo,
    int page = 1,
  }) async {
    final res = await _client.dio.get(ApiEndpoints.salesCombined, queryParameters: {
      'page': page,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return SalesCombinedPageModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<CollectionPageModel> fetchCollections({
    String? dateFrom,
    String? dateTo,
    int page = 1,
  }) async {
    final res = await _client.dio.get(ApiEndpoints.paymentCollections, queryParameters: {
      'type': 'collection',
      'page': page,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return CollectionPageModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Payroll (العمالة) ─────────────────────────────────────────────────

  @override
  Future<List<PayrollSummaryRowModel>> fetchPayrollSummary({String? month}) async {
    final res = await _client.dio.get(
      ApiEndpoints.adminPayrollSummary,
      queryParameters: {if (month != null) 'month': month},
    );
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list
        .map((e) => PayrollSummaryRowModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PenaltyModel>> fetchRepPenalties(int repId) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegatePenalties,
      queryParameters: {'rep_id': repId},
    );
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => PenaltyModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<AdvanceModel>> fetchRepAdvances(int repId) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegateAdvances,
      queryParameters: {'rep_id': repId},
    );
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => AdvanceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CommissionDayModel>> fetchRepCommissionBreakdown(int repId) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegateCommissionBreakdown,
      queryParameters: {'rep_id': repId},
    );
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => CommissionDayModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> setRepTarget({
    required int repId,
    required String month,
    required double targetAmount,
    String? notes,
  }) async {
    await _client.dio.put(ApiEndpoints.targets, data: {
      'rep_id': repId,
      'month': month,
      'target_amount': targetAmount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  // ── Production ("بدء تشغيلة جديدة" / "استلام إنتاج تام") ────────────────

  @override
  Future<List<IdNameModel>> fetchProductCategories() async {
    final res = await _client.dio
        .get(ApiEndpoints.categories, queryParameters: {'type': 'product', 'per_page': 100});
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => IdNameModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<IdNameModel>> fetchLabs() async {
    final res = await _client.dio.get(ApiEndpoints.labs);
    final data = res.data;
    final list = data is Map<String, dynamic> ? (data['data'] as List? ?? []) : (data as List? ?? []);
    return list.map((e) => IdNameModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<RecipeModel>> fetchRecipes({int? categoryId}) async {
    final res = await _client.dio.get(ApiEndpoints.manufacturingRecipes, queryParameters: {
      if (categoryId != null) 'category_id': categoryId,
      'active_only': 1,
      'per_page': 50,
    });
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => RecipeModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ProductionBatchSummaryModel>> fetchInProgressBatches() async {
    final res = await _client.dio.get(ApiEndpoints.manufacturingOrders, queryParameters: {
      'status': 'in_progress',
      'recipe_only': 1,
      'per_page': 20,
    });
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => ProductionBatchSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ProductionBatchSummaryModel>> fetchRecentlyCompletedBatches() async {
    final res = await _client.dio.get(ApiEndpoints.manufacturingOrders, queryParameters: {
      'status': 'completed',
      'recipe_only': 1,
      'per_page': 10,
    });
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => ProductionBatchSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<ProductionBatchDetailModel> fetchBatchDetail(int id) async {
    final res = await _client.dio.get('${ApiEndpoints.manufacturingOrders}/$id');
    return ProductionBatchDetailModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<String?> startProductionBatch({
    required int recipeId,
    int? categoryId,
    int? labId,
    String? notes,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> outputs,
    List<Map<String, dynamic>>? reentryMaterials,
    double? additionalExpense,
    int? expenseTreasuryId,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.manufacturingOrders, data: {
      'recipe_id': recipeId,
      if (categoryId != null) 'category_id': categoryId,
      if (labId != null) 'lab_id': labId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'materials': materials,
      'outputs': outputs,
      if (reentryMaterials != null && reentryMaterials.isNotEmpty)
        'reentry_materials': reentryMaterials,
      if (additionalExpense != null && additionalExpense > 0) 'additional_expense': additionalExpense,
      if (expenseTreasuryId != null) 'expense_treasury_id': expenseTreasuryId,
    });
    final data = res.data as Map<String, dynamic>;
    return data['batch_number'] as String?;
  }

  @override
  Future<void> completeProductionBatch({
    required int batchId,
    double? overheadFixed,
    double? overheadVariable,
    required List<Map<String, dynamic>> outputs,
  }) async {
    await _client.dio.post(ApiEndpoints.manufacturingComplete(batchId), data: {
      if (overheadFixed != null && overheadFixed > 0) 'overhead_fixed': overheadFixed,
      if (overheadVariable != null && overheadVariable > 0) 'overhead_variable': overheadVariable,
      'outputs': outputs,
    });
  }

  // ── Customer search (shared by "عملية بيع" and "تحصيل من عميل") ──────────

  @override
  Future<List<ClientModel>> searchCustomers(String query) async {
    final res = await _client.dio
        .get(ApiEndpoints.delegateClientSearch, queryParameters: {'query': query});
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ClientModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Admin sale ("عملية بيع") ─────────────────────────────────────────────

  @override
  Future<AdminSaleResultModel> submitAdminSale({
    required int customerId,
    required int treasuryId,
    int? warehouseId,
    required double cashReceived,
    String? notes,
    required List<Map<String, dynamic>> salesItems,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.adminSale, data: {
      'customer_id': customerId,
      'treasury_id': treasuryId,
      if (warehouseId != null) 'warehouse_id': warehouseId,
      'cash_received': cashReceived,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'sales_items': salesItems,
    });
    return AdminSaleResultModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Price edit ("تعديل سعر") ─────────────────────────────────────────────

  @override
  Future<List<RawMaterialModel>> fetchRawMaterials() async {
    final res = await _client.dio.get(ApiEndpoints.rawMaterials, queryParameters: {'per_page': 200});
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => RawMaterialModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<PriceUpdateResultModel> updateProductPrice(int productId, double newPrice) async {
    final res = await _client.dio
        .put(ApiEndpoints.adminProductPrice(productId), data: {'new_price': newPrice});
    return PriceUpdateResultModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<PriceUpdateResultModel> updateRawMaterialPrice(int rawMaterialId, double newPrice) async {
    final res = await _client.dio
        .put(ApiEndpoints.adminRawMaterialPrice(rawMaterialId), data: {'new_price': newPrice});
    return PriceUpdateResultModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── تحصيل/سداد من عميل (admin-initiated) ─────────────────────────────────

  @override
  Future<void> submitCustomerCollection({
    required int customerId,
    required int treasuryId,
    required double amount,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.adminCustomerCollection, data: {
      'customer_id': customerId,
      'treasury_id': treasuryId,
      'amount': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }
}
