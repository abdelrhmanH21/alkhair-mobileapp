import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';
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
              label: 'المندوبون'),
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

class _AdminDrawer extends StatelessWidget {
  final String userName;
  const _AdminDrawer({required this.userName});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: BlocBuilder<AppConfigBloc, AppConfigState>(
        builder: (_, configState) {
          final logoUrl = configState is AppConfigLoaded
              ? configState.config.logoUrl
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
                      userName,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12),
                    ),
                  ],
                ),
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
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: d.hasActiveShift
                      ? AppTheme.secondary.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.person_rounded,
                    color: d.hasActiveShift
                        ? AppTheme.secondary
                        : Colors.grey,
                  ),
                ),
                title: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(d.email,
                    style: const TextStyle(fontSize: 12)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: d.hasActiveShift
                            ? AppTheme.secondary.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        d.hasActiveShift ? 'في الوردية' : 'غير نشط',
                        style: TextStyle(
                            fontSize: 10,
                            color: d.hasActiveShift
                                ? AppTheme.secondary
                                : Colors.grey),
                      ),
                    ),
                  ],
                ),
                onTap: d.hasActiveShift
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BlocProvider.value(
                              value: context.read<AdminBloc>(),
                              child: SettleDelegatePage(delegate: d),
                            ),
                          ),
                        )
                    : null,
              ),
            );
          },
        ),
      );
}
