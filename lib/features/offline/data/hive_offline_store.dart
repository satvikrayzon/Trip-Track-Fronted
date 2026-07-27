import '../../../core/database/hive_database.dart';

/// Hive-backed offline queue stats (replaces Isar for Android AGP compatibility).
class HiveOfflineStore {
  HiveOfflineStore._();
  static final HiveOfflineStore instance = HiveOfflineStore._();

  final HiveDatabase _db = HiveDatabase.instance;

  Future<void> initialize() async {
    // Hive is initialized in main() via [HiveDatabase.instance.initialize].
  }

  Future<int> pendingPunchCount() async {
    final queue = await _db.getSyncQueueItems();
    final punchQueue = queue.where((item) {
      final type = item['type']?.toString().toLowerCase() ?? '';
      return type.contains('punch') || type.contains('travel');
    }).length;
    final unsyncedRequests = (await _db.getAllOfflineTravelRequests())
        .where((r) => r['isSynced'] != true)
        .length;
    return punchQueue + unsyncedRequests;
  }

  Future<int> pendingGpsCount() async {
    return _db.countUnsyncedRoutePoints();
  }
}
