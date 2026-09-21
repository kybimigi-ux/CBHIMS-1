import 'package:cloud_firestore/cloud_firestore.dart';
import 'transaction_item.dart';

class Transaction {
  final String? id; // Firestore document ID
  final String billNo;
  final String type; // 'Receive' or 'Release'
  final double totalItems;
  final String? remarks;
  final String? issuedTo;
  final String? createdBy; // UID of the user
  final String? createdByName; // resolved from users collection
  final DateTime? createdAt;
  final List<TransactionItem> items;

  /// Set only for transactions that were queued while offline.
  final String? localId;

  /// True until this transaction is confirmed to have reached Firestore.
  final bool isPendingSync;

  const Transaction({
    this.id,
    required this.billNo,
    required this.type,
    this.totalItems = 0.0,
    this.remarks,
    this.issuedTo,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.items = const [],
    this.localId,
    this.isPendingSync = false,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Resolve user name that was injected by the service layer
    String? userName;
    if (json['users'] != null && json['users'] is Map) {
      userName = json['users']['full_name'] as String?;
    }
    userName ??= json['created_by_name'] as String?;

    // Handle transaction_items if present (injected by service layer)
    List<TransactionItem> txnItems = [];
    if (json['transaction_items'] != null &&
        json['transaction_items'] is List) {
      txnItems = (json['transaction_items'] as List)
          .map((item) =>
              TransactionItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    DateTime? parsedDate;
    final rawDate = json['created_at'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate);
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    }

    double parsedTotalItems = 0.0;
    if (json['total_items'] is num) {
      parsedTotalItems = (json['total_items'] as num).toDouble();
    } else if (json['total_items'] is String) {
      parsedTotalItems =
          double.tryParse((json['total_items'] as String).replaceAll(',', '.')) ??
              0.0;
    }

    return Transaction(
      id: json['id']?.toString(),
      billNo: json['bill_no']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Receive',
      totalItems: parsedTotalItems,
      remarks: json['remarks']?.toString(),
      issuedTo: json['issued_to']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdByName: userName,
      createdAt: parsedDate,
      items: txnItems,
      localId: null,
      isPendingSync: false,
    );
  }

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Transaction.fromJson(data);
  }

  /// Formatted string representing totalItems without unnecessary trailing zeroes.
  String get formattedTotalItems {
    if (totalItems % 1 == 0) {
      return totalItems.toInt().toString();
    }
    return totalItems.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'bill_no': billNo,
      'type': type,
      'status': 'Completed',
      'total_items': totalItems,
      if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
      if (createdBy != null) 'created_by': createdBy,
    };
  }
}