import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/client_model.dart';

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
  final _regionCtrl  = TextEditingController();
  final _balanceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _regionCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<DelegateBloc>().add(DelegateClientCreated(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          region: _regionCtrl.text.trim().isNotEmpty
              ? _regionCtrl.text.trim()
              : null,
          initialBalance: double.tryParse(_balanceCtrl.text),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (ctx, state) {
        if (state is DelegateClientCreatedState) {
          widget.onClientAdded(state.client);
          Navigator.of(ctx).pop();
        }
        if (state is DelegateFailure) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppTheme.danger,
          ));
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
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'الهاتف مطلوب' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _regionCtrl,
                decoration: const InputDecoration(
                    labelText: 'المنطقة / العنوان',
                    prefixIcon: Icon(Icons.location_on_outlined)),
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
