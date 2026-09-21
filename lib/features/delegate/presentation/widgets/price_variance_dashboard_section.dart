import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/price_variance_models.dart';
import '../pages/price_variance_loading_detail_page.dart';

/// "مندوب حر السعر" self-service dashboard — REPLACES DashboardSection
/// entirely for a delegate whose linked SalesRep has
/// is_free_pricing_delegate=true (see dashboard_section.dart's own branch).
/// Shows the prominent accrued balance ("المستحق لك") and a tappable
/// drill-down by تحميلة (loading/shipment); each loading expands (via
/// PriceVarianceLoadingDetailPage) into every sale within it.
class PriceVarianceDashboardSection extends StatefulWidget {
  const PriceVarianceDashboardSection({super.key});

  @override
  State<PriceVarianceDashboardSection> createState() => _PriceVarianceDashboardSectionState();
}

class _PriceVarianceDashboardSectionState extends State<PriceVarianceDashboardSection> {
  PriceVarianceSummaryModel? _summary;
  String? _errorMessage;
  bool _retrying = false;
  final _tracker = RequestTracker<bool>();

  void _dispatchFetch() {
    final event = DelegatePriceVarianceSummaryFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void initState() {
    super.initState();
    _dispatchFetch();
  }

  void _refresh() {
    setState(() => _retrying = true);
    _dispatchFetch();
  }

  void _openLoading(PriceVarianceLoadingModel loading) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PriceVarianceLoadingDetailPage(loading: loading)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (_, state) {
        if (state is DelegatePriceVarianceSummaryLoaded) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() {
            _summary = state.summary;
            _errorMessage = null;
            _retrying = false;
          });
        } else if (state is DelegateFailure) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() {
            _retrying = false;
            if (_summary == null) _errorMessage = state.message;
          });
        }
      },
      child: Builder(builder: (context) {
        final summary = _summary;

        if (summary == null && _errorMessage == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (summary == null && _errorMessage != null) {
          return AppErrorView(
            title: 'تعذر عرض المستحق لك',
            message: _errorMessage!,
            danger: false,
            isRetrying: _retrying,
            onRetry: _refresh,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('فروقات الأسعار', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: _refresh,
                  tooltip: 'تحديث',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              elevation: AppTheme.elevationMed,
              color: AppTheme.primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.savings_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text('المستحق لك', style: TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${summary!.priceVarianceBalance.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 30, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('التحميلات', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (summary.byLoading.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('لا توجد مبيعات مسجلة بعد.', style: TextStyle(color: AppTheme.textMuted)),
                ),
              )
            else
              ...summary.byLoading.map((loading) => _LoadingCard(
                    loading: loading,
                    onTap: () => _openLoading(loading),
                  )),
          ],
        );
      }),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final PriceVarianceLoadingModel loading;
  final VoidCallback onTap;
  const _LoadingCard({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final positive = loading.loadingVarianceTotal >= 0;
    final color = positive ? AppTheme.secondary : AppTheme.danger;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loading.date ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${loading.lines.length} صنف مباع', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Text(
                '${positive ? '+' : ''}${loading.loadingVarianceTotal.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
