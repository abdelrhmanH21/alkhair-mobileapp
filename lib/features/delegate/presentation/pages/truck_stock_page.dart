import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/models/loading_model.dart';
import '../sync/delegate_sync_service.dart';

class TruckStockPage extends StatefulWidget {
  const TruckStockPage({super.key});

  @override
  State<TruckStockPage> createState() => _TruckStockPageState();
}

class _TruckStockPageState extends State<TruckStockPage> {
  // The stock list itself lives in the shared DelegateSyncService: it is
  // refetched whenever sync-state's stock_version moves (pickup, top-up,
  // sale, return, invoice edit, settlement), so this tab — kept alive
  // forever in DelegateHomePage's IndexedStack — no longer shows the
  // snapshot from whenever it was first built.
  List<TruckStockModel> _stocks = const [];

  @override
  void initState() {
    super.initState();
    // Opened as its own route (from the sell screen) → make sure it's fresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DelegateSyncScope.of(context, listen: false).refreshNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = DelegateSyncScope.of(context);
    _stocks = sync.truckStock;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مخزون الشاحنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: () => sync.refreshNow(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => sync.refreshNow(force: true),
        child: _buildBody(sync),
      ),
    );
  }

  Widget _buildBody(DelegateSyncService sync) {
    if (_stocks.isEmpty) {
      final Widget content;
      if (!sync.hasSyncedOnce && !sync.lastSyncFailed) {
        content = const Center(child: CircularProgressIndicator());
      } else if (!sync.hasSyncedOnce) {
        content = AppErrorView(
          title: 'تعذر تحميل مخزون الشاحنة',
          message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
          onRetry: () => sync.refreshNow(force: true),
        );
      } else {
        content = const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text('لا يوجد مخزون في الشاحنة', style: TextStyle(color: AppTheme.textMuted)),
            ],
          ),
        );
      }
      // Scrollable so pull-to-refresh works on the empty state too.
      return LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: content),
        ),
      );
    }
    return Column(
      children: [
        OfflineDataBanner(show: sync.isShowingStaleData),
        Expanded(child: _buildStockList()),
      ],
    );
  }

  Widget _buildStockList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _stocks.length,
      itemBuilder: (_, i) {
        final s = _stocks[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(s.productName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('الوحدة: ${s.productUnit}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.currentStockQty.toStringAsFixed(2),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary),
                ),
                const Text('متبقي',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ),
        );
      },
    );
  }
}
