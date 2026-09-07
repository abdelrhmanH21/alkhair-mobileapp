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
                      child: Text('لا يوجد مناديب نشطون.', style: TextStyle(color: AppTheme.textMuted)))
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
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  Text('المحقق: ${rep.achievedThisMonth.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  Text(pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MiniStat(
                    label: 'العمولة',
                    value: rep.commissionEarned,
                    color: AppTheme.secondary,
                    overridden: rep.isCommissionOverridden,
                  ),
                  _MiniStat(label: 'الجزاءات', value: rep.penaltiesTotal, color: AppTheme.danger),
                  _MiniStat(label: 'السلف', value: rep.advancesTotal, color: AppTheme.accent),
                  _MiniStat(label: 'المكافآت', value: rep.bonusTotal, color: Colors.green),
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
  // Shows a small "معدّل يدويًا" indicator dot next to the value — currently
  // only used for the commission stat (Part 2's manual override).
  final bool overridden;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.overridden = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.toStringAsFixed(0),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
              if (overridden) ...[
                const SizedBox(width: 3),
                const Icon(Icons.edit, size: 10, color: Colors.amber),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
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
  late final TabController _tabController = TabController(length: 4, vsync: this);
  bool _targetChanged = false;
  bool _deleting = false;

  // Local copy of the commission figures, seeded from the static snapshot
  // `widget.rep` (the list row at the time this page was opened) and kept
  // fresh here after a manual override is set/reverted — see
  // _refreshCommission() below.
  late double _commissionEarned = widget.rep.commissionEarned;
  late double _computedCommissionEarned = widget.rep.computedCommissionEarned;
  late bool _isCommissionOverridden = widget.rep.isCommissionOverridden;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Re-fetches this rep's row from the payroll summary list (the only
  // endpoint that exposes commission_earned/is_commission_overridden for a
  // given month) after a commission-override change, so the header below
  // reflects the new value without leaving this page.
  Future<void> _refreshCommission() async {
    try {
      final rows = await widget.remote.fetchPayrollSummary(month: widget.month);
      final updated = rows.where((r) => r.repId == widget.rep.repId).firstOrNull;
      if (updated == null || !mounted) return;
      setState(() {
        _commissionEarned = updated.commissionEarned;
        _computedCommissionEarned = updated.computedCommissionEarned;
        _isCommissionOverridden = updated.isCommissionOverridden;
      });
    } catch (_) {
      // Non-fatal — the header just keeps showing the pre-refresh value.
    }
  }

  Future<void> _openEditCommission() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditCommissionOverrideSheet(
        remote: widget.remote,
        repId: widget.rep.repId,
        repName: widget.rep.repName,
        month: widget.month,
        currentAmount: _commissionEarned,
        isOverridden: _isCommissionOverridden,
      ),
    );
    if (saved == true) {
      _targetChanged = true; // reused as the generic "refresh the list on pop" flag
      await _refreshCommission();
      if (mounted) AppSnackbar.showSuccess(context, 'تم تحديث العمولة.');
    }
  }

  // "حذف نهائي" — hard-deletes this rep and cascades every referencing
  // table (مبيعات، رواتب، سلف، جزاءات، مكافآت، أهداف...). Only allowed for
  // a rep with no linked User account — mirrors SalesRepsPage.tsx's web
  // behavior and is re-enforced server-side by
  // SalesRepController::forceDestroy().
  Future<void> _forceDelete() async {
    if (widget.rep.hasLinkedUser) {
      AppSnackbar.showError(
        context,
        'هذا المندوب مرتبط بحساب مستخدم — احذف أو عدّل الحساب من إدارة النظام أولاً.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نهائي'),
        content: Text(
          'سيتم حذف "${widget.rep.repName}" وكل بياناته المرتبطة '
          '(المبيعات، الرواتب، الجزاءات...) نهائيًا. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await widget.remote.forceDeleteRep(widget.rep.repId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل الحذف النهائي.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
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
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever_outlined),
              tooltip: 'حذف نهائي',
              onPressed: _deleting ? null : _forceDelete,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'العمولة اليومية'),
              Tab(text: 'الجزاءات'),
              Tab(text: 'السلف'),
              Tab(text: 'المكافآت'),
            ],
          ),
        ),
        body: Column(
          children: [
            // العمولة المكتسبة — computed by default, or the manually-set
            // override for widget.month if one is active (Part 2).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: _isCommissionOverridden ? Colors.amber.withValues(alpha: 0.08) : null,
              child: Row(
                children: [
                  const Text('العمولة المكتسبة', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  const SizedBox(width: 6),
                  if (_isCommissionOverridden)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('معدّل يدويًا',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown)),
                    ),
                  const Spacer(),
                  if (_isCommissionOverridden)
                    Text('(المحسوب: ${_computedCommissionEarned.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(width: 8),
                  Text(_commissionEarned.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary, fontSize: 15)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'تعديل العمولة يدويًا',
                    onPressed: _openEditCommission,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CommissionBreakdownTab(remote: widget.remote, repId: widget.rep.repId),
                  _RepPenaltiesTab(remote: widget.remote, repId: widget.rep.repId),
                  _RepAdvancesTab(remote: widget.remote, repId: widget.rep.repId),
                  _RepBonusesTab(
                    remote: widget.remote,
                    repId: widget.rep.repId,
                    onChanged: () => _targetChanged = true,
                  ),
                ],
              ),
            ),
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
          child: Text('لا توجد مبيعات هذا الشهر.', style: TextStyle(color: AppTheme.textMuted)));
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
          child: Text('لا توجد جزاءات هذا الشهر.', style: TextStyle(color: AppTheme.textMuted)));
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
          child: Text('لا توجد سلف هذا الشهر.', style: TextStyle(color: AppTheme.textMuted)));
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

class _RepBonusesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  // Notifies the parent detail page that data changed, so it marks the
  // rep list (one level up) for refresh on pop — same convention as
  // _openEditCommission's use of _targetChanged.
  final VoidCallback? onChanged;
  const _RepBonusesTab({required this.remote, required this.repId, this.onChanged});

  @override
  State<_RepBonusesTab> createState() => _RepBonusesTabState();
}

class _RepBonusesTabState extends State<_RepBonusesTab> {
  List<BonusModel>? _rows;
  String? _error;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.remote.fetchRepBonuses(widget.repId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل تحميل المكافآت.');
    }
  }

  // "حذف" — mirrors _forceDelete's AlertDialog confirm pattern (the only
  // delete-confirm convention already in this app; the web's ConfirmDialog
  // equivalent doesn't exist on mobile for penalties/advances either).
  Future<void> _delete(BonusModel bonus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المكافأة'),
        content: const Text('هل تريد حذف هذه المكافأة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingId = bonus.id);
    try {
      await widget.remote.deleteBonus(bonus.id);
      if (!mounted) return;
      setState(() {
        _rows = _rows?.where((b) => b.id != bonus.id).toList();
        _deletingId = null;
      });
      widget.onChanged?.call();
      AppSnackbar.showSuccess(context, 'تم حذف المكافأة.');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل الحذف.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (_rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد مكافآت هذا الشهر.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows!.length,
      itemBuilder: (_, i) {
        final b = _rows![i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: Text(b.reason?.isNotEmpty == true ? b.reason! : 'مكافأة'),
            subtitle: Text(b.isApplied ? '${b.date} · طُبِّقت في كشف الرواتب' : b.date),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b.amount.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                if (!b.isApplied) ...[
                  const SizedBox(width: 4),
                  _deletingId == b.id
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                          tooltip: 'حذف',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => _delete(b),
                        ),
                ],
              ],
            ),
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
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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

// ─── Edit commission-override sheet (Part 2) ─────────────────────────────────

class _EditCommissionOverrideSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  final String repName;
  final String month;
  final double currentAmount;
  final bool isOverridden;
  const _EditCommissionOverrideSheet({
    required this.remote,
    required this.repId,
    required this.repName,
    required this.month,
    required this.currentAmount,
    required this.isOverridden,
  });

  @override
  State<_EditCommissionOverrideSheet> createState() => _EditCommissionOverrideSheetState();
}

class _EditCommissionOverrideSheetState extends State<_EditCommissionOverrideSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountCtrl = TextEditingController(text: widget.currentAmount.toStringAsFixed(2));
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  bool _reverting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.remote.setCommissionOverride(
        repId: widget.repId,
        month: widget.month,
        amount: double.parse(_amountCtrl.text.trim()),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل حفظ العمولة.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  Future<void> _revert() async {
    setState(() => _reverting = true);
    try {
      await widget.remote.deleteCommissionOverride(repId: widget.repId, month: widget.month);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _reverting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل الإلغاء.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _reverting = false);
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
              Text('تعديل العمولة يدويًا — ${widget.repName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('الشهر: ${widget.month} — لن يؤثر هذا التعديل على أي شهر آخر.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'العمولة المكتسبة (ج.م)'),
                validator: (v) {
                  final amount = double.tryParse(v ?? '');
                  if (amount == null || amount < 0) return 'قيمة غير صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'سبب / ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting || _reverting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('حفظ التعديل'),
                ),
              ),
              if (widget.isOverridden) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _submitting || _reverting ? null : _revert,
                    child: _reverting
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('الرجوع للقيمة المحسوبة تلقائيًا'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
