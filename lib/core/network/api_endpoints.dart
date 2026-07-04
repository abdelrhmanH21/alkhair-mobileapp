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

  // Delegate — loading
  static const String delegateLoading        = '/delegate/loading';
  static const String delegateLoadingConfirm = '/delegate/loading/confirm';
  static const String delegateTruckStock     = '/delegate/truck-stock';
  static const String delegateDashboard      = '/delegate/dashboard';
  static const String delegateSellableProducts = '/delegate/sellable-products';

  // Delegate — clients
  static const String delegateClients       = '/delegate/clients';
  static const String delegateClientSearch  = '/delegate/clients/search';

  // Shared reference data (root API, not under /v1/mobile)
  static const String products        = '$apiRoot/products';
  static const String customerRegions = '$apiRoot/customer-regions';

  // Delegate — invoices
  static const String delegateInvoice  = '/delegate/invoice';
  static const String delegateInvoices = '/delegate/invoices';

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
