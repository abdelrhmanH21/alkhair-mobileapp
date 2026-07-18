import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/progress_ring.dart';
import '../../../../core/widgets/state_views.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/dashboard_model.dart';
import '../pages/penalties_page.dart';
import '../pages/advances_page.dart';
import '../pages/commission_breakdown_page.dart';

/// Reusable delegate-performance dashboard. Self-contained: dispatches its own
/// fetch and owns its own loading/error/data lifecycle, so it can be dropped
/// into any page (standalone `DashboardPage` or the `DelegateHomePage` home
/// tab) without duplicating the data-fetching logic.
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key});

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  DashboardModel? _dashboard;
  String? _errorMessage;
  bool _retrying = false;
  // Replaces the old _settled bool: tracks the requestId of THIS widget's
  // own outstanding dashboard fetch, so a DelegateLoadingLoaded/DelegateFailure
  // dispatched later by a sibling widget on the same shared DelegateBloc
  // (e.g. the shipment-status fetch on the home tab) can never be mistaken
  // for our own fetch's result — see request_tracker.dart.
  final _tracker = RequestTracker<bool>();

  void _dispatchFetch() {
    final event = DelegateDashboardRequested();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void initState() {
    super.initState();
    _dispatchFetch();
  }

  void _refresh() {
    setState(() {
      // Deliberately keep the previous _errorMessage in place (rather than
      // clearing it) so a retry that fails again doesn't blank the error
      // view back to the loading skeleton and flicker it right back —
      // the retry button shows its own inline spinner instead.
      _retrying = true;
    });
    _dispatchFetch();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (_, state) {
        if (state is DelegateDashboardLoaded) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() {
            _dashboard = state.dashboard;
            _errorMessage = null;
            _retrying = false;
          });
        } else if (state is DelegateFailure) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() {
            _errorMessage = state.message;
            _retrying = false;
          });
        }
      },
      child: Builder(builder: (context) {
        final dashboard = _dashboard;

        if (dashboard == null && _errorMessage == null) {
          return const _DashboardSkeleton();
        }

        if (dashboard == null && _errorMessage != null) {
          // Calm, non-alarming presentation: this is commonly just "your
          // account isn't linked to an employee record yet", not a crash.
          return AppErrorView(
            title: 'تعذر عرض لوحة الأداء',
            message: _errorMessage!,
            danger: false,
            isRetrying: _retrying,
            onRetry: _refresh,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthHeader(month: dashboard!.currentMonth, onRefresh: _refresh),
            const SizedBox(height: 12),
            _HeroTargetCard(dashboard: dashboard),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.percent_rounded,
                    label: 'العمولة المكتسبة',
                    value: dashboard.commissionEarned,
                    color: AppTheme.secondary,
                    onTap: () => _openPage(context, const CommissionBreakdownPage()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'الراتب الأساسي',
                    value: dashboard.baseSalary,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.remove_circle_outline,
                    label: 'إجمالي الجزاءات',
                    value: dashboard.penaltiesTotal,
                    color: AppTheme.danger,
                    onTap: () => _openPage(context, const PenaltiesPage()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.request_quote_outlined,
                    label: 'إجمالي السلف',
                    value: dashboard.advancesTotal,
                    color: AppTheme.accent,
                    onTap: () => _openPage(context, const AdvancesPage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _NetPayableCard(value: dashboard.netPayable),
          ],
        );
      }),
    );
  }
}

void _openPage(BuildContext context, Widget page) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: page,
      ),
    ),
  );
}

// ─── Loading skeleton ────────────────────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSkeletonBox(height: 14, width: 140),
          SizedBox(height: 12),
          Center(
            child: AppSkeletonBox(
              height: 140,
              width: 140,
              borderRadius: 70,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: AppSkeletonBox(height: 84)),
              SizedBox(width: 8),
              Expanded(child: AppSkeletonBox(height: 84)),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: AppSkeletonBox(height: 84)),
              SizedBox(width: 8),
              Expanded(child: AppSkeletonBox(height: 84)),
            ],
          ),
          SizedBox(height: 8),
          AppSkeletonBox(height: 64),
        ],
      );
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final String month;
  final VoidCallback onRefresh;
  const _MonthHeader({required this.month, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Text('ملخص شهر $month', style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: onRefresh,
              tooltip: 'تحديث',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
}

// ─── Hero target-progress ring ───────────────────────────────────────────────

class _HeroTargetCard extends StatelessWidget {
  final DashboardModel dashboard;
  const _HeroTargetCard({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final pct = dashboard.targetPercentage;
    final progress = pct == null ? 0.0 : (pct / 100).clamp(0.0, 1.0);
    final ringColor = progress >= 1 ? AppTheme.secondary : AppTheme.primary;

    return Card(
      elevation: AppTheme.elevationMed,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.track_changes_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('نسبة تحقيق الهدف', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ProgressRing(
              progress: progress,
              color: ringColor,
              size: 140,
              strokeWidth: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pct != null ? '${pct.toStringAsFixed(0)}%' : '—',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: ringColor),
                  ),
                  Text(
                    pct != null ? 'من الهدف' : 'لا يوجد هدف',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(label: 'المحقق', value: dashboard.achievedThisMonth),
                Container(width: 1, height: 28, color: Colors.grey.shade200),
                _MiniStat(label: 'الهدف', value: dashboard.monthlyTarget),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value.toStringAsFixed(2),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.black87)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

// ─── Stat cards ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    if (onTap != null) ...[
                      const Spacer(),
                      Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400, size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  value.toStringAsFixed(2),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: color, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─── Net payable highlight ───────────────────────────────────────────────────

class _NetPayableCard extends StatelessWidget {
  final double value;
  const _NetPayableCard({required this.value});

  @override
  Widget build(BuildContext context) => Card(
        elevation: AppTheme.elevationMed,
        color: AppTheme.primary,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.savings_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('الصافي المستحق',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                    color: AppTheme.accent, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
}
