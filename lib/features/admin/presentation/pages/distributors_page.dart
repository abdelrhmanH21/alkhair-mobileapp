import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
import 'distributor_detail_page.dart';

/// "الموزعون" — admin-only (no delegate mobile-app usage), reached from the
/// العمليات sub-menu. List of distributors + running_balance, with a "+" to
/// quick-add a new one; tapping a row opens DistributorDetailPage (full
/// statement + the three independent transaction actions).
class DistributorsPage extends StatefulWidget {
  const DistributorsPage({super.key});

  @override
  State<DistributorsPage> createState() => _DistributorsPageState();
}

class _DistributorsPageState extends State<DistributorsPage> {
  final _remote = sl<AdminRemoteDataSource>();
  List<DistributorModel> _distributors = [];
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
      final list = await _remote.fetchDistributors();
      if (!mounted) return;
      setState(() {
        _distributors = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل قائمة الموزعين.';
      });
    }
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddDistributorSheet(
        onAdded: (distributor) {
          setState(() => _distributors = [..._distributors, distributor]
            ..sort((a, b) => a.name.compareTo(b.name)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموزعون'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: _openAddSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : _distributors.isEmpty
                  ? const Center(
                      child: Text('لا يوجد موزعون بعد.', style: TextStyle(color: AppTheme.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _distributors.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final d = _distributors[i];
                          final owesUs = d.runningBalance > 0;
                          final settled = d.runningBalance == 0;
                          return Card(
                            color: AppTheme.cardBg,
                            surfaceTintColor: Colors.transparent,
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppTheme.primary,
                                child: Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
                              ),
                              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: d.phone != null ? Text(d.phone!) : null,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    d.runningBalance.abs().toStringAsFixed(2),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: settled
                                          ? AppTheme.textMuted
                                          : owesUs
                                              ? AppTheme.danger
                                              : AppTheme.secondary,
                                    ),
                                  ),
                                  Text(
                                    settled ? 'مسوّى' : (owesUs ? 'مستحق' : 'رصيد له'),
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DistributorDetailPage(distributorId: d.id, distributorName: d.name),
                                  ),
                                );
                                if (mounted) _load();
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _AddDistributorSheet extends StatefulWidget {
  final void Function(DistributorModel) onAdded;
  const _AddDistributorSheet({required this.onAdded});

  @override
  State<_AddDistributorSheet> createState() => _AddDistributorSheetState();
}

class _AddDistributorSheetState extends State<_AddDistributorSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppSnackbar.showError(context, 'يرجى إدخال اسم الموزع.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final distributor = await sl<AdminRemoteDataSource>().createDistributor(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      widget.onAdded(distributor);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        AppSnackbar.showError(context, 'فشل إضافة الموزع.');
      }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('إضافة موزع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 10),
          TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)')),
          const SizedBox(height: 10),
          TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('حفظ'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
