import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
import '../../../delegate/data/models/breakdown_models.dart';

/// العمالة — الأهداف الشهرية والرواتب الشهرية لكل مندوبي المبيعات، تعادل
/// تبويبي الويب "الأهداف الشهرية"/"الرواتب الشهرية". المصدر:
/// GET /v1/mobile/admin/payroll-summary (AdminDelegateController::
/// payrollSummary()) — نفس حسابات SalesRepPayrollService التي تُبنى عليها
/// لوحة المندوب لنفسه، لكل المناديب دفعة واحدة. تستدعي
/// AdminRemoteDataSource مباشرة، بنفس أسلوب باقي صفحات الإدارة الجديدة.
class AdminPayrollPage extends StatefulWidget {
  const AdminPayrollPage({super.key});

  @override
  State<AdminPayrollPage> createState() => _AdminPayrollPageState();
}

class _AdminPayrollPageState extends State<AdminPayrollPage> {
  final _remote = sl<AdminRemoteDataSource>();
  List<PayrollSummaryRowModel> _rows = [];
  bool _loading = true;
  String? _error;

  String get _currentMonth => DateFormat('yyyy-MM').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _remote.fetchPayrollSummary(month: _currentMonth);
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'فشل تحميل بيانات العمالة.';
      });
    }
  }

  Future<void> _openRep(PayrollSummaryRowModel rep) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _RepPayrollDetailPage(remote: _remote, rep: rep, month: _currentMonth),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العمالة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const Center(
                      child: Text('لا يوجد مناديب نشطون.', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _RepCard(rep: _rows[i], onTap: () => _openRep(_rows[i])),
                      ),
                    ),
    );
  }
}

class _RepCard extends StatelessWidget {
  final PayrollSummaryRowModel rep;
  final VoidCallback onTap;
  const _RepCard({required this.rep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = rep.targetPercentage;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(rep.repName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  Text(rep.netPayable.toStringAsFixed(0),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct == null ? 0 : (pct / 100).clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade200,
                  color: (pct ?? 0) >= 100 ? AppTheme.secondary : AppTheme.accent,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الهدف: ${rep.monthlyTarget.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('المحقق: ${rep.achievedThisMonth.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MiniStat(label: 'العمولة', value: rep.commissionEarned, color: AppTheme.secondary),
                  _MiniStat(label: 'الجزاءات', value: rep.penaltiesTotal, color: AppTheme.danger),
                  _MiniStat(label: 'السلف', value: rep.advancesTotal, color: AppTheme.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value.toStringAsFixed(0),
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      );
}

// ─── Rep detail: breakdowns + target editing ─────────────────────────────────

class _RepPayrollDetailPage extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final PayrollSummaryRowModel rep;
  final String month;
  const _RepPayrollDetailPage({required this.remote, required this.rep, required this.month});

  @override
  State<_RepPayrollDetailPage> createState() => _RepPayrollDetailPageState();
}

class _RepPayrollDetailPageState extends State<_RepPayrollDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  bool _targetChanged = false;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openEditTarget() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditTargetSheet(
        remote: widget.remote,
        rep: widget.rep,
        month: widget.month,
      ),
    );
    if (saved == true) {
      _targetChanged = true;
      if (mounted) AppSnackbar.showSuccess(context, 'تم حفظ الهدف بنجاح.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _targetChanged);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.rep.repName),
          actions: [
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'تعديل الهدف',
              onPressed: _openEditTarget,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'العمولة اليومية'),
              Tab(text: 'الجزاءات'),
              Tab(text: 'السلف'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _CommissionBreakdownTab(remote: widget.remote, repId: widget.rep.repId),
            _RepPenaltiesTab(remote: widget.remote, repId: widget.rep.repId),
            _RepAdvancesTab(remote: widget.remote, repId: widget.rep.repId),
          ],
        ),
      ),
    );
  }
}

class _CommissionBreakdownTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  const _CommissionBreakdownTab({required this.remote, required this.repId});

  @override
  State<_CommissionBreakdownTab> createState() => _CommissionBreakdownTabState();
}

class _CommissionBreakdownTabState extends State<_CommissionBreakdownTab> {
  List<CommissionDayModel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.remote.fetchRepCommissionBreakdown(widget.repId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل تحميل بيانات العمولة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (_rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد مبيعات هذا الشهر.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows!.length,
      itemBuilder: (_, i) {
        final r = _rows![i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.calendar_today_outlined, color: AppTheme.primary),
            title: Text(r.date),
            subtitle: Text('مبيعات: ${r.totalSales.toStringAsFixed(2)}'),
            trailing: Text('+${r.commissionEarned.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary)),
          ),
        );
      },
    );
  }
}

class _RepPenaltiesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  const _RepPenaltiesTab({required this.remote, required this.repId});

  @override
  State<_RepPenaltiesTab> createState() => _RepPenaltiesTabState();
}

class _RepPenaltiesTabState extends State<_RepPenaltiesTab> {
  List<PenaltyModel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.remote.fetchRepPenalties(widget.repId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل تحميل الجزاءات.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (_rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد جزاءات هذا الشهر.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows!.length,
      itemBuilder: (_, i) {
        final p = _rows![i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
            title: Text(p.reason),
            subtitle: Text(p.date),
            trailing: Text(p.amount.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
          ),
        );
      },
    );
  }
}

class _RepAdvancesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  const _RepAdvancesTab({required this.remote, required this.repId});

  @override
  State<_RepAdvancesTab> createState() => _RepAdvancesTabState();
}

class _RepAdvancesTabState extends State<_RepAdvancesTab> {
  List<AdvanceModel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.remote.fetchRepAdvances(widget.repId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل تحميل السلف.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (_rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد سلف هذا الشهر.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows!.length,
      itemBuilder: (_, i) {
        final a = _rows![i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.request_quote_outlined, color: AppTheme.accent),
            title: Text(a.description?.isNotEmpty == true ? a.description! : a.type),
            subtitle: Text('${a.date} — ${a.type}'),
            trailing: Text(a.amount.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
          ),
        );
      },
    );
  }
}

// ─── Edit target sheet ────────────────────────────────────────────────────────

class _EditTargetSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final PayrollSummaryRowModel rep;
  final String month;
  const _EditTargetSheet({required this.remote, required this.rep, required this.month});

  @override
  State<_EditTargetSheet> createState() => _EditTargetSheetState();
}

class _EditTargetSheetState extends State<_EditTargetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountCtrl =
      TextEditingController(text: widget.rep.monthlyTarget.toStringAsFixed(0));
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.remote.setRepTarget(
        repId: widget.rep.repId,
        month: widget.month,
        targetAmount: double.parse(_amountCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل حفظ الهدف.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تعديل هدف — ${widget.rep.repName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('الشهر: ${widget.month}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الهدف الشهري'),
                validator: (v) {
                  final amount = double.tryParse(v ?? '');
                  if (amount == null || amount < 0) return 'قيمة غير صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('حفظ الهدف'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
