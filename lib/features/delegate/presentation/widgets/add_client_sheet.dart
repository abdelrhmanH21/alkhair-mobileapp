import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/client_model.dart';
import '../../data/models/customer_region_model.dart';

enum _AddClientReq { regions, create }

class AddClientSheet extends StatefulWidget {
  final void Function(ClientModel client) onClientAdded;
  const AddClientSheet({super.key, required this.onClientAdded});

  @override
  State<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<AddClientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _balanceCtrl = TextEditingController();

  List<CustomerRegionModel> _regions = [];
  CustomerRegionModel? _selectedRegion;
  String? _phoneError;

  // This sheet is always opened on top of an already-mounted screen sharing
  // the same DelegateBloc (InvoicePage, TransactionsPage's collection sheet,
  // ...) — tracks this sheet's own two dispatches by requestId so an
  // unrelated DelegateFailure from underneath can never surface here.
  final _tracker = RequestTracker<_AddClientReq>();

  @override
  void initState() {
    super.initState();
    final event = DelegateCustomerRegionsFetched();
    _tracker.start(event.requestId, _AddClientReq.regions);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _phoneError = null);
    if (!_formKey.currentState!.validate()) return;
    final event = DelegateClientCreated(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      customerRegionId: _selectedRegion?.id,
      initialBalance: double.tryParse(_balanceCtrl.text),
    );
    _tracker.start(event.requestId, _AddClientReq.create);
    context.read<DelegateBloc>().add(event);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (ctx, state) {
        if (state is DelegateClientCreatedState) {
          if (_tracker.resolve(state.requestId) == null) return;
          widget.onClientAdded(state.client);
          Navigator.of(ctx).pop();
        }
        if (state is DelegateCustomerRegionsLoaded) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() => _regions = state.regions);
        }
        if (state is DelegateClientValidationFailure) {
          if (_tracker.resolve(state.requestId) == null) return;
          final phoneErrors = state.errors['phone'];
          if (phoneErrors != null && phoneErrors.isNotEmpty) {
            setState(() {
              _phoneError = phoneErrors.first;
              _formKey.currentState?.validate();
            });
          } else {
            AppSnackbar.showError(ctx, state.message);
          }
        }
        if (state is DelegateFailure) {
          if (_tracker.resolve(state.requestId) == null) return;
          AppSnackbar.showError(ctx, state.message);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('إضافة عميل جديد',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم العميل *',
                    prefixIcon: Icon(Icons.person_outline)),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'رقم الهاتف *',
                    prefixIcon: Icon(Icons.phone_outlined)),
                onChanged: (_) {
                  if (_phoneError != null) setState(() => _phoneError = null);
                },
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'الهاتف مطلوب';
                  return _phoneError;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<CustomerRegionModel>(
                value: _selectedRegion,
                hint: const Text('اختر منطقة'),
                decoration: const InputDecoration(
                    labelText: 'المنطقة',
                    prefixIcon: Icon(Icons.location_on_outlined)),
                items: _regions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedRegion = v),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'رصيد افتتاحي مستحق',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
              ),
              const SizedBox(height: 16),
              BlocBuilder<DelegateBloc, DelegateState>(
                builder: (_, state) => ElevatedButton.icon(
                  onPressed: state is DelegateLoading ? null : _submit,
                  icon: state is DelegateLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('حفظ العميل'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
