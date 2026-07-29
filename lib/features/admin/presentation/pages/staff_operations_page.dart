import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "عمليات العمالة" — admin quick-action to record a جزاء/سلفة/مكافأة
/// against any staff member (sales rep or production worker, per the
/// general "العمالة" web page's staff list which legitimately covers both
/// — unlike AdminPayrollPage's rep-only list). Submits to
/// POST /v1/mobile/admin/staff-operations (AdminStaffOperationController),
/// which routes to the right StaffOperationService::create*() method
/// server-side based on operation_type.
class StaffOperationsPage extends StatefulWidget {
  const StaffOperationsPage({super.key});

  @override
  State<StaffOperationsPage> createState() => _StaffOperationsPageState();
}

class _StaffOperationsPageState extends State<StaffOperationsPage> {
  final _remote = sl<AdminRemoteDataSource>();

  bool _loadingStaff = true;
  String? _error;
  List<StaffModel> _allStaff = [];
  StaffModel? _selectedStaff;
  final _searchCtrl = TextEditingController();

  String _operationType = 'penalty';
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loadingStaff = true;
      _error = null;
    });
    try {
      final staff = await _remote.fetchAllStaff();
      if (!mounted) return;
      setState(() {
        _allStaff = staff;
        _loadingStaff = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingStaff = false;
        _error = 'فشل تحميل قائمة العمالة.';
      });
    }
  }

  List<StaffModel> get _filteredStaff {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return _allStaff;
    return _allStaff
        .where((s) =>
            s.name.contains(query) || (s.phone?.contains(query) ?? false))
        .toList();
  }

  Future<void> _submit() async {
    final staff = _selectedStaff;
    if (staff == null) {
      AppSnackbar.showError(context, 'يرجى اختيار موظف.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _remote.submitStaffOperation(
        salesRepId: staff.id,
        operationType: _operationType,
        amount: amount,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(
          context, 'تم تسجيل العملية بنجاح — ${staff.name}.');
      setState(() {
        _submitting = false;
        _selectedStaff = null;
        _searchCtrl.clear();
        _operationType = 'penalty';
        _amountCtrl.clear();
        _notesCtrl.clear();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(context,
          e.response?.data?['message'] as String? ?? 'فشل تسجيل العملية.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عمليات العمالة')),
      body: _loadingStaff
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _loadStaff)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_selectedStaff == null) ...[
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ابحث عن موظف بالاسم أو الهاتف',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      if (_filteredStaff.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                              child: Text('لا يوجد موظفون مطابقون.',
                                  style: TextStyle(color: AppTheme.textMuted))),
                        )
                      else
                        ..._filteredStaff.map((s) => Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: s.workerType == 'worker'
                                      ? Colors.amber.withValues(alpha: 0.2)
                                      : AppTheme.primary.withValues(alpha: 0.1),
                                  child: Icon(
                                    s.workerType == 'worker'
                                        ? Icons.engineering_outlined
                                        : Icons.badge_outlined,
                                    color: s.workerType == 'worker'
                                        ? Colors.amber.shade800
                                        : AppTheme.primary,
                                  ),
                                ),
                                title: Text(s.name),
                                subtitle: Text(s.workerType == 'worker'
                                    ? 'عامل إنتاج'
                                    : 'مندوب مبيعات'),
                                onTap: () => setState(() => _selectedStaff = s),
                              ),
                            )),
                    ] else ...[
                      Card(
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        child: ListTile(
                          leading: const Icon(Icons.person_outline,
                              color: AppTheme.primary),
                          title: Text(_selectedStaff!.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(_selectedStaff!.workerType == 'worker'
                              ? 'عامل إنتاج'
                              : 'مندوب مبيعات'),
                          trailing: TextButton(
                            onPressed: () =>
                                setState(() => _selectedStaff = null),
                            child: const Text('تغيير'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('نوع العملية',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('جزاء'),
                              selected: _operationType == 'penalty',
                              selectedColor:
                                  AppTheme.danger.withValues(alpha: 0.2),
                              onSelected: (_) =>
                                  setState(() => _operationType = 'penalty'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('سلفة'),
                              selected: _operationType == 'advance',
                              selectedColor:
                                  AppTheme.accent.withValues(alpha: 0.3),
                              onSelected: (_) =>
                                  setState(() => _operationType = 'advance'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('مكافأة'),
                              selected: _operationType == 'bonus',
                              selectedColor:
                                  Colors.green.withValues(alpha: 0.2),
                              onSelected: (_) =>
                                  setState(() => _operationType = 'bonus'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'المبلغ', hintText: '0'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesCtrl,
                        decoration:
                            const InputDecoration(labelText: 'السبب / ملاحظات'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded),
                          label: Text(
                              _submitting ? 'جارٍ الحفظ...' : 'تسجيل العملية'),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
