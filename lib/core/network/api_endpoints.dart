class ApiEndpoints {
  static const String baseUrl = 'https://accounting.alkhairdairies.com/api/v1/mobile';

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

  // Delegate — clients
  static const String delegateClients       = '/delegate/clients';
  static const String delegateClientSearch  = '/delegate/clients/search';

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
