import 'package:flutter/foundation.dart';
import '../models/pending_transaction.dart';
import '../models/transaction.dart';
import 'offline_queue_service.dart';
import 'transaction_service.dart';

/// Result of one sync pass over the queue.
class SyncResult {
  final int succeeded;
  final List<SyncFailure> failures;

  const SyncResult({required this.succeeded, required this.failures});

  bool get hasFailures => failures.isNotEmpty;
  int get total => succeeded + failures.length;
}

class SyncFailure {
  final PendingTransaction pending;
  final String reason;

  /// True if this looks like a genuine data conflict (e.g. duplicate bill
  /// number) rather than a transient network error — these need a human
  /// to look at them, so the sync loop leaves them in the queue with the
  /// error attached rather than silently retrying forever.
  final bool isConflict;

  const SyncFailure(
      {required this.pending, required this.reason, required this.isConflict});
}

/// Walks the offline queue and replays each entry against
/// [TransactionService.create]. Runs entries in order (oldest first) so
/// bill numbers / stock changes apply in the sequence they were made.
///
/// Deliberately does NOT run entries in parallel — concurrent inserts to
/// the same product's stock would race each other, and TransactionService
/// already does several sequential calls per create(), so parallel syncing
/// would multiply that risk.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Future<SyncResult> syncPendingTransactions() async {
    if (_isSyncing) {
      // Avoid overlapping sync runs (e.g. reconnect event fires while a
      // manual "retry" is already in flight).
      return const SyncResult(succeeded: 0, failures: []);
    }
    _isSyncing = true;

    final queue = OfflineQueueService.instance;
    final pending = queue.getAll();

    int succeeded = 0;
    final failures = <SyncFailure>[];

    try {
      for (final item in pending) {
        try {
          await TransactionService.instance.create(
            billNo: item.billNo,
            type: item.type,
            status: item.status,
            items: item.items,
            remarks: item.remarks,
            issuedTo: item.issuedTo,
            userId: item.userId,
            createdAt: item.createdAt,
          );
          await queue.remove(item.localId);
          succeeded++;
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          final isConflict =
              errStr.contains('duplicate key') || errStr.contains('unique');

          await queue.recordAttempt(item.localId, error: e.toString());
          failures.add(SyncFailure(
            pending: item,
            reason: e.toString(),
            isConflict: isConflict,
          ));

          debugPrint('[SyncService] Failed to sync ${item.localId} '
              '(bill ${item.billNo}): $e');

          // Conflicts (e.g. duplicate bill_no) stay queued with the error
          // recorded — don't keep hammering the rest of the queue blindly,
          // but do continue to the next item so one bad record doesn't
          // block everything else behind it.
          continue;
        }
      }
    } finally {
      _isSyncing = false;
    }

    return SyncResult(succeeded: succeeded, failures: failures);
  }

  /// Retry a single queue entry (e.g. user tapped "retry" on a failed item
  /// after fixing something, like renaming the bill number externally).
  Future<Transaction?> retrySingle(PendingTransaction item) async {
    final queue = OfflineQueueService.instance;
    try {
      final result = await TransactionService.instance.create(
        billNo: item.billNo,
        type: item.type,
        status: item.status,
        items: item.items,
        remarks: item.remarks,
        issuedTo: item.issuedTo,
        userId: item.userId,
        createdAt: item.createdAt,
      );
      await queue.remove(item.localId);
      return result;
    } catch (e) {
      await queue.recordAttempt(item.localId, error: e.toString());
      rethrow;
    }
  }
}