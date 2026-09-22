import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String? id; // Firestore document ID
  final String productName;
  final String? categoryId;
  final String? categoryName;
  final double quantity;
  final String unit;
  final bool isActive;
  final String? remarks;
  final DateTime? createdAt;

  const Product({
    this.id,
    required this.productName,
    this.categoryId,
    this.categoryName,
    this.quantity = 0.0,
    this.unit = 'pcs',
    this.isActive = true,
    this.remarks,
    this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    double parseQty(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) {
        return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
      }
      return 0.0;
    }

    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawName = json['product_name'] ?? json['productName'] ?? json['name'] ?? '';
    final rawIsActive = json['is_active'] ?? json['isActive'];
    final bool active = rawIsActive is bool
        ? rawIsActive
        : (rawIsActive is String
            ? rawIsActive.toLowerCase() != 'false'
            : true);

    return Product(
      id: json['id']?.toString(),
      productName: rawName.toString(),
      categoryId: (json['category_id'] ?? json['categoryId'])?.toString(),
      categoryName: (json['category_name'] ?? json['categoryName'])?.toString(),
      quantity: parseQty(json['quantity']),
      unit: json['unit']?.toString() ?? 'pcs',
      isActive: active,
      remarks: json['remarks']?.toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data() as Map<dynamic, dynamic>? ?? {};
    final data = Map<String, dynamic>.from(rawData);
    data['id'] = doc.id;
    return Product.fromJson(data);
  }

  /// Formatted string representing quantity without unnecessary trailing zeroes.
  String get formattedQuantity {
    if (quantity % 1 == 0) {
      return quantity.toInt().toString();
    }
    return quantity.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
  }

  /// Serializes fields for INSERT / UPDATE (id is NOT included — Firestore manages it).
  Map<String, dynamic> toInsertJson() {
    return {
      'product_name': productName,
      if (categoryId != null) 'category_id': categoryId,
      'quantity': quantity,
      'unit': unit,
      'is_active': isActive,
      if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  Product copyWith({
    String? id,
    String? productName,
    String? categoryId,
    String? categoryName,
    double? quantity,
    String? unit,
    bool? isActive,
    String? remarks,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      isActive: isActive ?? this.isActive,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          productName == other.productName;

  @override
  int get hashCode => id.hashCode ^ productName.hashCode;
}
