import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/polling_mixin.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/loading_model.dart';
import '../widgets/dashboard_section.dart';
import 'invoice_page.dart';
import 'truck_stock_page.dart';
import 'invoice_history_page.dart';
import 'loading_page.dart';
import 'settlement_page.dart';

/// Landing page for the delegate role. Always shows the performance dashboard
/// plus a lightweight "current shipment" status card; the full loading /
/// truck-stock / invoicing workflows are reached via bottom navigation and
/// remain completely untouched pages.
class DelegateHomePage extends StatefulWidget {
  const DelegateHomePage({super.key});

  @override
  State<DelegateHomePage> createState() => _DelegateHomePageState();
}

class _DelegateHomePageState extends State<DelegateHomePage> {
  int _tab = 0;
  LoadingModel? _loading;
  // SettlementPage lives inside an IndexedStack that builds every tab once
  // and keeps it alive for the whole session, so its initState() fetch only
  // ever runs at home-page mount — typically before any sales exist yet.
  // Bumping this each time the settlement tab is (re)selected lets
  // SettlementPage detect "I just became visible again" via didUpdateWidget
  // and refetch, instead of showing the stale first-load snapshot forever.
  int _settlementRefreshTick = 0;
  // Same IndexedStack-staleness issue affects the invoice history tab: a
  // freshly-submitted invoice wouldn't show up there until app restart.
  int _invoiceHistoryRefreshTick = 0;

  bool get _canSell => _loading?.isActiveForSales == true;
  bool get _hasActiveLoading => _loading != null;

  void _goToSell() => _selectTab(1);

  void _selectTab(int i) {
    if (i == 1 && !_canSell) {
      AppSnackbar.showInfo(context, 'لا توجد تحميلة نشطة حالياً — لا يمكنك البيع الآن.');
      return;
    }
    if (i == 4 && !_hasActiveLoading) {
      AppSnackbar.showInfo(context, 'لا توجد تحميلة نشطة حالياً — لا يوجد ما يمكن تسليمه.');
      return;
    }
    setState(() {
      _tab = i;
      if (i == 4) _settlementRefreshTick++;
      if (i == 3) _invoiceHistoryRefreshTick++;
    });
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الخروج'),
        content: const Text('هل تريد تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            child: const Text('خروج'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userName = authState is AuthAuthenticated ? authState.user.name : '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            BlocBuilder<AppConfigBloc, AppConfigState>(
              builder: (_, state) {
                final logoUrl = state is AppConfigLoaded ? state.config.logoUrl : null;
                return AppLogo(logoUrl: logoUrl, size: 34, borderRadius: 8);
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlocBuilder<AppConfigBloc, AppConfigState>(
                    builder: (_, state) {
                      final name = state is AppConfigLoaded && state.config.companyName.isNotEmpty
                          ? state.config.companyName
                          : 'الخير للألبان';
                      return Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white));
                    },
                  ),
                  Text(userName,
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined,
                color: _canSell ? null : Colors.grey.shade400),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: 'البيع',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'المخزون',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'الفواتير',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_turned_in_outlined,
                color: _hasActiveLoading ? null : Colors.grey.shade400),
            selectedIcon: const Icon(Icons.assignment_turned_in),
            label: 'تسليم',
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _HomeTab(
            onGoToSell: _goToSell,
            onLoadingChanged: (l) => setState(() => _loading = l),
          ),
          BlocProvider.value(value: context.read<DelegateBloc>(), child: const InvoicePage()),
          BlocProvider.value(value: context.read<DelegateBloc>(), child: const TruckStockPage()),
          BlocProvider.value(
              value: context.read<DelegateBloc>(),
              child: InvoiceHistoryPage(refreshTick: _invoiceHistoryRefreshTick)),
          BlocProvider.value(
              value: context.read<DelegateBloc>(),
              child: SettlementPage(refreshTick: _settlementRefreshTick)),
        ],
      ),
    );
  }
}

// ─── Home tab: dashboard + current-shipment status ──────────────────────────

class _HomeTab extends StatefulWidget {
  final VoidCallback onGoToSell;
  final ValueChanged<LoadingModel?> onLoadingChanged;
  const _HomeTab({required this.onGoToSell, required this.onLoadingChanged});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with PollingMixin<_HomeTab> {
  LoadingModel? _loading;
  String? _loadingError;
  bool _hasLoadingResult = false;

  // See DashboardSection for the same pattern: the dashboard fetch and this
  // shipment fetch share one DelegateBloc, and flutter_bloc's default
  // transformer processes events strictly in dispatch order — so we only
  // dispatch the shipment fetch once we've observed the dashboard fetch's
  // own first Loaded/Failure, keeping the two requests non-overlapping and
  // their DelegateFailure results unambiguous.
  bool _dashboardSettled = false;

  // Set while a silent PollingMixin tick's fetch is outstanding, so its
  // result can be told apart from the explicit initial/manual fetch.
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  @override
  void onPoll() {
    // Nothing to refresh yet, or an explicit fetch/dashboard sequencing is
    // still in progress — let that settle first rather than overlapping.
    if (!_dashboardSettled || _pollInFlight) return;
    _pollInFlight = true;
    context.read<DelegateBloc>().add(DelegateLoadingFetched());
  }

  void _fetchLoading() {
    setState(() => _loadingError = null);
    context.read<DelegateBloc>().add(DelegateLoadingFetched());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (_, state) {
        final dashboardWasSettled = _dashboardSettled;
        if (!dashboardWasSettled) {
          if (state is DelegateDashboardLoaded || state is DelegateFailure) {
            _dashboardSettled = true;
            _fetchLoading();
          }
          return;
        }
        if (state is DelegateLoadingLoaded) {
          _pollInFlight = false;
          setState(() {
            _loading = state.loading;
            _loadingError = null;
            _hasLoadingResult = true;
          });
          widget.onLoadingChanged(state.loading);
        } else if (state is DelegateFailure) {
          if (_pollInFlight) {
            _pollInFlight = false;
            if (_loading == null) {
              // No good data to protect — safe to show/update the error.
              setState(() {
                _loadingError = state.message;
                _hasLoadingResult = true;
              });
            }
            // else: silent — keep showing the last-good shipment card,
            // retry next tick, per PollingMixin's contract.
          } else {
            setState(() {
              _loadingError = state.message;
              _hasLoadingResult = true;
            });
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DashboardSection(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('الشحنة الحالية', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            _buildShipmentCard(context),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildShipmentCard(BuildContext context) {
    if (!_hasLoadingResult && _loadingError == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_loadingError != null) {
      return Card(
        child: AppErrorView(
          title: 'تعذر تحميل حالة التحميلة',
          message: _loadingError!,
          onRetry: _fetchLoading,
        ),
      );
    }

    final loading = _loading;
    if (loading == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, color: Colors.grey.shade500, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('لا توجد تحميلة نشطة حاليًا',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text('سيتم تعيين تحميلة لك من المدير عند الحاجة.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث',
                onPressed: _fetchLoading,
              ),
            ],
          ),
        ),
      );
    }

    return _ShipmentSummaryCard(
      loading: loading,
      onGoToSell: widget.onGoToSell,
      onRefresh: _fetchLoading,
    );
  }
}

// ─── Shipment summary card (links out to the untouched LoadingPage) ────────

class _ShipmentSummaryCard extends StatelessWidget {
  final LoadingModel loading;
  final VoidCallback onGoToSell;
  final VoidCallback onRefresh;

  const _ShipmentSummaryCard({
    required this.loading,
    required this.onGoToSell,
    required this.onRefresh,
  });

  Color get _statusColor {
    if (loading.isPendingPickup) return AppTheme.accent;
    if (loading.isAccepted || loading.isInTransit) return AppTheme.primary;
    if (loading.isCompleted) return AppTheme.secondary;
    return Colors.grey;
  }

  String get _statusLabel {
    if (loading.isPendingPickup) return 'بانتظار الاستلام';
    if (loading.isAccepted) return 'مستلمة';
    if (loading.isInTransit) return 'في الطريق';
    if (loading.isCompleted) return 'مكتملة';
    return loading.status;
  }

  void _openDetails(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: context.read<DelegateBloc>(),
            child: const LoadingPage(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final canSell = loading.isActiveForSales;
    return Card(
      elevation: AppTheme.elevationMed,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping_rounded, color: _statusColor, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مستودع: ${loading.warehouseName}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('${loading.items.length} منتج',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabel,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openDetails(context),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('عرض التفاصيل'),
                  ),
                ),
                if (canSell) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onGoToSell,
                      icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                      label: const Text('بدء البيع'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
