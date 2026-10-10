import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../data/sync/delegate_sync_engine.dart';
import '../bloc/delegate_bloc.dart';
import '../../data/models/loading_model.dart';
import '../widgets/dashboard_section.dart';
import '../sync/delegate_sync_service.dart';
import 'invoice_page.dart';
import 'truck_stock_page.dart';
import 'invoice_history_page.dart';
import 'loading_page.dart';
import 'settlement_page.dart';
import 'sync_status_page.dart';
import 'transactions_page.dart';
import 'delegate_reports_page.dart';

/// Landing page for the delegate role. Always shows the performance dashboard
/// plus a lightweight "current shipment" status card; the full loading /
/// truck-stock / invoicing workflows are reached via bottom navigation and
/// remain completely untouched pages.
class DelegateHomePage extends StatefulWidget {
  const DelegateHomePage({super.key});

  @override
  State<DelegateHomePage> createState() => _DelegateHomePageState();
}

class _DelegateHomePageState extends State<DelegateHomePage> with WidgetsBindingObserver {
  int _tab = 0;
  // Loading/stock/settlement state lives in the shared DelegateSyncService
  // (see docs/delegate-state-flow.md) — this page no longer keeps a private
  // copy of the loading that only its own home-tab fetch could update.
  DelegateSyncService? _sync;
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
  // Same for معاملات: its shift expense/collection lists should reflect
  // whatever happened on OTHER tabs (e.g. settlement) since it was last seen.
  int _transactionsRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A delegate is signed in from here on: start the shared sync loop
    // (idempotent — didChangeDependencies runs again on inherited changes).
    _sync ??= DelegateSyncScope.of(context, listen: false);
    _sync!.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phase 3.2 sync trigger #1: the delegate reopening the app (e.g. after
    // regaining signal) is exactly when queued actions should attempt to
    // sync, without waiting for the connectivity-restored stream event
    // alone (which may have already fired while the app was backgrounded
    // and gone unobserved). (DelegateSyncService resyncs state on resume
    // by itself.)
    if (state == AppLifecycleState.resumed) {
      sl<DelegateSyncEngine>().syncNow();
    }
  }

  void _goToSell() => _selectTab(1);

  void _selectTab(int i) {
    final sync = _sync!;
    // A tab becoming visible is a sync trigger in its own right.
    sync.refreshNow();
    if (i == 1 && !sync.canSell) {
      AppSnackbar.showInfo(context, _cannotSellMessage(sync.lifecycle));
      return;
    }
    if (i == 4 && !sync.hasActiveLoading) {
      AppSnackbar.showInfo(
        context,
        sync.lifecycle == DelegateLifecycle.unknown
            ? 'جاري التحقق من حالة الشحنة…'
            : 'لا توجد شحنة نشطة حالياً — لا يوجد ما يمكن تسليمه.',
      );
      return;
    }
    setState(() {
      _tab = i;
      if (i == 4) _settlementRefreshTick++;
      if (i == 3) _invoiceHistoryRefreshTick++;
      if (i == 5) _transactionsRefreshTick++;
    });
  }

  static String _cannotSellMessage(DelegateLifecycle lifecycle) => switch (lifecycle) {
        DelegateLifecycle.unknown => 'جاري التحقق من حالة الشحنة…',
        DelegateLifecycle.pendingPickup => 'عندك شحنة جديدة بانتظار الاستلام — أكّد الاستلام أولاً لتبدأ البيع.',
        DelegateLifecycle.completed => 'تم إنهاء الجولة — لا يمكن البيع بعد الآن.',
        DelegateLifecycle.settlementRequested => 'بانتظار تأكيد التسليم من الإدارة.',
        DelegateLifecycle.settled => 'تمت تسوية الشحنة — لا توجد شحنة جديدة حالياً.',
        _ => 'لا توجد شحنة نشطة حالياً — لا يمكنك البيع الآن.',
      };

  // Unlike tabs 1/4, معاملات (index 5) is NOT gated at the tab-switch level:
  // TransactionsPage itself shows a persistent banner + disables its action
  // cards when !_canSell, which stays visible and explains why — clearer
  // than a transient snackbar blocking entry to a tab the user never sees.

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
    final sync = DelegateSyncScope.of(context);
    final canSell = sync.canSell;
    final hasActiveLoading = sync.hasActiveLoading;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            BlocBuilder<AppConfigBloc, AppConfigState>(
              builder: (_, state) {
                final logoUrl = state is AppConfigLoaded
                    ? (state.config.logoColorUrl ?? state.config.logoUrl)
                    : null;
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
          ValueListenableBuilder<int>(
            valueListenable: sl<PendingActionQueue>().pendingCountNotifier,
            builder: (context, count, __) {
              if (count == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'عمليات بانتظار المزامنة',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncStatusPage()),
                ),
                icon: Badge(
                  label: Text('$count'),
                  backgroundColor: AppTheme.accent,
                  child: const Icon(Icons.cloud_upload_outlined),
                ),
              );
            },
          ),
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
                color: canSell ? null : Colors.grey.shade400),
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
                color: hasActiveLoading ? null : Colors.grey.shade400),
            selectedIcon: const Icon(Icons.assignment_turned_in),
            label: 'تسليم',
          ),
          const NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'عمليات',
          ),
        ],
      ),
      // Each tab wrapped in TickerMode so hidden tabs count as not visible:
      // IndexedStack keeps every tab alive with tickers ON, and PollingMixin
      // (_HomeTab, SettlementPage) reads TickerMode to decide whether to
      // poll — without this both polled every 20s on whichever tab was shown.
      body: IndexedStack(
        index: _tab,
        children: [
          for (final (i, tab) in [
          _HomeTab(onGoToSell: _goToSell),
          BlocProvider.value(value: context.read<DelegateBloc>(), child: const InvoicePage()),
          BlocProvider.value(value: context.read<DelegateBloc>(), child: const TruckStockPage()),
          BlocProvider.value(
              value: context.read<DelegateBloc>(),
              child: InvoiceHistoryPage(
                  refreshTick: _invoiceHistoryRefreshTick, hasActiveLoading: canSell)),
          BlocProvider.value(
              value: context.read<DelegateBloc>(),
              child: SettlementPage(refreshTick: _settlementRefreshTick)),
          BlocProvider.value(
              value: context.read<DelegateBloc>(),
              child: TransactionsPage(
                  hasActiveLoading: canSell, refreshTick: _transactionsRefreshTick)),
          ].indexed)
            TickerMode(enabled: i == _tab, child: tab),
        ],
      ),
    );
  }
}

// ─── Home tab: dashboard + current-shipment status ──────────────────────────

class _HomeTab extends StatelessWidget {
  final VoidCallback onGoToSell;
  const _HomeTab({required this.onGoToSell});

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
    // Rebuilds whenever the shared sync state changes — no private fetch,
    // no private poller, no private cache read on this tab any more.
    final sync = DelegateSyncScope.of(context);
    return RefreshIndicator(
      // Fallback only — the state updates by itself.
      onRefresh: () => sync.refreshNow(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OfflineDataBanner(show: sync.activeLoading != null && sync.isShowingStaleData),
            const DashboardSection(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('الشحنة الحالية', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            _buildShipmentCard(context, sync),
            const SizedBox(height: 12),
            _ReportsEntryCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: context.read<DelegateBloc>(),
                    child: const DelegateReportsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildShipmentCard(BuildContext context, DelegateSyncService sync) {
    final loading = sync.activeLoading;
    switch (sync.lifecycle) {
      case DelegateLifecycle.unknown:
        // Never "no shipment" before the server has said so.
        if (sync.lastSyncFailed) {
          return Card(
            child: AppErrorView(
              title: 'تعذر تحميل حالة الشحنة',
              message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
              onRetry: () => sync.refreshNow(force: true),
            ),
          );
        }
        return const Card(
          key: Key('shipment-skeleton'),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSkeletonBox(height: 18, width: 180),
                SizedBox(height: 10),
                AppSkeletonBox(height: 14, width: 120),
                SizedBox(height: 14),
                AppSkeletonBox(height: 40),
              ],
            ),
          ),
        );
      case DelegateLifecycle.none:
        return _NoShipmentCard(
          title: 'لا توجد شحنة',
          subtitle: 'سيتم تعيين شحنة لك من الإدارة عند الحاجة.',
          onRefresh: () => sync.refreshNow(force: true),
        );
      case DelegateLifecycle.settled:
        return _NoShipmentCard(
          title: 'تمت تسوية الشحنة',
          subtitle: 'لا توجد شحنة جديدة حالياً — ستظهر هنا تلقائياً عند تعيينها.',
          icon: Icons.verified_outlined,
          onRefresh: () => sync.refreshNow(force: true),
        );
      case DelegateLifecycle.pendingPickup:
      case DelegateLifecycle.accepted:
      case DelegateLifecycle.inTransit:
      case DelegateLifecycle.completed:
      case DelegateLifecycle.settlementRequested:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sync.lifecycle == DelegateLifecycle.pendingPickup)
              _StateNotice(
                key: const Key('notice-pending-pickup'),
                icon: Icons.local_shipping_outlined,
                text: 'عندك شحنة جديدة بانتظار الاستلام',
                actionLabel: 'مراجعة وتأكيد الاستلام',
                onAction: () => _openDetails(context),
              ),
            if (sync.lifecycle == DelegateLifecycle.settlementRequested)
              const _StateNotice(
                key: Key('notice-settlement-requested'),
                icon: Icons.hourglass_top_rounded,
                text: 'بانتظار تأكيد التسليم من الإدارة',
              ),
            _ShipmentSummaryCard(
              loading: loading!,
              onGoToSell: onGoToSell,
              onRefresh: () => sync.refreshNow(force: true),
            ),
          ],
        );
    }
  }
}

class _NoShipmentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onRefresh;
  const _NoShipmentCard({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: Colors.grey.shade500, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث',
                onPressed: onRefresh,
              ),
            ],
          ),
        ),
      );
}

/// A one-line state banner above the shipment card (same visual language as
/// the pending top-up notice inside it).
class _StateNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _StateNotice({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      );
}

// ─── Reports entry point ─────────────────────────────────────────────────────

/// Reached from a Home-tab card rather than a 7th bottom-nav destination —
/// six tabs (الرئيسية/البيع/المخزون/الفواتير/تسليم/معاملات) is already a lot
/// for a NavigationBar to carry legibly, and unlike those, reports isn't a
/// workflow step a delegate repeats many times a shift; it's an occasional
/// look-up, same category as العمولة/الجزاءات/السلف which already live as
/// tappable cards off the dashboard rather than as tabs.
class _ReportsEntryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ReportsEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: AppTheme.primary, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('التقارير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 2),
                      Text('تقارير المناطق والأصناف لمبيعاتك',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      );
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
    // Background fill behind white badge text — needs to stay dark enough
    // for that text to stay readable (bare Colors.grey/500 fails contrast
    // with white text on top; shade600 keeps ~4.6:1).
    return Colors.grey.shade600;
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
            // Mid-shift top-up (Part 5) awaiting confirmation — surfaced
            // here too (not just inside LoadingPage) so it's visible right
            // on the home tab without navigating in first. The actual
            // confirm action lives in LoadingPage/_PendingAdditionCard —
            // this is a tap-through notice, not a duplicate action flow.
            if (loading.pendingAdditions.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _openDetails(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_shopping_cart_rounded, color: AppTheme.accent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تمت إضافة منتجات جديدة للشحنة — اضغط للمراجعة والتأكيد',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded, color: AppTheme.accent),
                    ],
                  ),
                ),
              ),
            ],
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
