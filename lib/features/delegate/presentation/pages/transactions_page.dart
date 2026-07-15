import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/client_model.dart';
import '../../data/models/transaction_record_models.dart';
import '../widgets/client_search_field.dart';
import '../widgets/add_client_sheet.dart';

/// معاملات tab: two lightweight route-side actions that don't belong to the
/// invoice flow — recording a real expense (fuel, tolls, ...) and collecting
/// an old debt payment from a customer with no invoice involved — plus the
/// current shift's own history of both, editable while the loading is still
/// active. Everything here is gated behind an active loading, same as
/// selling/settlement.
class TransactionsPage extends StatefulWidget {
  final bool hasActiveLoading;
  /// Bumped by DelegateHomePage each time this tab is (re)selected, so the
  /// shift's expense/collection lists refresh instead of showing a stale
  /// IndexedStack snapshot from the first visit (same pattern as
  /// InvoiceHistoryPage.refreshTick).
  final int refreshTick;
  const TransactionsPage({super.key, required this.hasActiveLoading, this.refreshTick = 0});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<ExpenseRecordModel> _expenses = [];
  List<CustomerCollectionRecordModel> _collections = [];

  @override
  void initState() {
    super.initState();
    _fetchLists();
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _fetchLists();
    }
  }

  void _fetchLists() {
    context.read<DelegateBloc>().add(DelegateExpenseRecordsFetched());
    context.read<DelegateBloc>().add(DelegateCustomerCollectionRecordsFetched());
  }

  void _openExpenseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: const _ExpenseFormSheet(),
      ),
    );
  }

  void _openCollectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: const _CollectionFormSheet(),
      ),
    );
  }

  void _openExpenseEditSheet(ExpenseRecordModel expense) {
    if (!widget.hasActiveLoading) {
      AppSnackbar.showInfo(context, 'لا يمكن التعديل بعد تسليم الوردية');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _ExpenseEditSheet(expense: expense),
      ),
    );
  }

  void _openCollectionEditSheet(CustomerCollectionRecordModel collection) {
    if (!widget.hasActiveLoading) {
      AppSnackbar.showInfo(context, 'لا يمكن التعديل بعد تسليم الوردية');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _CollectionEditSheet(collection: collection),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاملات')),
      body: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateExpenseRecordsLoaded) {
            setState(() => _expenses = state.expenses);
          } else if (state is DelegateCustomerCollectionRecordsLoaded) {
            setState(() => _collections = state.collections);
          } else if (state is DelegateExpenseSubmittedState ||
              state is DelegateExpenseRecordUpdatedState) {
            _fetchLists();
          } else if (state is DelegateCustomerCollectionSubmittedState ||
              state is DelegateCustomerCollectionRecordUpdatedState) {
            _fetchLists();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.hasActiveLoading)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.danger, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'لا توجد تحميلة نشطة حالياً — لا يمكن تسجيل مصروف أو تحصيل الآن.',
                        style: TextStyle(color: AppTheme.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            _ActionCard(
              icon: Icons.receipt_long_outlined,
              color: AppTheme.danger,
              title: 'تسجيل مصروف',
              subtitle: 'وقود، رسوم، أو أي مصروف أثناء الجولة',
              enabled: widget.hasActiveLoading,
              onTap: () => _openExpenseSheet(context),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.payments_outlined,
              color: AppTheme.secondary,
              title: 'تحصيل من عميل',
              subtitle: 'تحصيل دفعة من دين عميل بدون فاتورة',
              enabled: widget.hasActiveLoading,
              onTap: () => _openCollectionSheet(context),
            ),
            const SizedBox(height: 24),
            Text('مصروفات الوردية', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد مصروفات مسجلة في هذه الوردية.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ..._expenses.map((e) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined, color: AppTheme.danger),
                      title: Text(e.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        [
                          if (e.categoryName != null) e.categoryName!,
                          DateFormat('HH:mm').format(e.createdAt),
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        e.amount.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger),
                      ),
                      onTap: () => _openExpenseEditSheet(e),
                    ),
                  )),
            const SizedBox(height: 24),
            Text('تحصيلات الوردية', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_collections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد تحصيلات مسجلة في هذه الوردية.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ..._collections.map((c) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined, color: AppTheme.secondary),
                      title: Text(c.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('HH:mm').format(c.createdAt),
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        c.amount.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary),
                      ),
                      onTap: () => _openCollectionEditSheet(c),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? onTap
              : () => AppSnackbar.showInfo(
                  context, 'لا توجد تحميلة نشطة حالياً — لا يمكنك القيام بهذا الإجراء.'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (enabled ? color : Colors.grey).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: enabled ? color : Colors.grey, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: enabled ? null : Colors.grey)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: enabled ? Colors.grey.shade600 : Colors.grey.shade400)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded,
                    color: enabled ? Colors.grey.shade400 : Colors.grey.shade300),
              ],
            ),
          ),
        ),
      );
}

// ─── تسجيل مصروف ─────────────────────────────────────────────────────────────

class _ExpenseFormSheet extends StatefulWidget {
  const _ExpenseFormSheet();

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      AppSnackbar.showError(context, 'يرجى إدخال وصف المصروف.');
      return;
    }
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(DelegateExpenseSubmitted(
          amount: amount,
          description: _descCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateExpenseSubmittedState) {
            Navigator.pop(ctx);
            AppSnackbar.showSuccess(ctx, state.message);
          } else if (state is DelegateFailure) {
            setState(() => _submitting = false);
            AppSnackbar.showError(ctx, state.message);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تسجيل مصروف',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                hintText: '0',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                hintText: 'مثال: سولار سيارة',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ المصروف'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── تعديل مصروف (الوردية الحالية فقط) ───────────────────────────────────────

class _ExpenseEditSheet extends StatefulWidget {
  final ExpenseRecordModel expense;
  const _ExpenseEditSheet({required this.expense});

  @override
  State<_ExpenseEditSheet> createState() => _ExpenseEditSheetState();
}

class _ExpenseEditSheetState extends State<_ExpenseEditSheet> {
  late final _amountCtrl = TextEditingController(text: widget.expense.amount.toStringAsFixed(2));
  late final _descCtrl = TextEditingController(text: widget.expense.description);
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      AppSnackbar.showError(context, 'يرجى إدخال وصف المصروف.');
      return;
    }
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(DelegateExpenseRecordUpdateRequested(
          id: widget.expense.id,
          amount: amount,
          description: _descCtrl.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateExpenseRecordUpdatedState) {
            Navigator.pop(ctx);
            AppSnackbar.showSuccess(ctx, 'تم تعديل المصروف بنجاح.');
          } else if (state is DelegateFailure) {
            setState(() => _submitting = false);
            AppSnackbar.showError(ctx, state.message);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تعديل مصروف', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── تحصيل من عميل ───────────────────────────────────────────────────────────

class _CollectionFormSheet extends StatefulWidget {
  const _CollectionFormSheet();

  @override
  State<_CollectionFormSheet> createState() => _CollectionFormSheetState();
}

class _CollectionFormSheetState extends State<_CollectionFormSheet> {
  ClientModel? _selectedClient;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<ClientModel> _searchResults = [];
  bool _searchLoading = false;

  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _paymentMethod = 'cash';
  bool _submitting = false;

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) {
      setState(() => _searchLoading = true);
      context.read<DelegateBloc>().add(DelegateClientSearchRequested(''));
    }
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedClient == null) {
      AppSnackbar.showError(context, 'يرجى اختيار عميل أولاً.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(DelegateCustomerCollectionSubmitted(
          customerId: _selectedClient!.id,
          amount: amount,
          paymentMethod: _paymentMethod,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ));
  }

  void _openAddClientSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: AddClientSheet(
          onClientAdded: (client) => setState(() {
            _selectedClient = client;
            _searchCtrl.text = client.name;
            _searchResults.clear();
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateClientSearchResults) {
            setState(() {
              _searchResults = state.clients;
              _searchLoading = false;
            });
          } else if (state is DelegateCustomerCollectionSubmittedState) {
            Navigator.pop(ctx);
            AppSnackbar.showSuccess(ctx, state.message);
          } else if (state is DelegateFailure) {
            setState(() {
              _submitting = false;
              _searchLoading = false;
            });
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (context, state) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تحصيل من عميل',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ClientSearchField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              results: _searchResults,
              isLoading: _searchLoading,
              selectedClient: _selectedClient,
              onSearch: (q) {
                setState(() => _searchLoading = true);
                context.read<DelegateBloc>().add(DelegateClientSearchRequested(q));
              },
              onSelect: (c) => setState(() {
                _selectedClient = c;
                _searchCtrl.text = c.name;
                _searchResults.clear();
              }),
              onAddNew: _openAddClientSheet,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المحصّل',
                hintText: '0',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('نقدي'),
                    selected: _paymentMethod == 'cash',
                    onSelected: (_) => setState(() => _paymentMethod = 'cash'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('محفظة إلكترونية'),
                    selected: _paymentMethod == 'wallet',
                    onSelected: (_) => setState(() => _paymentMethod = 'wallet'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ التحصيل'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── تعديل تحصيل (الوردية الحالية فقط) ───────────────────────────────────────

class _CollectionEditSheet extends StatefulWidget {
  final CustomerCollectionRecordModel collection;
  const _CollectionEditSheet({required this.collection});

  @override
  State<_CollectionEditSheet> createState() => _CollectionEditSheetState();
}

class _CollectionEditSheetState extends State<_CollectionEditSheet> {
  late final _amountCtrl =
      TextEditingController(text: widget.collection.amount.toStringAsFixed(2));
  late final _notesCtrl = TextEditingController(text: widget.collection.notes ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(DelegateCustomerCollectionRecordUpdateRequested(
          id: widget.collection.id,
          amount: amount,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateCustomerCollectionRecordUpdatedState) {
            Navigator.pop(ctx);
            AppSnackbar.showSuccess(ctx, 'تم تعديل التحصيل بنجاح.');
          } else if (state is DelegateFailure) {
            setState(() => _submitting = false);
            AppSnackbar.showError(ctx, state.message);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تعديل تحصيل — ${widget.collection.customerName}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المحصّل',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
  }
}
