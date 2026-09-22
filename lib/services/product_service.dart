import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

/// Thrown when an outbound (or other decreasing) quantity change would
/// take a product's stock below zero.
class InsufficientStockException implements Exception {
  final String productId;
  InsufficientStockException(this.productId);

  @override
  String toString() =>
      'InsufficientStockException: not enough stock for product $productId';
}

/// Service for all product-related Firestore operations.
class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _products => _db.collection('products');

  /// Fetch all active products, ordered by name.
  Future<List<Product>> getAll() async {
    try {
      final snap = await _products.get();
      final products = snap.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive)
          .toList();
      products.sort((a, b) =>
          a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
      return products;
    } catch (e) {
      debugPrint('[ProductService] getAll error: $e');
      rethrow;
    }
  }

  /// Fetch a single product by its Firestore document ID.
  Future<Product?> getById(String id) async {
    final doc = await _products.doc(id).get();
    if (!doc.exists) return null;
    return Product.fromFirestore(doc);
  }

  /// Search products by name (client-side filter since Firestore doesn't support ILIKE).
  Future<List<Product>> search(String query) async {
    final all = await getAll();
    final lower = query.toLowerCase();
    return all
        .where((p) => p.productName.toLowerCase().contains(lower))
        .toList();
  }

  /// Insert a new product into Firestore.
  Future<Product> add(Product product) async {
    final data = product.toInsertJson();
    final ref = await _products.add(data);
    final doc = await ref.get();
    return Product.fromFirestore(doc);
  }

  /// Update an existing product by document ID.
  Future<void> update(String id, Map<String, dynamic> data) async {
    final cleanData = Map<String, dynamic>.from(data)
      ..remove('id')
      ..remove('created_at');
    try {
      await _products.doc(id).update(cleanData);
    } catch (e) {
      debugPrint('[ProductService] update failed for $id: $e');
      rethrow;
    }
  }

  /// Soft-delete a product (set is_active = false).
  Future<void> delete(String id) async {
    await _products.doc(id).update({'is_active': false});
  }

  /// Fetch current stock for a single product.
  Future<double> getCurrentQuantity(String id) async {
    final doc = await _products.doc(id).get();
    final q = (doc.data() as Map<String, dynamic>?)?['quantity'];
    if (q is num) return q.toDouble();
    if (q is String) return double.tryParse(q.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  /// Atomically adjusts product quantity using a Firestore Transaction.
  /// Throws [InsufficientStockException] if the result would go below zero.
  Future<void> updateQuantity(String id, double quantityChange) async {
    final docRef = _products.doc(id);
    await _db.runTransaction((txn) async {
      final snapshot = await txn.get(docRef);
      final data = snapshot.data() as Map<String, dynamic>?;
      final current = () {
        final q = data?['quantity'];
        if (q is num) return q.toDouble();
        if (q is String) return double.tryParse(q.replaceAll(',', '.')) ?? 0.0;
        return 0.0;
      }();
      final newQty = current + quantityChange;
      if (newQty < 0) throw InsufficientStockException(id);
      txn.update(docRef, {'quantity': newQty});
    });
  }

  /// Get total active product count.
  Future<int> getTotalCount() async {
    try {
      final snap =
          await _products.where('is_active', isEqualTo: true).count().get();
      return snap.count ?? 0;
    } catch (_) {
      try {
        final all = await getAll();
        return all.length;
      } catch (_) {
        return 0;
      }
    }
  }

  /// Get count of low-stock products (quantity <= 10 and > 0).
  Future<int> getLowStockCount() async {
    try {
      final snap = await _products
          .where('is_active', isEqualTo: true)
          .where('quantity', isLessThanOrEqualTo: 10)
          .where('quantity', isGreaterThan: 0)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      try {
        final all = await getAll();
        return all.where((p) => p.quantity <= 10 && p.quantity > 0).length;
      } catch (_) {
        return 0;
      }
    }
  }
}