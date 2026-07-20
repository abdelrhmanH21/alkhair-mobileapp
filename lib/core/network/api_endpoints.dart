class ApiEndpoints {
  static const String baseUrl = 'https://accounting.alkhairdairies.com/api/v1/mobile';

  // Root API (non-mobile-prefixed, shared reference-data endpoints).
  // Dio treats an absolute "http..." path as-is and ignores baseUrl.
  static const String apiRoot = 'https://accounting.alkhairdairies.com/api';

  // Public
  static const String appSettings = '/app-settings';

  // Auth
  static const String login  = '/auth/login';
  static const String logout = '/auth/logout';
  static const String me     = '/auth/me';

  // Push notifications
  static const String registerDeviceToken     = '/register-device-token';
  static const String notificationPreferences = '/notification-preferences';

  // Delegate — loading
  static const String delegateLoading        = '/delegate/loading';
  static const String delegateLoadingConfirm = '/delegate/loading/confirm';
  static const String delegateTruckStock     = '/delegate/truck-stock';
  static const String delegateDashboard      = '/delegate/dashboard';
  static const String delegateSellableProducts = '/delegate/sellable-products';
  static const String delegateShiftSummary      = '/delegate/shift-summary';
  static const String delegateSettlementRequest = '/delegate/settlement-request';
  static const String delegatePenalties            = '/delegate/penalties';
  static const String delegateAdvances             = '/delegate/advances';
  static const String delegateCommissionBreakdown  = '/delegate/commission-breakdown';

  // Delegate — clients
  static const String delegateClients       = '/delegate/clients';
  static const String delegateClientSearch  = '/delegate/clients/search';
  static String delegateCustomerInvoiceHistory(int customerId) =>
      '/delegate/customers/$customerId/invoices';

  // Shared reference data (root API, not under /v1/mobile)
  static const String products        = '$apiRoot/products';
  static const String customerRegions = '$apiRoot/customer-regions';
  static const String expenses        = '$apiRoot/expenses';
  static const String treasuries      = '$apiRoot/treasuries';
  static const String expenseItems    = '$apiRoot/expense-items';
  static const String customers       = '$apiRoot/customers';
  static const String suppliers       = '$apiRoot/suppliers';

  // Delegate — invoices
  static const String delegateInvoice  = '/delegate/invoice';
  static const String delegateInvoices = '/delegate/invoices';
  static String delegateInvoiceUpdate(int id) => '/delegate/invoice/$id';

  // Delegate — transactions (معاملات)
  static const String delegateExpenses            = '/delegate/expenses';
  static const String delegateCustomerCollections = '/delegate/customer-collections';
  static String delegateExpense(int id) => '/delegate/expenses/$id';
  static String delegateCustomerCollection(int id) => '/delegate/customer-collections/$id';

  // Delegate — reports (التقارير)
  static const String delegateReportsByRegion  = '/delegate/reports/by-region';
  static const String delegateReportsByProduct = '/delegate/reports/by-product';

  // Delegate — trip status update (id injected at call site)
  static String delegateLoadingStatus(int id) => '/delegate/loading/$id/status';

  // Admin
  static const String adminDelegates    = '/admin/delegates';
  static const String adminDashboard    = '/admin/dashboard';
  static const String adminShiftSummary = '/admin/delegate/shift-summary';
  static const String adminSettle       = '/admin/settle-delegate';
  static const String adminLoadings     = '/admin/loadings';
  static const String adminProducts     = '/admin/products';
  static const String adminWarehouses   = '/admin/warehouses';
}
