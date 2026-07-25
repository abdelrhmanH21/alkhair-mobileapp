import 'package:flutter/material.dart';

/// One entry in an operations bottom sheet (icon + title + subtitle,
/// tapping it runs [onTap] after the sheet closes).
class OperationSheetItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const OperationSheetItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

/// Shared sub-menu presentation for the bottom nav's multi-item
/// destinations (التصنيع / التوزيع / العمليات) — one consistent pattern
/// (a modal bottom sheet of icon+label cards) used everywhere instead of
/// three different navigation styles for three different tabs.
Future<void> showOperationSheet(
  BuildContext context, {
  required String title,
  required List<OperationSheetItem> items,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OperationCard(item: items[i]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OperationCard extends StatelessWidget {
  final OperationSheetItem item;
  const _OperationCard({required this.item});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            item.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      );
}
