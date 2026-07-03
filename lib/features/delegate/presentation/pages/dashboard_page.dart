import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/dashboard_model.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardModel? _dashboard;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateDashboardRequested());
  }

  void _refresh() {
    setState(() => _errorMessage = null);
    context.read<DelegateBloc>().add(DelegateDashboardRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأداء'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (_, state) {
          if (state is DelegateDashboardLoaded) {
            setState(() {
              _dashboard = state.dashboard;
              _errorMessage = null;
            });
          }
          if (state is DelegateFailure) {
            setState(() => _errorMessage = state.message);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _dashboard == null && _errorMessage == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_errorMessage != null && _dashboard == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 64, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ],
                ),
              ),
            );
          }

          final dashboard = _dashboard;
          if (dashboard == null) {
            return const SizedBox.shrink();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MonthHeader(month: dashboard.currentMonth),
                const SizedBox(height: 8),
                _TargetProgressCard(dashboard: dashboard),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.percent_rounded,
                        label: 'العمولة المكتسبة',
                        value: dashboard.commissionEarned,
                        color: AppTheme.secondary,
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.request_quote_outlined,
                        label: 'إجمالي السلف',
                        value: dashboard.advancesTotal,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _NetPayableCard(value: dashboard.netPayable),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String month;
  const _MonthHeader({required this.month});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          'ملخص شهر $month',
          style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
      );
}

class _TargetProgressCard extends StatelessWidget {
  final DashboardModel dashboard;
  const _TargetProgressCard({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final pct = dashboard.targetPercentage;
    final progress = pct == null ? 0.0 : (pct / 100).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.track_changes_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('نسبة تحقيق الهدف',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text(
                  pct != null ? '${pct.toStringAsFixed(1)}%' : 'لا يوجد هدف',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: progress >= 1 ? AppTheme.secondary : AppTheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المحقق: ${dashboard.achievedThisMonth.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('الهدف: ${dashboard.monthlyTarget.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      );
}

class _NetPayableCard extends StatelessWidget {
  final double value;
  const _NetPayableCard({required this.value});

  @override
  Widget build(BuildContext context) => Card(
        color: AppTheme.primary,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الصافي المستحق',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
}
