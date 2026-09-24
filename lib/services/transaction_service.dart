import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import 'hardware_context.dart';
import 'product_service.dart';
import 'package:uuid/uuid.dart';
import '../models/pending_transaction.dart';
import 'offline_queue_service.dart';

List<String>? _billNoCache;

bool _looksLikeConnectivityError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection closed') ||
      s.contains('network is unreachable') ||
      s.contains('timeoutexception') ||
      s.contains('no internet') ||
      s.contains('unavailable');
}

/// Fetch distinct bill numbers for autocomplete. Cached in-memory after first fetch.
Future<List<String>> getAllBillNumbers() async {
  if (_billNoCache != null) return _billNoCache!;
  try {
    final hwId = HardwareContext.instance.activeHardware?.id;
    if (hwId == null || hwId.isEmpty) return [];
    final snap = await FirebaseFirestore.instance
        .collection('hardwares')
        .doc(hwId)
        .collection('transactions')
        .get();
    final seen = <String>{};
    for (final doc in snap.docs) {
      final billNo = doc.data()['bill_no']?.toString().trim();
      if (billNo != null && billNo.isNotEmpty) seen.add(billNo);
    }
    _billNoCache = seen.toList()..sort();
    return _billNoCache!;
  } catch (e) {
    debugPrint('[TransactionService] Failed to load bill numbers: $e');
    return _billNoCache ?? [];
  }
}

/// Call after creating a transaction so the next autocomplete includes
/// the bill number that was just used.
void refreshBillNoCache() => _billNoCache = null;

/// Thrown when an outbound transaction requests more of one or more
/// products than are currently in stock.
class InsufficientStockError implements Exception {
  final List<StockShortfall> shortfalls;
  InsufficientStockError(this.shortfalls);

  @override
  String toString() => 'InsufficientStockError: '
      '${shortfalls.map((s) => '${s.productId} (requested ${s.requested}, have ${s.available})').join(', ')}';
}

class StockShortfall {
  final String productId;
  final String? productName;
  final double requested;
  final double available;
  StockShortfall({
    required this.productId,
    required this.available,
    required this.requested,
    this.productName,
  });
}

/// Service for all transaction-related Firestore operations.
class TransactionService {
  TransactionService._();
  static final TransactionService instance = TransactionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns the transactions subcollection for the currently active hardware, or null if none.
  CollectionReference? get _transactions {
    final hwId = HardwareContext.instance.activeHardware?.id;
    if (hwId == null || hwId.isEmpty) {
      return null;
    }
    return _db.collection('hardwares').doc(hwId).collection('transactions');
  }

  /// Map of userId -> fullName cache to avoid repeated reads.
  final Map<String, String> _userNameCache = {};

  /// Map of productId -> productName cache.
  final Map<String, String> _productNameCache = {};

  bool _userNamesPreloaded = false;

  /// Preload all user names from the users collection in one read.
  Future<void> _preloadUserNames() async {
    if (_userNamesPreloaded) return;
    try {
      final snap = await _db.collection('users').get();
      for (final doc in snap.docs) {
        final data = doc.data();
        String? name = data['full_name']?.toString().trim();
        if (name == null || name.isEmpty || name.toLowerCase() == 'user') {
          final role = data['role']?.toString().trim();
          final email = data['email']?.toString().trim();
          if (role != null && role.isNotEmpty) {
            name = role[0].toUpperCase() + role.substring(1);
          } else if (email != null && email.isNotEmpty) {
            name = email.split('@').first;
          }
        }
        if (name != null && name.isNotEmpty) {
          _userNameCache[doc.id] = name;
        }
      }
      _userNamesPreloaded = true;
    } catch (e) {
      debugPrint('[TransactionService] Could not preload user names: $e');
    }
  }

  Future<String?> _getUserName(String? userId) async {
    if (userId == null || userId.isEmpty) {
      final current = _auth.currentUser;
      final metaName = current?.displayName?.trim();
      if (metaName != null &&
          metaName.isNotEmpty &&
          metaName.toLowerCase() != 'user') {
        return metaName;
      }
      final email = current?.email?.split('@').first;
      if (email != null && email.isNotEmpty) return email;
      return 'Admin';
    }

    if (_userNameCache.containsKey(userId)) return _userNameCache[userId];

    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        String? name = data['full_name']?.toString().trim();
        if (name == null || name.isEmpty || name.toLowerCase() == 'user') {
          final role = data['role']?.toString().trim();
          final email = data['email']?.toString().trim();
          if (role != null && role.isNotEmpty) {
            name = role[0].toUpperCase() + role.substring(1);
          } else if (email != null && email.isNotEmpty) {
            name = email.split('@').first;
          }
        }
        if (name != null && name.isNotEmpty) {
          _userNameCache[userId] = name;
          return name;
        }
      }
    } catch (e) {
      debugPrint('[TransactionService] Could not resolve user name: $e');
    }

    final current = _auth.currentUser;
    if (current != null && current.uid == userId) {
      final name = current.displayName?.trim();
      if (name != null && name.isNotEmpty && name.toLowerCase() != 'user') {
        _userNameCache[userId] = name;
        return name;
      }
      final email = current.email?.split('@').first;
      if (email != null && email.isNotEmpty) {
        _userNameCache[userId] = email;
        return email;
      }
    }
    return 'Admin';
  }

  /// Preload all active product names into cache (from the active hardware's products).
  Future<void> _preloadProductNames() async {
    try {
      final snap = await ProductService.instance.getAll();
      for (final p in snap) {
        if (p.id != null && p.productName.trim().isNotEmpty) {
          _productNameCache[p.id!] = p.productName.trim();
        }
      }
    } catch (e) {
      debugPrint('[TransactionService] Could not preload product names: $e');
    }
  }

  /// Load items subcollection for a list of transaction docs and resolve names.
  Future<List<Transaction>> _buildTransactionList(
      List<QueryDocumentSnapshot> docs) async {
    await _preloadUserNames();
    await _preloadProductNames();

    final transactions = <Transaction>[];

    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['id'] = doc.id;

      // Load items subcollection
      try {
        final ref = _transactions;
        if (ref != null) {
          final itemsSnap =
              await ref.doc(doc.id).collection('items').get();
          final itemsList = itemsSnap.docs.map((itemDoc) {
            final itemData = Map<String, dynamic>.from(itemDoc.data());
            itemData['id'] = itemDoc.id;
            final pid = itemData['product_id']?.toString();
            if ((itemData['product_name'] == null ||
                    itemData['product_name'].toString().trim().isEmpty) &&
                pid != null &&
                _productNameCache.containsKey(pid)) {
              itemData['product_name'] = _productNameCache[pid];
            }
            return itemData;
          }).toList();
          data['transaction_items'] = itemsList;
        }
      } catch (e) {
        debugPrint(
            '[TransactionService] Could not load items for ${doc.id}: $e');
      }

      final createdBy = data['created_by'] as String?;
      final userName = await _getUserName(createdBy);
      if (userName != null) {
        data['users'] = {'full_name': userName};
      }
      transactions.add(Transaction.fromJson(data));
    }

    return transactions;
  }

  /// Fetch all transactions, ordered by most recent.
  Future<List<Transaction>> getAll() async {
    final ref = _transactions;
    if (ref == null) return [];
    try {
      final snap = await ref
          .orderBy('created_at', descending: true)
          .get();
      return _buildTransactionList(snap.docs);
    } catch (e) {
      debugPrint('[TransactionService] getAll error: $e');
      rethrow;
    }
  }

  /// Fetch all transactions associated with a specific product ID.
  Future<List<Transaction>> getByProductId(String productId) async {
    final ref = _transactions;
    if (ref == null) return [];
    // Find all items docs across transactions that reference this product
    final allTxnSnap = await ref
        .orderBy('created_at')
        .get();

    final matchingDocs = <QueryDocumentSnapshot>[];
    for (final txnDoc in allTxnSnap.docs) {
      final itemsSnap = await ref
          .doc(txnDoc.id)
          .collection('items')
          .where('product_id', isEqualTo: productId)
          .get();
      if (itemsSnap.docs.isNotEmpty) {
        matchingDocs.add(txnDoc);
      }
    }

    return _buildTransactionList(matchingDocs);
  }

  /// Fetch a single transaction with its items.
  Future<Transaction> getById(String id) async {
    final ref = _transactions;
    if (ref == null) throw StateError('No active workspace selected.');
    final doc = await ref.doc(id).get();
    if (!doc.exists) throw Exception('Transaction $id not found');

    await _preloadProductNames();

    final data = Map<String, dynamic>.from(doc.data() as Map);
    data['id'] = doc.id;

    try {
      final itemsSnap =
          await ref.doc(id).collection('items').get();
      final itemsList = itemsSnap.docs.map((itemDoc) {
        final itemData = Map<String, dynamic>.from(itemDoc.data());
        itemData['id'] = itemDoc.id;
        final pid = itemData['product_id']?.toString();
        if ((itemData['product_name'] == null ||
                itemData['product_name'].toString().trim().isEmpty) &&
            pid != null &&
            _productNameCache.containsKey(pid)) {
          itemData['product_name'] = _productNameCache[pid];
        }
        return itemData;
      }).toList();
      data['transaction_items'] = itemsList;
    } catch (e) {
      debugPrint('[TransactionService] Failed to load items for $id: $e');
    }

    final createdBy = data['created_by'] as String?;
    final userName = await _getUserName(createdBy);
    if (userName != null) {
      data['users'] = {'full_name': userName};
    }

    return Transaction.fromJson(data);
  }

  /// Fetch the most recent transactions (for the dashboard).
  Future<List<Transaction>> getRecent({int limit = 5}) async {
    final ref = _transactions;
    if (ref == null) return [];
    final snap = await ref
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return _buildTransactionList(snap.docs);
  }

  /// Pre-check outbound stock before creating any records.
  Future<List<StockShortfall>> _checkStockAvailability(
      List<TransactionItem> items) async {
    final shortfalls = <StockShortfall>[];
    final productService = ProductService.instance;

    for (final item in items) {
      if (item.productId == null) continue;
      try {
        final available =
            await productService.getCurrentQuantity(item.productId!);
        if (item.quantity > available) {
          shortfalls.add(StockShortfall(
            productId: item.productId!,
            productName: _productNameCache[item.productId!],
            requested: item.quantity,
            available: available,
          ));
        }
      } catch (e) {
        debugPrint(
            '[TransactionService] Stock pre-check failed for ${item.productId}: $e');
      }
    }
    return shortfalls;
  }

  /// Create a new transaction. If offline, queues locally and returns a
  /// pending-sync Transaction so the UI can show it immediately.
  Future<Transaction> create({
    required String billNo,
    required String type,
    String status = 'Completed',
    required List<TransactionItem> items,
    String? remarks,
    String? issuedTo,
    String? userId,
    DateTime? createdAt,
  }) async {
    // Pre-flight stock check for outbound transactions.
    if (type.toLowerCase() == 'release') {
      final shortfalls = await _checkStockAvailability(items);
      if (shortfalls.isNotEmpty) throw InsufficientStockError(shortfalls);
    }

    try {
      return await _createRemote(
        billNo: billNo,
        type: type,
        status: status,
        items: items,
        remarks: remarks,
        issuedTo: issuedTo,
        userId: userId,
        createdAt: createdAt,
      );
    } catch (e) {
      if (e is InsufficientStockError) rethrow;
      if (!_looksLikeConnectivityError(e)) rethrow;

      debugPrint(
          '[TransactionService] create() failed due to connectivity, queuing offline: $e');

      final localId = const Uuid().v4();
      final effectiveDate = createdAt ?? DateTime.now();
      final pending = PendingTransaction(
        localId: localId,
        billNo: billNo,
        type: type,
        status: status,
        items: items,
        remarks: remarks,
        issuedTo: issuedTo,
        userId: userId,
        queuedAt: DateTime.now(),
        createdAt: effectiveDate,
      );
      await OfflineQueueService.instance.enqueue(pending);

      return Transaction(
        id: null,
        billNo: billNo,
        type: type,
        totalItems: items.fold<double>(0.0, (acc, item) => acc + item.quantity),
        remarks: (remarks != null && remarks.trim().isNotEmpty)
            ? remarks.trim()
            : 'N/A',
        createdBy: userId,
        createdByName: null,
        createdAt: effectiveDate,
        items: items,
        localId: localId,
        isPendingSync: true,
      );
    }
  }

  /// Write the transaction and its items to Firestore, then update stock.
  Future<Transaction> _createRemote({
    required String billNo,
    required String type,
    String status = 'Completed',
    required List<TransactionItem> items,
    String? remarks,
    String? issuedTo,
    String? userId,
    DateTime? createdAt,
  }) async {
    final totalItems =
        items.fold<double>(0.0, (acc, item) => acc + item.quantity);
    final finalIssuedTo =
        (issuedTo != null && issuedTo.trim().isNotEmpty) ? issuedTo.trim() : 'N/A';
    final finalRemarks =
        (remarks != null && remarks.trim().isNotEmpty) ? remarks.trim() : 'N/A';

    final typeTitle = type.isNotEmpty
        ? (type[0].toUpperCase() + type.substring(1).toLowerCase())
        : type;
    final statusCapital = status.isNotEmpty
        ? (status[0].toUpperCase() + status.substring(1).toLowerCase())
        : status;

    // Build Firestore transaction document
    final txnData = <String, dynamic>{
      'bill_no': billNo,
      'type': typeTitle,
      'total_items': totalItems,
      'status': statusCapital,
      'issued_to': finalIssuedTo,
      'remarks': finalRemarks,
      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt)
          : FieldValue.serverTimestamp(),
      if (userId != null && userId.isNotEmpty) 'created_by': userId,
    };

    final ref = _transactions;
    if (ref == null) throw StateError('No active workspace selected.');

    final txnRef = await ref.add(txnData);
    final txnId = txnRef.id;

    // Insert items as a subcollection
    if (items.isNotEmpty) {
      final batch = _db.batch();
      for (final item in items) {
        final itemRef = ref.doc(txnId).collection('items').doc();
        batch.set(itemRef, {
          'product_id': item.productId,
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit': item.unit,
          'transaction_id': txnId,
        });
      }
      await batch.commit();
    }

    // Atomically update product stock
    final productService = ProductService.instance;
    for (final item in items) {
      if (item.productId != null) {
        final quantityChange = (type.toLowerCase() == 'receive' ||
                type.toLowerCase() == 'inbound' ||
                type.toLowerCase() == 'purchase')
            ? item.quantity
            : -item.quantity;
        await productService.updateQuantity(item.productId!, quantityChange);
      }
    }

    refreshBillNoCache();

    String? createdByName;
    if (userId != null && userId.isNotEmpty) {
      createdByName = await _getUserName(userId);
    }

    return Transaction(
      id: txnId,
      billNo: billNo,
      type: typeTitle,
      totalItems: totalItems,
      remarks: finalRemarks,
      issuedTo: finalIssuedTo,
      createdBy: userId,
      createdByName: createdByName,
      createdAt: createdAt ?? DateTime.now(),
      items: items,
    );
  }

  /// Update an existing transaction's core fields, replace its items,
  /// and automatically adjust product stock to match.
  Future<Transaction> update({
    required String transactionId,
    required String billNo,
    required String type,
    required List<TransactionItem> items,
    String? remarks,
    String? issuedTo,
    DateTime? createdAt,
  }) async {
    final ref = _transactions;
    if (ref == null) throw StateError('No active workspace selected.');

    // 1. Fetch original transaction to calculate stock delta.
    Transaction? oldTxn;
    try {
      oldTxn = await getById(transactionId);
    } catch (e) {
      debugPrint(
          '[TransactionService] Could not fetch original txn for stock adjustment: $e');
    }

    final productService = ProductService.instance;

    // 2. Revert the original stock impact.
    if (oldTxn != null) {
      final oldIsReceive = oldTxn.type.toLowerCase() == 'receive' ||
          oldTxn.type.toLowerCase() == 'inbound' ||
          oldTxn.type.toLowerCase() == 'purchase';
      for (final oldItem in oldTxn.items) {
        if (oldItem.productId != null) {
          final revertDelta =
              oldIsReceive ? -oldItem.quantity : oldItem.quantity;
          await productService.updateQuantity(oldItem.productId!, revertDelta);
        }
      }
    }

    // 3. Apply updated stock impact.
    final newIsReceive = type.toLowerCase() == 'receive' ||
        type.toLowerCase() == 'inbound' ||
        type.toLowerCase() == 'purchase';
    for (final newItem in items) {
      if (newItem.productId != null) {
        final applyDelta = newIsReceive ? newItem.quantity : -newItem.quantity;
        await productService.updateQuantity(newItem.productId!, applyDelta);
      }
    }

    final totalItems =
        items.fold<double>(0.0, (acc, item) => acc + item.quantity);
    final finalIssuedTo =
        (issuedTo != null && issuedTo.trim().isNotEmpty) ? issuedTo.trim() : 'N/A';
    final finalRemarks =
        (remarks != null && remarks.trim().isNotEmpty) ? remarks.trim() : 'N/A';

    final typeTitle = type.isNotEmpty
        ? (type[0].toUpperCase() + type.substring(1).toLowerCase())
        : type;

    final updatePayload = <String, dynamic>{
      'bill_no': billNo,
      'type': typeTitle,
      'total_items': totalItems,
      'issued_to': finalIssuedTo,
      'remarks': finalRemarks,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt),
    };
    await ref.doc(transactionId).update(updatePayload);

    // Replace items: delete existing subcollection docs, insert new ones.
    try {
      final existingItems = await ref
          .doc(transactionId)
          .collection('items')
          .get();
      final batch = _db.batch();
      for (final doc in existingItems.docs) {
        batch.delete(doc.reference);
      }
      for (final item in items) {
        final newRef =
            ref.doc(transactionId).collection('items').doc();
        batch.set(newRef, {
          'product_id': item.productId,
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit': item.unit,
          'transaction_id': transactionId,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint(
          '[TransactionService] Failed to replace transaction items: $e');
      rethrow;
    }

    return getById(transactionId);
  }

  /// Delete a transaction and its items, reversing product stock.
  Future<void> deleteTransaction(String transactionId) async {
    final ref = _transactions;
    if (ref == null) return;

    // 1. Fetch original transaction to revert stock.
    Transaction? txn;
    try {
      txn = await getById(transactionId);
    } catch (e) {
      debugPrint(
          '[TransactionService] Could not fetch transaction to reverse stock: $e');
    }

    if (txn != null) {
      final productService = ProductService.instance;
      final isReceive = txn.type.toLowerCase() == 'receive' ||
          txn.type.toLowerCase() == 'inbound' ||
          txn.type.toLowerCase() == 'purchase';
      for (final item in txn.items) {
        if (item.productId != null) {
          final revertDelta = isReceive ? -item.quantity : item.quantity;
          try {
            await productService.updateQuantity(item.productId!, revertDelta);
          } catch (e) {
            debugPrint(
                '[TransactionService] Error reverting stock for ${item.productId}: $e');
          }
        }
      }
    }

    // 2. Delete items subcollection then the transaction document.
    try {
      final itemsSnap = await ref
          .doc(transactionId)
          .collection('items')
          .get();
      final batch = _db.batch();
      for (final doc in itemsSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(ref.doc(transactionId));
      await batch.commit();
    } catch (e) {
      debugPrint(
          '[TransactionService] Failed to delete transaction: $e');
      rethrow;
    }
  }
}
