import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/client_model.dart';
import '../widgets/client_search_field.dart';
import '../widgets/add_client_sheet.dart';

/// معاملات tab: two lightweight route-side actions that don't belong to the
/// invoice flow — recording a real expense (fuel, tolls, ...) and collecting
/// an old debt payment from a customer with no invoice involved. Both are
/// gated behind an active loading, same as selling/settlement.
class TransactionsPage extends StatelessWidget {
  final bool hasActiveLoading;
  const TransactionsPage({super.key, required this.hasActiveLoading});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاملات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasActiveLoading)
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
              enabled: hasActiveLoading,
              onTap: () => _openExpenseSheet(context),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.payments_outlined,
              color: AppTheme.secondary,
              title: 'تحصيل من عميل',
              subtitle: 'تحصيل دفعة من دين عميل بدون فاتورة',
              enabled: hasActiveLoading,
              onTap: () => _openCollectionSheet(context),
            ),
          ],
        ),
      ),
    );
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
