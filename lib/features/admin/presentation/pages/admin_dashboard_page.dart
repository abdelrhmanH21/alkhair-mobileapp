import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
import '../../../delegate/presentation/bloc/delegate_bloc.dart';
import '../../../delegate/presentation/pages/delegate_reports_page.dart';
import '../widgets/operation_sheet.dart';
import 'settle_delegate_page.dart';
import 'create_loading_page.dart';
import 'admin_expenses_page.dart';
import 'admin_customers_suppliers_page.dart';
import 'admin_sales_collections_page.dart';
import 'admin_payroll_page.dart';
import 'start_production_page.dart';
import 'receive_production_page.dart';
import 'admin_sale_page.dart';
import 'admin_purchase_page.dart';
import 'admin_price_edit_page.dart';
import 'admin_supplier_payment_page.dart';
import 'admin_waste_page.dart';
import 'admin_inventory_count_page.dart';

/// Admin shell: bottom nav with exactly 5 destinations —
///   1. الرئيسية (center, emphasized — the working-capital dashboard, unchanged)
///   2. التصنيع (sub-menu: بدء تشغيلة جديدة / استلام إنتاج تام)
///   3. التوزيع (sub-menu: توزيعة جديدة / طلبات التسليم / التقارير / العمالة)
///   4. العمليات (sub-menu: بيع / شراء / تعديل سعر / تحصيل / سداد لمورد /
///      هالك / جرد / المبيعات والتحصيلات / المصروفات والخزائن)
///   5. العملاء والموردين
/// Sub-menus (2-4) all use the same showOperationSheet() bottom-sheet
/// pattern (see widgets/operation_sheet.dart) rather than three different
/// navigation styles. الرئيسية is the only destination with persistent
/// body content — the other four are one-shot navigation triggers, so
/// there's no IndexedStack/selected-index bookkeeping for them.
///
/// The old side drawer is gone; every entry that lived there now maps to:
///   المبيعات والتحصيلات      → العمليات sub-menu
///   العمالة                  → التوزيع sub-menu
///   المصروفات والخزائن        → العمليات sub-menu
///   التقارير                  → التوزيع sub-menu
///   بيانات العملاء والموردين  → العملاء والموردين (bottom-nav destination 5)
///   بدء تشغيلة جديدة / استلام إنتاج تام → التصنيع sub-menu
///   العمليات (old drawer item) → العمليات bottom-nav destination itself
///   إشعارات المبيعات (toggle) → AppBar icon
///   تسجيل الخروج              → AppBar icon
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _salesNotificationsEnabled = true;
  bool _updatingPreference = false;

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(AdminDashboardFetched());
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _salesNotificationsEnabled = authState.user.salesNotificationsEnabled;
    }
  }

  Future<void> _toggleNotifications() async {
    final next = !_salesNotificationsEnabled;
    setState(() {
      _salesNotificationsEnabled = next;
      _updatingPreference = true;
    });
    try {
      await sl<AdminRemoteDataSource>().updateNotificationPreference(next);
      if (mounted) {
        AppSnackbar.showSuccess(
            context, next ? 'تم تفعيل إشعارات المبيعات' : 'تم إيقاف إشعارات المبيعات');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _salesNotificationsEnabled = !next);
      AppSnackbar.showError(context, 'فشل تحديث تفضيلات الإشعارات.');
    } finally {
      if (mounted) setState(() => _updatingPreference = false);
    }
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

  // ── Sub-menus ────────────────────────────────────────────────────────

  void _openManufacturingMenu() {
    showOperationSheet(
      context,
      title: 'التصنيع',
      items: [
        OperationSheetItem(
          icon: Icons.science_outlined,
          color: AppTheme.primary,
          title: 'بدء تشغيلة جديدة',
          subtitle: 'صرف خامات وفتح أمر تشغيل',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const StartProductionPage())),
        ),
        OperationSheetItem(
          icon: Icons.inventory_2_outlined,
          color: AppTheme.secondary,
          title: 'استلام إنتاج تام',
          subtitle: 'تسجيل المنتجات الناتجة من تشغيلة جارية',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ReceiveProductionPage())),
        ),
      ],
    );
  }

  void _openDistributionMenu() {
    showOperationSheet(
      context,
      title: 'التوزيع',
      items: [
        OperationSheetItem(
          icon: Icons.add_road_rounded,
          color: AppTheme.primary,
          title: 'توزيعة جديدة',
          subtitle: 'تحميل شاحنة مندوب بمنتجات من مخزن',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<AdminBloc>(),
                child: const CreateLoadingPage(),
              ),
            ),
          ),
        ),
        OperationSheetItem(
          icon: Icons.people_outline,
          color: AppTheme.secondary,
          title: 'طلبات التسليم',
          subtitle: 'متابعة حالة المناديب وتسوية الورديات',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<AdminBloc>(),
                child: const _DelegatesTrackingPage(),
              ),
            ),
          ),
        ),
        OperationSheetItem(
          icon: Icons.bar_chart_rounded,
          color: AppTheme.accent,
          title: 'التقارير',
          subtitle: 'تقارير المبيعات حسب المنطقة والمنتج',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              // DelegateReportsPage's by-region/by-product endpoints return
              // company-wide totals for admin/manager callers — see
              // DelegateReportController::byRegion(). DelegateBloc is
              // already provided at the app root (see app.dart).
              builder: (_) => BlocProvider.value(
                value: context.read<DelegateBloc>(),
                child: const DelegateReportsPage(),
              ),
            ),
          ),
        ),
        OperationSheetItem(
          icon: Icons.badge_outlined,
          color: Colors.teal,
          title: 'العمالة',
          subtitle: 'رواتب وعمولات وأهداف المناديب',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminPayrollPage())),
        ),
      ],
    );
  }

  void _openOperationsMenu() {
    showOperationSheet(
      context,
      title: 'العمليات',
      items: [
        OperationSheetItem(
          icon: Icons.point_of_sale_outlined,
          color: AppTheme.primary,
          title: 'تسجيل عملية بيع',
          subtitle: 'بيع مباشر لعميل — لا يُنسب لأي مندوب',
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSalePage())),
        ),
        OperationSheetItem(
          icon: Icons.shopping_cart_outlined,
          color: AppTheme.secondary,
          title: 'عملية شراء',
          subtitle: 'فاتورة شراء من مورد — خامات أو منتجات',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminPurchasePage())),
        ),
        OperationSheetItem(
          icon: Icons.price_change_outlined,
          color: AppTheme.accent,
          title: 'عملية تعديل سعر',
          subtitle: 'تعديل سعر جملة منتج أو تكلفة مادة خام',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminPriceEditPage())),
        ),
        OperationSheetItem(
          icon: Icons.payments_outlined,
          color: Colors.teal,
          title: 'عملية تحصيل',
          subtitle: 'تحصيل دفعة من مديونية عميل',
          onTap: () => openAdminCollectionSheet(context, sl<AdminRemoteDataSource>()),
        ),
        OperationSheetItem(
          icon: Icons.request_quote_outlined,
          color: AppTheme.danger,
          title: 'عملية سداد لمورد',
          subtitle: 'سداد دفعة من مديونية مورد',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminSupplierPaymentPage())),
        ),
        OperationSheetItem(
          icon: Icons.delete_outline,
          color: AppTheme.danger,
          title: 'تسجيل هالك',
          subtitle: 'خصم كمية تالفة من المخزون',
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminWastePage())),
        ),
        OperationSheetItem(
          icon: Icons.fact_check_outlined,
          color: AppTheme.primary,
          title: 'عملية جرد',
          subtitle: 'جرد مخزن ومطابقة الأرصدة الفعلية',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminInventoryCountPage())),
        ),
        OperationSheetItem(
          icon: Icons.receipt_long_outlined,
          color: AppTheme.secondary,
          title: 'المبيعات والتحصيلات',
          subtitle: 'سجل فواتير المبيعات والتحصيلات من العملاء',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminSalesCollectionsPage())),
        ),
        OperationSheetItem(
          icon: Icons.account_balance_wallet_outlined,
          color: AppTheme.accent,
          title: 'المصروفات والخزائن',
          subtitle: 'تسجيل ومتابعة مصروفات الشركة',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminExpensesPage())),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userName = authState is AuthAuthenticated ? authState.user.name : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم الإدارة'),
        actions: [
          IconButton(
            icon: Icon(_salesNotificationsEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined),
            tooltip: 'إشعارات المبيعات',
            onPressed: _updatingPreference ? null : _toggleNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _DashboardTab(userName: userName),
      floatingActionButton: FloatingActionButton(
        tooltip: 'الرئيسية',
        onPressed: () => context.read<AdminBloc>().add(AdminDashboardFetched()),
        child: const Icon(Icons.home_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          // Each destination is wrapped in Expanded so the two items left of
          // the notch and the two right of it each claim an equal half of
          // the remaining width — with mainAxisAlignment.spaceAround (the
          // previous approach), the fixed-width notch spacer was treated as
          // just another flex child among four unequally-sized items, so
          // the gap never landed under the FAB and "العمليات" (immediately
          // after the spacer) rendered visibly off-center.
          children: [
            Expanded(
              child: _BottomNavAction(
                icon: Icons.science_outlined,
                label: 'التصنيع',
                onTap: _openManufacturingMenu,
              ),
            ),
            Expanded(
              child: _BottomNavAction(
                icon: Icons.local_shipping_outlined,
                label: 'التوزيع',
                onTap: _openDistributionMenu,
              ),
            ),
            const SizedBox(width: 48), // space for the docked FAB notch
            Expanded(
              child: _BottomNavAction(
                icon: Icons.touch_app_outlined,
                label: 'العمليات',
                onTap: _openOperationsMenu,
              ),
            ),
            Expanded(
              child: _BottomNavAction(
                icon: Icons.groups_outlined,
                label: 'العملاء والموردين',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminCustomersSuppliersPage())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BottomNavAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.grey.shade600, size: 24),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

/// "طلبات التسليم" — thin Scaffold wrapper around the existing _DelegatesTab
/// (unmodified) so it can be pushed as a standalone page from the التوزيع
/// sub-menu instead of living as a persistent bottom-nav tab.
class _DelegatesTrackingPage extends StatefulWidget {
  const _DelegatesTrackingPage();

  @override
  State<_DelegatesTrackingPage> createState() => _DelegatesTrackingPageState();
}

class _DelegatesTrackingPageState extends State<_DelegatesTrackingPage> {
  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(AdminDelegatesFetched());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلبات التسليم')),
        body: const _DelegatesTab(),
      );
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
                  style: TextStyle(color: AppTheme.textMuted)),
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
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
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
          if (breakdown.payables > 0 || breakdown.payrollPaidToDate > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
          ],
          if (breakdown.payrollPaidToDate > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.remove_circle_outline,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  const Text('رواتب مصروفة هذا الشهر — تُخصم من الإجمالي',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const Spacer(),
                  Text(
                    '- ${breakdown.payrollPaidToDate.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (breakdown.payables > 0)
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
                style: TextStyle(color: AppTheme.textMuted)),
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
        return const _StatusBadge('غير نشط', AppTheme.textMuted);
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
