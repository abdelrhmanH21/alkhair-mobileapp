import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/location_service.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../data/models/client_model.dart';
import '../../domain/repositories/delegate_repository.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../widgets/add_client_sheet.dart';
import '../widgets/client_search_field.dart';
import 'customer_location_controller.dart';

/// تسجيل موقع عميل (عمليات tab): pick a customer (cached list works
/// offline) or add a new one, then ONE button captures the phone's GPS fix
/// and saves it as the customer's pin. Location is read only on that tap —
/// no background or continuous tracking.
class CustomerLocationPage extends StatefulWidget {
  /// Tests inject a controller wired to a fake LocationService.
  final CustomerLocationController? controller;
  const CustomerLocationPage({super.key, this.controller});

  @override
  State<CustomerLocationPage> createState() => _CustomerLocationPageState();
}

class _CustomerLocationPageState extends State<CustomerLocationPage> {
  late final CustomerLocationController _ctrl = widget.controller ??
      CustomerLocationController(
        location: sl<LocationService>(),
        send: (id, fix) => sl<DelegateRepository>().submitCustomerLocation(
          customerId: id,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyM: double.parse(fix.accuracyM.toStringAsFixed(2)),
          capturedAt: fix.capturedAt,
        ),
        isOnline: () => sl<ConnectivityService>().isOnline,
        enqueue: (a) => sl<PendingActionQueue>().enqueue(a),
      );

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _tracker = RequestTracker<bool>();
  List<ClientModel> _results = [];
  bool _searchLoading = false;
  ClientModel? _selected;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    _ctrl.addListener(_onCaptureChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCaptureChanged);
    if (widget.controller == null) _ctrl.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) _search('', showCached: true);
  }

  void _search(String q, {bool showCached = false}) {
    final bloc = context.read<DelegateBloc>();
    final cached = showCached ? bloc.getCachedCustomerList() : const <ClientModel>[];
    final event = DelegateClientSearchRequested(q);
    _tracker.start(event.requestId, true);
    setState(() {
      if (cached.isNotEmpty) _results = cached;
      _searchLoading = cached.isEmpty;
    });
    bloc.add(event);
  }

  void _select(ClientModel c) {
    _ctrl.reset();
    setState(() {
      _selected = c;
      _searchCtrl.text = c.name;
      _results = [];
    });
    _searchFocus.unfocus();
  }

  void _openAddClientSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        // A brand-new customer goes straight to the capture panel.
        child: AddClientSheet(onClientAdded: _select),
      ),
    );
  }

  void _onCaptureChanged() {
    if (!mounted) return;
    final c = _selected;
    switch (_ctrl.status) {
      case CaptureStatus.success:
        AppSnackbar.showSuccess(context, 'تم تسجيل الموقع${c != null ? ' — ${c.name}' : ''}');
        _readyForNext();
        break;
      case CaptureStatus.savedOffline:
        AppSnackbar.showQueued(context, 'تم الحفظ محليًا وسيُرسل عند توفر الإنترنت');
        _readyForNext();
        break;
      default:
        setState(() {});
    }
  }

  /// Search cleared and focused for the next customer.
  void _readyForNext() {
    setState(() {
      _selected = null;
      _searchCtrl.clear();
      _results = [];
    });
    _searchFocus.requestFocus();
  }

  Future<bool> _confirmReplace(DateTime? previous) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استبدال الموقع؟'),
        content: Text(previous != null
            ? 'هذا العميل له موقع مسجل بتاريخ ${_fmt(previous)}.\nهل تريد استبداله بموقعك الحالي؟'
            : 'هذا العميل له موقع مسجل بالفعل.\nهل تريد استبداله بموقعك الحالي؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استبدال')),
        ],
      ),
    );
    return ok == true;
  }

  static String _fmt(DateTime d) => DateFormat('yyyy/MM/dd – HH:mm').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل موقع عميل')),
      body: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateClientSearchResults) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() {
              _results = state.clients;
              _searchLoading = false;
            });
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _searchLoading = false);
            AppSnackbar.showError(ctx, state.message);
          }
        },
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            ClientSearchField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              results: _results,
              isLoading: _searchLoading,
              selectedClient: null,
              showLocationMarker: true,
              onSearch: (q) => _search(q),
              onSelect: _select,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _openAddClientSheet,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('+ عميل جديد'),
              ),
            ),
            const SizedBox(height: 16),
            if (_selected == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'ابحث عن العميل أو أضف عميلًا جديدًا، ثم اضغط «تسجيل الموقع» وأنت عنده.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              )
            else
              _CapturePanel(
                client: _selected!,
                ctrl: _ctrl,
                format: _fmt,
                onCapture: () => _ctrl.capture(_selected!, confirmReplace: _confirmReplace),
                onSaveAnyway: () => _ctrl.saveAnyway(_selected!),
                onOpenLocationSettings: () => _ctrl.locationService.openLocationSettings(),
                onOpenAppSettings: () => _ctrl.locationService.openAppSettings(),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapturePanel extends StatelessWidget {
  final ClientModel client;
  final CustomerLocationController ctrl;
  final String Function(DateTime) format;
  final VoidCallback onCapture;
  final VoidCallback onSaveAnyway;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  const _CapturePanel({
    required this.client,
    required this.ctrl,
    required this.format,
    required this.onCapture,
    required this.onSaveAnyway,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  @override
  Widget build(BuildContext context) {
    final recorded = client.hasLocation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(client.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _InfoRow(icon: Icons.phone_outlined, text: client.phone.isEmpty ? '—' : client.phone, ltr: true),
            _InfoRow(icon: Icons.map_outlined, text: client.regionName ?? 'بدون منطقة'),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(recorded ? Icons.location_on : Icons.location_off_outlined,
                    size: 18, color: recorded ? AppTheme.secondary : AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    recorded
                        ? (client.locationRecordedAt != null
                            ? 'الموقع مسجل بتاريخ ${format(client.locationRecordedAt!)}'
                            : 'الموقع مسجل')
                        : 'الموقع غير مسجل',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: recorded ? AppTheme.secondary : AppTheme.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                key: const Key('capture-location-button'),
                onPressed: ctrl.busy ? null : onCapture,
                icon: ctrl.busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.my_location),
                label: Text(_busyLabel ?? 'تسجيل الموقع', style: const TextStyle(fontSize: 17)),
              ),
            ),
            ..._statusSection(),
          ],
        ),
      ),
    );
  }

  String? get _busyLabel {
    switch (ctrl.status) {
      case CaptureStatus.checking:
        return 'جاري التحقق من الإذن...';
      case CaptureStatus.locating:
        return 'جاري تحديد الموقع...';
      case CaptureStatus.sending:
        return 'جاري الحفظ...';
      default:
        return null;
    }
  }

  List<Widget> _statusSection() {
    switch (ctrl.status) {
      case CaptureStatus.servicesOff:
        return _notice(
          'خدمة الموقع (GPS) مغلقة على الهاتف. فعّلها ثم اضغط «تسجيل الموقع».',
          actions: [_Action('تفعيل الموقع', onOpenLocationSettings)],
        );
      case CaptureStatus.permissionDenied:
        return _notice(
          'لم يُسمح للتطبيق بالوصول إلى الموقع. نستخدمه فقط لحظة الضغط على «تسجيل الموقع» لحفظ مكان العميل — اضغط الزر مرة أخرى واختر «السماح».',
        );
      case CaptureStatus.permissionDeniedForever:
        return _notice(
          'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق ← الأذونات ← الموقع واختر «السماح أثناء استخدام التطبيق».',
          actions: [_Action('فتح الإعدادات', onOpenAppSettings)],
        );
      case CaptureStatus.timeout:
        return _notice(
          'لم يتم التقاط إشارة GPS خلال ${ctrl.policy.firstFixTimeout.inSeconds} ثانية. اقترب من مكان مكشوف ثم أعد المحاولة.',
          actions: [_Action('إعادة المحاولة', onCapture)],
        );
      case CaptureStatus.weakAccuracy:
        return _notice(
          'الدقة ضعيفة (±${ctrl.fix?.accuracyM.round() ?? '?'} م)',
          color: AppTheme.accent,
          actions: [_Action('إعادة المحاولة', onCapture), _Action('حفظ رغم ذلك', onSaveAnyway)],
        );
      case CaptureStatus.notApplied:
        return _notice('يوجد موقع أحدث مسجل لهذا العميل، لذلك لم يتم استبداله.', color: AppTheme.accent);
      case CaptureStatus.error:
        return _notice(ctrl.message ?? 'حدث خطأ.', actions: [_Action('إعادة المحاولة', onCapture)]);
      default:
        return const [];
    }
  }

  List<Widget> _notice(String text, {Color color = AppTheme.danger, List<_Action> actions = const []}) => [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in actions) OutlinedButton(onPressed: a.onTap, child: Text(a.label)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ];
}

class _Action {
  final String label;
  final VoidCallback onTap;
  const _Action(this.label, this.onTap);
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool ltr;
  const _InfoRow({required this.icon, required this.text, this.ltr = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(text, textDirection: ltr ? TextDirection.ltr : null, style: const TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
}
