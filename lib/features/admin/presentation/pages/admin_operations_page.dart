import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'admin_sale_page.dart';
import 'admin_price_edit_page.dart';

/// "العمليات" — admin-initiated operations list, reachable from the drawer.
/// Currently holds "عملية بيع" and "تعديل سعر"; new admin operations should
/// be added here as additional _OperationCard entries rather than as
/// separate drawer items, so this stays the single place admins look for
/// one-off actions.
class AdminOperationsPage extends StatelessWidget {
  const AdminOperationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العمليات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OperationCard(
            icon: Icons.point_of_sale_outlined,
            color: AppTheme.primary,
            title: 'عملية بيع',
            subtitle: 'بيع مباشر لعميل — لا يُنسب لأي مندوب',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminSalePage())),
          ),
          const SizedBox(height: 12),
          _OperationCard(
            icon: Icons.price_change_outlined,
            color: AppTheme.accent,
            title: 'تعديل سعر',
            subtitle: 'تعديل سعر الجملة لمنتج أو سعر تكلفة لمادة خام',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminPriceEditPage())),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OperationCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        color: AppTheme.cardBg,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(subtitle,
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
