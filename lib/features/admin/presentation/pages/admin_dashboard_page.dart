import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
// delegates_page.dart is a re-export barrel; no additional imports needed
import 'settle_delegate_page.dart';
import 'create_loading_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(AdminDashboardFetched());
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userName = authState is AuthAuthenticated ? authState.user.name : '';

    return Scaffold(
      drawer: _AdminDrawer(userName: userName),
      appBar: AppBar(
        title: const Text('لوحة تحكم الإدارة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('تأكيد الخروج'),
                  content: const Text('هل تريد تسجيل الخروج؟'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء')),
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
            },
          ),
        ],
      ),
      floatingActionButton: _currentTab == 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: context.read<AdminBloc>(),
                    child: const CreateLoadingPage(),
                  ),
                ),
              ).then((_) =>
                  context.read<AdminBloc>().add(AdminDelegatesFetched())),
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('تحميلة جديدة'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) {
          setState(() => _currentTab = i);
          if (i == 0) context.read<AdminBloc>().add(AdminDashboardFetched());
          if (i == 1) context.read<AdminBloc>().add(AdminDelegatesFetched());
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'الرئيسية'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'متابعة المناديب'),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _DashboardTab(userName: userName),
          const _DelegatesTab(),
        ],
      ),
    );
  }
}

// ─── Admin Drawer ──────────────────────────────────────────────────────────────

class _AdminDrawer extends StatefulWidget {
  final String userName;
  const _AdminDrawer({required this.userName});

  @override
  State<_AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<_AdminDrawer> {
  bool _salesNotificationsEnabled = true;
  bool _updatingPreference = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _salesNotificationsEnabled = authState.user.salesNotificationsEnabled;
    }
  }

  Future<void> _togglePreference(bool value) async {
    setState(() {
      _salesNotificationsEnabled = value;
      _updatingPreference = true;
    });
    try {
      await sl<AdminRemoteDataSource>().updateNotificationPreference(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salesNotificationsEnabled = !value);
      AppSnackbar.showError(context, 'فشل تحديث تفضيلات الإشعارات.');
    } finally {
      if (mounted) setState(() => _updatingPreference = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: BlocBuilder<AppConfigBloc, AppConfigState>(
        builder: (_, configState) {
          final logoUrl = configState is AppConfigLoaded
              ? (configState.config.logoColorUrl ?? configState.config.logoUrl)
              : null;
          final companyName = configState is AppConfigLoaded &&
                  configState.config.companyName.isNotEmpty
              ? configState.config.companyName
              : 'الخير للألبان';

          return Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: AppTheme.primary),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogo(logoUrl: logoUrl, size: 72, borderRadius: 16),
                    const SizedBox(height: 10),
                    Text(
                      companyName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.userName,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('إشعارات المبيعات'),
                value: _salesNotificationsEnabled,
                onChanged: _updatingPreference ? null : _togglePreference,
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('تسجيل الخروج'),
                onTap: () {
                  Navigator.pop(context);
                  context.read<AuthBloc>().add(AuthLogoutRequested());
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Dashboard Tab ─────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final String userName;
  const _DashboardTab({required this.userName});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AdminBloc, AdminState>(
        builder: (_, state) {
          if (state is AdminLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AdminDashboardLoaded) {
            return _DashboardContent(
                stats: state.stats, userName: userName);
          }
          if (state is AdminFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message,
                      style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.read<AdminBloc>().add(AdminDashboardFetched()),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      );
}

class _DashboardContent extends StatelessWidget {
  final DashboardStatsModel stats;
  final String userName;
  const _DashboardContent({required this.stats, required this.userName});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async =>
            context.read<AdminBloc>().add(AdminDashboardFetched()),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'مرحباً، $userName',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Text('إحصائيات اليوم',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),

              _WorkingCapitalSection(
                total: stats.workingCapital,
                breakdown: stats.workingCapitalBreakdown,
              ),
              const SizedBox(height: 20),

              // KPI grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _KpiCard(
                    label: 'الفواتير اليوم',
                    value: stats.todayInvoicesCount.toString(),
                    icon: Icons.receipt_long_outlined,
                    color: AppTheme.primary,
                  ),
                  _KpiCard(
                    label: 'إجمالي المبيعات',
                    value: stats.todayGrossSales.toStringAsFixed(0),
                    icon: Icons.trending_up_rounded,
                    color: AppTheme.secondary,
                  ),
                  _KpiCard(
                    label: 'النقد المحصل',
                    value: stats.todayCashCollected.toStringAsFixed(0),
                    icon: Icons.payments_outlined,
                    color: Colors.teal,
                  ),
                  _KpiCard(
                    label: 'ديون جديدة',
                    value: stats.todayNewDebt.toStringAsFixed(0),
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppTheme.danger,
                  ),
                  _KpiCard(
                    label: 'تحميلات نشطة',
                    value: stats.activeLoadings.toString(),
                    icon: Icons.local_shipping_outlined,
                    color: AppTheme.accent,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (stats.topProducts.isNotEmpty) ...[
                const Text('أكثر المنتجات مبيعاً اليوم',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: stats.topProducts
                        .asMap()
                        .entries
                        .map((e) => ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.1),
                                child: Text('${e.key + 1}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primary)),
                              ),
                              title: Text(e.value.name,
                                  style: const TextStyle(fontSize: 13)),
                              trailing: Text(
                                '${e.value.totalQty.toStringAsFixed(0)} وحدة',
                                style: const TextStyle(
                                    color: AppTheme.primary, fontSize: 12),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      );
}

// ─── Working Capital Section ────────────────────────────────────────────────

class _WorkingCapitalSection extends StatelessWidget {
  final double total;
  final WorkingCapitalBreakdownModel breakdown;
  const _WorkingCapitalSection({required this.total, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    // Positive components make up the donut; payables is a deduction shown
    // separately below since a slice can't represent a subtraction.
    final components = <_WcComponent>[
      _WcComponent('نقدية بالخزائن', breakdown.cash, AppTheme.primary),
      _WcComponent('مواد خام', breakdown.rawMaterials, AppTheme.secondary),
      _WcComponent('منتجات تامة', breakdown.finishedGoods, AppTheme.accent),
      _WcComponent('ذمم مدينة (عملاء)', breakdown.receivables, Colors.teal),
    ].where((c) => c.value > 0).toList();
    final componentsTotal = components.fold<double>(0, (s, c) => s + c.value);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('إجمالي رأس المال المتداول',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              if (total < 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('سالب',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            total.toStringAsFixed(0),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (componentsTotal > 0)
            Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 26,
                      sections: components
                          .map((c) => PieChartSectionData(
                                value: c.value,
                                color: c.color,
                                radius: 20,
                                showTitle: false,
                              ))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: components
                        .map((c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: c.color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(c.label,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 11)),
                                  ),
                                  Text(
                                    c.value.toStringAsFixed(0),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          if (breakdown.payables > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.remove_circle_outline,
                    color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                const Text('مطلوبات (دائنون) — تُخصم من الإجمالي',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                const Spacer(),
                Text(
                  '- ${breakdown.payables.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WcComponent {
  final String label;
  final double value;
  final Color color;
  const _WcComponent(this.label, this.value, this.color);
}

// ─── Delegates Tab ─────────────────────────────────────────────────────────────

class _DelegatesTab extends StatelessWidget {
  const _DelegatesTab();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AdminBloc, AdminState>(
        builder: (_, state) {
          if (state is AdminLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AdminDelegatesLoaded) {
            return _DelegatesList(delegates: state.delegates);
          }
          if (state is AdminFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message,
                      style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<AdminBloc>().add(AdminDelegatesFetched()),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          return const Center(
            child: Text('اضغط على قائمة المندوبين للتحميل',
                style: TextStyle(color: Colors.grey)),
          );
        },
      );
}

class _DelegatesList extends StatelessWidget {
  final List<DelegateModel> delegates;
  const _DelegatesList({required this.delegates});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async =>
            context.read<AdminBloc>().add(AdminDelegatesFetched()),
        child: ListView.builder(
          itemCount: delegates.length,
          itemBuilder: (_, i) {
            final d = delegates[i];
            final badge = _statusBadge(d.trackingStatus);
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: badge.color.withValues(alpha: 0.15),
                  child: Icon(Icons.person_rounded, color: badge.color),
                ),
                title: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(d.email,
                    style: const TextStyle(fontSize: 12)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge.label,
                    style: TextStyle(fontSize: 10, color: badge.color),
                  ),
                ),
                onTap: () => _openDelegate(context, d),
              ),
            );
          },
        ),
      );

  void _openDelegate(BuildContext context, DelegateModel d) {
    if (d.canOpenShiftDetail) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: context.read<AdminBloc>(),
            child: SettleDelegatePage(delegate: d),
          ),
        ),
      );
      return;
    }
    final message = d.trackingStatus == DelegateTrackingStatus.pendingPickup
        ? 'التحميلة بانتظار استلام المندوب من التطبيق بعد.'
        : 'لا توجد وردية نشطة لهذا المندوب حالياً.';
    AppSnackbar.showInfo(context, message);
  }

  _StatusBadge _statusBadge(DelegateTrackingStatus status) {
    switch (status) {
      case DelegateTrackingStatus.idle:
        return const _StatusBadge('غير نشط', Colors.grey);
      case DelegateTrackingStatus.pendingPickup:
        return const _StatusBadge('بانتظار الاستلام', AppTheme.accent);
      case DelegateTrackingStatus.accepted:
        return const _StatusBadge('تم الاستلام', AppTheme.secondary);
      case DelegateTrackingStatus.inTransit:
        return const _StatusBadge('في الطريق', AppTheme.secondary);
      case DelegateTrackingStatus.completed:
        return const _StatusBadge('أنهى الجولة', AppTheme.primary);
      case DelegateTrackingStatus.awaitingSettlementConfirmation:
        return const _StatusBadge('بانتظار تأكيد التسليم', AppTheme.danger);
    }
  }
}

class _StatusBadge {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);
}
