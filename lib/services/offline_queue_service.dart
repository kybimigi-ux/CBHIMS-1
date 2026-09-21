import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/pending_transaction.dart';

/// Persists transactions that couldn't be sent to Firebase (offline or
/// a network error) so they can be retried later.
///
/// Backed by a single Hive box of raw maps, keyed by [PendingTransaction.localId].
/// Hive (not sqflite) is used because it works on web out of the box and
/// the data here is just a flat list of records — no relational queries
/// needed.
class OfflineQueueService {
  OfflineQueueService._();
  static final OfflineQueueService instance = OfflineQueueService._();

  static const _boxName = 'pending_transactions';
  Box? _box;

  /// Must be called once during app startup, after Hive.initFlutter().
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  Box get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError(
          'OfflineQueueService.init() must be called before use (e.g. in main()).');
    }
    return box;
  }

  /// Add a transaction to the queue.
  Future<void> enqueue(PendingTransaction txn) async {
    await _requireBox.put(txn.localId, txn.toJson());
  }

  /// All queued transactions, oldest first (so sync processes them in
  /// the order they were created).
  List<PendingTransaction> getAll() {
    final items = _requireBox.values
        .map((raw) =>
            PendingTransaction.fromJson(Map<dynamic, dynamic>.from(raw as Map)))
        .toList();
    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return items;
  }

  int get pendingCount => _requireBox.length;

  /// Remove a transaction from the queue (call after a successful sync).
  Future<void> remove(String localId) async {
    await _requireBox.delete(localId);
  }

  /// Update the stored error/attempt info for a queue entry, e.g. after
  /// a failed sync attempt (so the UI can show why it's stuck).
  Future<void> recordAttempt(String localId, {String? error}) async {
    final raw = _requireBox.get(localId);
    if (raw == null) return; // already removed / synced elsewhere
    final current =
        PendingTransaction.fromJson(Map<dynamic, dynamic>.from(raw as Map));
    final updated = current.copyWith(
      lastError: error,
      lastAttemptAt: DateTime.now(),
      clearError: error == null,
    );
    await _requireBox.put(localId, updated.toJson());
  }

  Future<void> clearAll() async {
    await _requireBox.clear();
  }

  void debugLog(String message) {
    debugPrint('[OfflineQueueService] $message');
  }
}