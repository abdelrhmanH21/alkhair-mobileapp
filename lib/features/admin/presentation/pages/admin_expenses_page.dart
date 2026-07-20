import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// المصروفات والخزائن — يعرض بيانات ExpenseController/TreasuryController
/// كما هي (نفس المسارات التي تستخدمها واجهة الويب)، دون المرور عبر
/// AdminBloc المشترك مع لوحة التحكم وتبويب المندوبين: هذه الصفحة تُفتح فوق
/// تلك الشاشات وتستدعي AdminRemoteDataSource مباشرة بنفس أسلوب
/// CustomerInvoiceHistoryPage — لتفادي تسرّب حالات التحميل/الخطأ الخاصة بها
/// إلى تبويبات AdminDashboardPage الأخرى.
class AdminExpensesPage extends StatefulWidget {
  const AdminExpensesPage({super.key});

  @override
  State<AdminExpensesPage> createState() => _AdminExpensesPageState();
}

class _AdminExpensesPageState extends State<AdminExpensesPage>
    with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المصروفات والخزائن'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'المصروفات'),
            Tab(text: 'الخزائن'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ExpensesTab(remote: _remote),
          _TreasuriesTab(remote: _remote),
        ],
      ),
    );
  }
}

// ─── Expenses tab ────────────────────────────────────────────────────────────

class _ExpensesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _ExpensesTab({required this.remote});

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  DateTimeRange? _range;
  List<ExpenseModel> _expenses = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

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
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchExpenses(
        dateFrom: _range != null ? fmt.format(_range!.start) : null,
        dateTo: _range != null ? fmt.format(_range!.end) : null,
        page: 1,
      );
      setState(() {
        _expenses = page.data;
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = e.response?.data?['message'] as String? ?? 'فشل تحميل المصروفات.';
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'حدث خطأ غير متوقع.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchExpenses(
        dateFrom: _range != null ? fmt.format(_range!.start) : null,
        dateTo: _range != null ? fmt.format(_range!.end) : null,
        page: _currentPage + 1,
      );
      setState(() {
        _expenses.addAll(page.data);
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange:
          _range ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (range != null) {
      setState(() => _range = range);
      _load();
    }
  }

  Future<void> _openNewExpenseSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewExpenseSheet(remote: widget.remote),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewExpenseSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('مصروف جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      _range == null
                          ? 'كل الفترات'
                          : '${DateFormat('yyyy-MM-dd').format(_range!.start)} — ${DateFormat('yyyy-MM-dd').format(_range!.end)}',
                    ),
                  ),
                ),
                if (_range != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _range = null);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_expenses.isEmpty) {
      return const Center(
          child: Text('لا توجد مصروفات في هذه الفترة.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _expenses.length + 1,
        itemBuilder: (_, i) {
          if (i == _expenses.length) {
            if (!_hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: const Text('تحميل المزيد')),
              ),
            );
          }
          final e = _expenses[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.description,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text(e.amount.toStringAsFixed(2),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: AppTheme.danger, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Chip(text: e.categoryName ?? 'بدون تصنيف'),
                      const SizedBox(width: 6),
                      _Chip(text: e.treasuryName),
                      const SizedBox(width: 6),
                      _Chip(
                        text: e.isDelegateSourced ? 'مندوب' : 'عام',
                        color: e.isDelegateSourced ? AppTheme.accent : AppTheme.secondary,
                      ),
                      const Spacer(),
                      Text(DateFormat('yyyy-MM-dd').format(e.expenseDate),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color? color;
  const _Chip({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: c)),
    );
  }
}

// ─── New expense bottom sheet ────────────────────────────────────────────────

class _NewExpenseSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _NewExpenseSheet({required this.remote});

  @override
  State<_NewExpenseSheet> createState() => _NewExpenseSheetState();
}

class _NewExpenseSheetState extends State<_NewExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<TreasuryModel>? _treasuries;
  List<ExpenseCategoryModel>? _categories;
  TreasuryModel? _selectedTreasury;
  ExpenseCategoryModel? _selectedCategory;
  DateTime _date = DateTime.now();
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.remote.fetchTreasuries(),
        widget.remote.fetchExpenseCategories(),
      ]);
      final treasuries = results[0] as List<TreasuryModel>;
      final defaultTreasuries = treasuries.where((t) => t.isDefault);
      setState(() {
        _treasuries = treasuries;
        _categories = results[1] as List<ExpenseCategoryModel>;
        _selectedTreasury = defaultTreasuries.isNotEmpty
            ? defaultTreasuries.first
            : (treasuries.isNotEmpty ? treasuries.first : null);
        _loadingOptions = false;
      });
    } catch (_) {
      setState(() {
        _loadingOptions = false;
        _loadError = 'تعذر تحميل بيانات الخزائن/التصنيفات.';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTreasury == null) {
      AppSnackbar.showError(context, 'اختر خزينة');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.remote.createExpense(
        categoryId: _selectedCategory?.id,
        treasuryId: _selectedTreasury!.id,
        description: _descCtrl.text.trim(),
        amount: double.parse(_amountCtrl.text.trim()),
        expenseDate: DateFormat('yyyy-MM-dd').format(_date),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'تم تسجيل المصروف بنجاح.');
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل تسجيل المصروف.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
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
      child: _loadingOptions
          ? const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()))
          : _loadError != null
              ? SizedBox(
                  height: 200,
                  child: AppErrorView(message: _loadError!, onRetry: _loadOptions),
                )
              : SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('تسجيل مصروف جديد',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: const InputDecoration(labelText: 'الوصف'),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'المبلغ'),
                          validator: (v) {
                            final amount = double.tryParse(v ?? '');
                            if (amount == null || amount <= 0) return 'مبلغ غير صحيح';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<TreasuryModel>(
                          initialValue: _selectedTreasury,
                          decoration: const InputDecoration(labelText: 'الخزينة'),
                          items: (_treasuries ?? [])
                              .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                              .toList(),
                          onChanged: (t) => setState(() => _selectedTreasury = t),
                          validator: (v) => v == null ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<ExpenseCategoryModel?>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(labelText: 'التصنيف (اختياري)'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('بدون تصنيف')),
                            ...(_categories ?? [])
                                .map((c) => DropdownMenuItem(value: c, child: Text(c.name))),
                          ],
                          onChanged: (c) => setState(() => _selectedCategory = c),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'التاريخ'),
                            child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('حفظ المصروف'),
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

// ─── Treasuries tab ──────────────────────────────────────────────────────────

class _TreasuriesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _TreasuriesTab({required this.remote});

  @override
  State<_TreasuriesTab> createState() => _TreasuriesTabState();
}

class _TreasuriesTabState extends State<_TreasuriesTab> {
  List<TreasuryModel>? _treasuries;
  bool _loading = true;
  String? _error;

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
      final treasuries = await widget.remote.fetchTreasuries();
      setState(() {
        _treasuries = treasuries;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'فشل تحميل الخزائن.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    final treasuries = _treasuries ?? [];
    if (treasuries.isEmpty) {
      return const Center(child: Text('لا توجد خزائن.', style: TextStyle(color: Colors.grey)));
    }
    final total = treasuries.fold<double>(0, (s, t) => s + t.balance);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: AppTheme.primary,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('إجمالي أرصدة الخزائن',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text(total.toStringAsFixed(2),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...treasuries.map((t) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.secondary.withValues(alpha: 0.12),
                    child: const Icon(Icons.account_balance_outlined, color: AppTheme.secondary),
                  ),
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: t.isDefault ? const Text('الخزينة الافتراضية') : null,
                  trailing: Text(
                    '${t.balance.toStringAsFixed(2)} ${t.currency}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
