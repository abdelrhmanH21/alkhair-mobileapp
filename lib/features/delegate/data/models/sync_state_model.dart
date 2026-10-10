/// GET /delegate/sync-state — the compact "did anything change?" probe the
/// DelegateSyncService polls (see DelegateSyncController on the backend).
/// Carries only identities/versions, never the heavy payloads themselves.
class SyncLoadingRef {
  final int id;
  final String status;
  final String? updatedAt;
  const SyncLoadingRef({required this.id, required this.status, this.updatedAt});

  factory SyncLoadingRef.fromJson(Map<String, dynamic> json) => SyncLoadingRef(
        id: json['id'] as int,
        status: json['status'] as String,
        updatedAt: json['updated_at'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncLoadingRef && other.id == id && other.status == status && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, status, updatedAt);
}

class SyncSettlementRef {
  final int id;
  final int loadingId;
  final String status; // 'pending' | 'confirmed'
  final String? updatedAt;
  const SyncSettlementRef({required this.id, required this.loadingId, required this.status, this.updatedAt});

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';

  factory SyncSettlementRef.fromJson(Map<String, dynamic> json) => SyncSettlementRef(
        id: json['id'] as int,
        loadingId: json['loading_id'] as int,
        status: json['status'] as String,
        updatedAt: json['updated_at'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncSettlementRef &&
      other.id == id &&
      other.loadingId == loadingId &&
      other.status == status &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, loadingId, status, updatedAt);
}

class SyncStateModel {
  final SyncLoadingRef? loading;
  final List<int> pendingAdditionIds;
  final SyncSettlementRef? settlementRequest;
  final String stockVersion;
  final DateTime? serverTime;

  const SyncStateModel({
    required this.loading,
    required this.pendingAdditionIds,
    required this.settlementRequest,
    required this.stockVersion,
    this.serverTime,
  });

  factory SyncStateModel.fromJson(Map<String, dynamic> json) {
    final loading = json['loading'] as Map<String, dynamic>?;
    final additions = json['pending_additions'] as Map<String, dynamic>? ?? const {};
    final settlement = json['settlement_request'] as Map<String, dynamic>?;
    return SyncStateModel(
      loading: loading == null ? null : SyncLoadingRef.fromJson(loading),
      pendingAdditionIds: (additions['ids'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
      settlementRequest: settlement == null ? null : SyncSettlementRef.fromJson(settlement),
      stockVersion: json['stock_version'] as String? ?? '',
      serverTime: DateTime.tryParse(json['server_time'] as String? ?? ''),
    );
  }
}

/// One sync-state round trip: either a fresh [state] (HTTP 200) or
/// [notModified] (HTTP 304 — the [etag] sent still matches).
class SyncStateResult {
  final bool notModified;
  final String? etag;
  final SyncStateModel? state;
  const SyncStateResult.notModified(this.etag)
      : notModified = true,
        state = null;
  const SyncStateResult.fresh(this.state, this.etag) : notModified = false;
}
