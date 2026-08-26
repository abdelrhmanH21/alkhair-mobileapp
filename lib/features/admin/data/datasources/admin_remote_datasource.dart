import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../delegate/data/models/breakdown_models.dart';
import '../../../delegate/data/models/client_model.dart';
import '../../../delegate/data/models/customer_region_model.dart';
import '../models/admin_models.dart';

abstract class AdminRemoteDataSource {
  Future<DashboardStatsModel> fetchDashboard();
  Future<IndicatorTrendModel> fetchIndicatorTrend({required String type, required String period});
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
  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
    int? customerRegionId,
  });
  Future<SupplierModel> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    double? balance,
  });
  Future<void> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
  });

  // ── مناطق التوزيع (CustomerRegion) ───────────────────────────────────────
  Future<List<CustomerRegionModel>> fetchAllCustomerRegions();
  Future<void> createCustomerRegion(String name);
  Future<void> updateCustomerRegion({
    required int id,
    String? name,
    bool? isActive,
  });

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
  Future<List<BonusModel>> fetchRepBonuses(int repId);

  // ── Settlement history (سجل التسويات) ──────────────────────────────────
  Future<SettlementRecordPageModel> fetchSettlementHistory({
    int? delegateId,
    String? dateFrom,
    String? dateTo,
    int page = 1,
  });
  Future<DailySummaryModel> fetchDailySummary(int settlementId);
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

  // ── عملية شراء ────────────────────────────────────────────────────────
  Future<void> submitPurchase({
    int? supplierId,
    int? labId,
    required int treasuryId,
    required String purchaseDate,
    required double paidAmount,
    String? notes,
    required List<Map<String, dynamic>> items,
  });

  // ── عملية سداد لمورد ──────────────────────────────────────────────────
  Future<void> submitSupplierPayment({
    required int supplierId,
    required int treasuryId,
    required double amount,
    String? notes,
  });

  // ── تسجيل هالك ────────────────────────────────────────────────────────
  Future<void> submitWaste({
    required String itemType,
    int? productId,
    int? rawMaterialId,
    required int warehouseId,
    required double quantity,
    required String reason,
  });

  // ── عملية جرد ─────────────────────────────────────────────────────────
  Future<List<InventoryCountItemModel>> fetchInventoryCountItems(int warehouseId);
  Future<double> submitInventoryCount({
    required int warehouseId,
    String? notes,
    required String settlementType,
    int? treasuryId,
    int? customerId,
    required List<Map<String, dynamic>> counts,
  });

  // ── جرد الخزائن ("جرد التصنيع"/VaultAuditController) ─────────────────────
  Future<List<VaultAuditModel>> fetchVaultAudits({int? treasuryId});
  Future<double> submitVaultAudit({
    required int treasuryId,
    required double physicalBalance,
    String? notes,
  });

  // ── جرد المديونيات / جرد ديون الموردين (DebtAuditController) ─────────────
  Future<List<DebtAuditModel>> fetchDebtAudits(String clientType);
  Future<double> submitDebtAudit({
    required String clientType,
    required int entityId,
    required double physicalBalance,
    String? notes,
  });

  // ── عمليات العمالة (جزاء / سلفة / مكافأة) ────────────────────────────────
  Future<List<StaffModel>> fetchAllStaff();
  Future<void> submitStaffOperation({
    required int salesRepId,
    required String operationType,
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
  Future<IndicatorTrendModel> fetchIndicatorTrend({required String type, required String period}) async {
    final res = await _client.dio.get(
      ApiEndpoints.adminIndicatorTrend,
      queryParameters: {'type': type, 'period': period},
    );
    return IndicatorTrendModel.fromJson(res.data as Map<String, dynamic>);
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

  @override
  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
    int? customerRegionId,
  }) async {
    await _client.dio.put('${ApiEndpoints.customers}/$id', data: {
      'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (customerRegionId != null) 'customer_region_id': customerRegionId,
    });
  }

  @override
  Future<SupplierModel> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    double? balance,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.suppliers, data: {
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (address != null && address.isNotEmpty) 'address': address,
      if (balance != null) 'balance': balance,
    });
    return SupplierModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<void> updateSupplier({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
  }) async {
    await _client.dio.put('${ApiEndpoints.suppliers}/$id', data: {
      'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
    });
  }

  // ── مناطق التوزيع (CustomerRegion) ───────────────────────────────────────

  @override
  Future<List<CustomerRegionModel>> fetchAllCustomerRegions() async {
    final res = await _client.dio
        .get(ApiEndpoints.customerRegions, queryParameters: {'per_page': 500});
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => CustomerRegionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> createCustomerRegion(String name) async {
    await _client.dio.post(ApiEndpoints.customerRegions, data: {'name': name});
  }

  @override
  Future<void> updateCustomerRegion({
    required int id,
    String? name,
    bool? isActive,
  }) async {
    await _client.dio.put('${ApiEndpoints.customerRegions}/$id', data: {
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
    });
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

  // ── Settlement history (سجل التسويات) ──────────────────────────────────

  @override
  Future<SettlementRecordPageModel> fetchSettlementHistory({
    int? delegateId,
    String? dateFrom,
    String? dateTo,
    int page = 1,
  }) async {
    final res = await _client.dio.get(ApiEndpoints.adminSettlementHistory, queryParameters: {
      'page': page,
      if (delegateId != null) 'delegate_id': delegateId,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return SettlementRecordPageModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<DailySummaryModel> fetchDailySummary(int settlementId) async {
    final res = await _client.dio.get(ApiEndpoints.adminDailySummary(settlementId));
    return DailySummaryModel.fromJson(res.data as Map<String, dynamic>);
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
  Future<List<BonusModel>> fetchRepBonuses(int repId) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegateBonuses,
      queryParameters: {'rep_id': repId},
    );
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => BonusModel.fromJson(e as Map<String, dynamic>)).toList();
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

  // ── عملية شراء ────────────────────────────────────────────────────────

  @override
  Future<void> submitPurchase({
    int? supplierId,
    int? labId,
    required int treasuryId,
    required String purchaseDate,
    required double paidAmount,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    await _client.dio.post(ApiEndpoints.adminPurchase, data: {
      if (supplierId != null) 'supplier_id': supplierId,
      if (labId != null) 'lab_id': labId,
      'treasury_id': treasuryId,
      'purchase_date': purchaseDate,
      'paid_amount': paidAmount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'items': items,
    });
  }

  // ── عملية سداد لمورد ──────────────────────────────────────────────────

  @override
  Future<void> submitSupplierPayment({
    required int supplierId,
    required int treasuryId,
    required double amount,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.adminSupplierPayment, data: {
      'supplier_id': supplierId,
      'treasury_id': treasuryId,
      'amount': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  // ── تسجيل هالك ────────────────────────────────────────────────────────

  @override
  Future<void> submitWaste({
    required String itemType,
    int? productId,
    int? rawMaterialId,
    required int warehouseId,
    required double quantity,
    required String reason,
  }) async {
    await _client.dio.post(ApiEndpoints.adminWaste, data: {
      'item_type': itemType,
      if (productId != null) 'product_id': productId,
      if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
      'warehouse_id': warehouseId,
      'quantity': quantity,
      'reason': reason,
    });
  }

  // ── عملية جرد ─────────────────────────────────────────────────────────

  @override
  Future<List<InventoryCountItemModel>> fetchInventoryCountItems(int warehouseId) async {
    final res = await _client.dio.get(
      ApiEndpoints.adminInventoryCountItems,
      queryParameters: {'warehouse_id': warehouseId},
    );
    final list = (res.data as Map<String, dynamic>)['items'] as List? ?? [];
    return list.map((e) => InventoryCountItemModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<double> submitInventoryCount({
    required int warehouseId,
    String? notes,
    required String settlementType,
    int? treasuryId,
    int? customerId,
    required List<Map<String, dynamic>> counts,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.adminInventoryCount, data: {
      'warehouse_id': warehouseId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'settlement_type': settlementType,
      if (treasuryId != null) 'treasury_id': treasuryId,
      if (customerId != null) 'customer_id': customerId,
      'counts': counts,
    });
    final data = res.data as Map<String, dynamic>;
    return (data['total_variance_value'] as num? ?? 0).toDouble();
  }

  // ── جرد الخزائن ───────────────────────────────────────────────────────

  @override
  Future<List<VaultAuditModel>> fetchVaultAudits({int? treasuryId}) async {
    final res = await _client.dio.get(ApiEndpoints.vaultAudits, queryParameters: {
      'per_page': 30,
      if (treasuryId != null) 'treasury_id': treasuryId,
    });
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => VaultAuditModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<double> submitVaultAudit({
    required int treasuryId,
    required double physicalBalance,
    String? notes,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.vaultAudits, data: {
      'treasury_id': treasuryId,
      'physical_balance': physicalBalance,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    final audit = (res.data as Map<String, dynamic>)['audit'] as Map<String, dynamic>;
    return (audit['variance'] as num? ?? 0).toDouble();
  }

  // ── جرد المديونيات / جرد ديون الموردين ───────────────────────────────────

  @override
  Future<List<DebtAuditModel>> fetchDebtAudits(String clientType) async {
    final res = await _client.dio.get(ApiEndpoints.debtAudits, queryParameters: {
      'client_type': clientType,
      'per_page': 30,
    });
    final list = (res.data as Map<String, dynamic>)['data'] as List? ?? [];
    return list.map((e) => DebtAuditModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<double> submitDebtAudit({
    required String clientType,
    required int entityId,
    required double physicalBalance,
    String? notes,
  }) async {
    final idField = clientType == 'supplier' ? 'supplier_id' : 'customer_id';
    final res = await _client.dio.post(ApiEndpoints.debtAudits, data: {
      'client_type': clientType,
      idField: entityId,
      'physical_balance': physicalBalance,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return ((res.data as Map<String, dynamic>)['variance'] as num? ?? 0).toDouble();
  }

  // ── عمليات العمالة (جزاء / سلفة / مكافأة) ────────────────────────────────

  @override
  Future<List<StaffModel>> fetchAllStaff() async {
    final res = await _client.dio
        .get(ApiEndpoints.salesReps, queryParameters: {'active_only': 1});
    final list = res.data as List? ?? [];
    return list.map((e) => StaffModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> submitStaffOperation({
    required int salesRepId,
    required String operationType,
    required double amount,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.adminStaffOperations, data: {
      'sales_rep_id': salesRepId,
      'operation_type': operationType,
      'amount': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }
}
