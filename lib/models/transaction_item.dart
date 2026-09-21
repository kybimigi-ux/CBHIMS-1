import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionItem {
  final String? id; // Firestore document ID
  final String? transactionId;
  final String? productId;
  final String productName;
  final double quantity;
  final String unit;

  const TransactionItem({
    this.id,
    this.transactionId,
    this.productId,
    required this.productName,
    required this.quantity,
    this.unit = 'pcs',
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) {
        return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
      }
      return 0.0;
    }

    return TransactionItem(
      id: json['id']?.toString(),
      transactionId: json['transaction_id']?.toString(),
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString() ?? 'Item',
      quantity: parseDouble(json['quantity']),
      unit: json['unit']?.toString() ?? 'pcs',
    );
  }

  factory TransactionItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return TransactionItem.fromJson(data);
  }

  /// Formatted string representing quantity without unnecessary trailing zeroes.
  String get formattedQuantity {
    if (quantity % 1 == 0) {
      return quantity.toInt().toString();
    }
    return quantity.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
  }

  Map<String, dynamic> toInsertJson(String txnId) {
    return {
      'transaction_id': txnId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit': unit,
    };
  }
}
