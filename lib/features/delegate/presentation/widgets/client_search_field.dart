import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/client_model.dart';

/// Shared customer search/select field: text input with live results
/// dropdown, a selected-client summary card (showing outstanding debt), and
/// an "add new client" FAB. Used by invoice_page.dart's sale flow and by the
/// معاملات tab's customer-collection form — kept as one widget so both stay
/// visually/behaviorally identical rather than drifting apart.
class ClientSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<ClientModel> results;
  final bool isLoading;
  final ClientModel? selectedClient;
  final void Function(String) onSearch;
  final void Function(ClientModel) onSelect;
  final VoidCallback onAddNew;
  /// Opens سجل الفواتير السابقة for a client. Optional — callers that don't
  /// need this entry point (e.g. the معاملات tab's collection form) simply
  /// omit it and no history icon is shown.
  final void Function(ClientModel)? onViewHistory;

  const ClientSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.isLoading,
    required this.selectedClient,
    required this.onSearch,
    required this.onSelect,
    required this.onAddNew,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن العميل (اسم أو هاتف)...',
                    prefixIcon: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : const Icon(Icons.search),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              onSearch('');
                            })
                        : null,
                  ),
                  onChanged: (v) {
                    if (v.isEmpty || v.length >= 2) onSearch(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'add_client_fab',
                onPressed: onAddNew,
                backgroundColor: AppTheme.primary,
                tooltip: 'إضافة عميل جديد',
                child: const Icon(Icons.person_add, color: Colors.white),
              ),
            ],
          ),
          if (selectedClient != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.secondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedClient!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(selectedClient!.phone,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (onViewHistory != null)
                    IconButton(
                      icon: const Icon(Icons.history, color: AppTheme.primary, size: 20),
                      tooltip: 'عرض السجل',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onViewHistory!(selectedClient!),
                    ),
                  if (selectedClient!.balance > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'دين: ${selectedClient!.balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          if (results.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: AppTheme.shadowColor, blurRadius: 10)],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.phone,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.balance > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              '${c.balance.toStringAsFixed(0)} دين',
                              style: const TextStyle(
                                  color: AppTheme.danger, fontSize: 11),
                            ),
                          ),
                        if (onViewHistory != null)
                          IconButton(
                            icon: const Icon(Icons.history, size: 18),
                            tooltip: 'عرض السجل',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => onViewHistory!(c),
                          ),
                      ],
                    ),
                    onTap: () => onSelect(c),
                  );
                },
              ),
            ),
        ],
      );
}
