class ApiEndpoints {
  static const String baseUrl = 'http://10.0.2.2:8080/api';

  // Auth
  static const String login  = '/v1/mobile/auth/login';
  static const String logout = '/v1/mobile/auth/logout';
  static const String me     = '/v1/mobile/auth/me';

  // Delegate — loading
  static const String delegateLoading        = '/v1/mobile/delegate/loading';
  static const String delegateLoadingConfirm = '/v1/mobile/delegate/loading/confirm';
  static const String delegateTruckStock     = '/v1/mobile/delegate/truck-stock';

  // Delegate — clients
  static const String delegateClients       = '/v1/mobile/delegate/clients';
  static const String delegateClientSearch  = '/v1/mobile/delegate/clients/search';

  // Delegate — invoices
  static const String delegateInvoice  = '/v1/mobile/delegate/invoice';
  static const String delegateInvoices = '/v1/mobile/delegate/invoices';

  // Admin
  static const String adminDelegates    = '/v1/mobile/admin/delegates';
  static const String adminDashboard    = '/v1/mobile/admin/dashboard';
  static const String adminShiftSummary = '/v1/mobile/admin/delegate/shift-summary';
  static const String adminSettle       = '/v1/mobile/admin/settle-delegate';
  static const String adminLoadings     = '/v1/mobile/admin/loadings';
}
