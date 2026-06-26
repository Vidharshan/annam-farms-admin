import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/domain/order_model.dart';
import '../../../shared/services/excel_import_service.dart';

class OrdersRepository {
  final SupabaseClient _client;

  OrdersRepository(this._client);



  Future<List<Order>> getAllOrders() async {
    try {
      print('Admin: Fetching all orders...');
      final response = await _client
          .from('orders')
          .select('*, order_items(*, products(*))')
          .order('created_at', ascending: false);

      final ordersJson = response as List;
      print('Admin: Received ${ordersJson.length} orders');

      // Manual join with profiles
      final userIds = ordersJson.map((o) => o['user_id'] as String).toSet().toList();
      if (userIds.isNotEmpty) {
        final profilesResponse = await _client
            .from('user_profiles')
            .select()
            .inFilter('user_id', userIds);
        
        final profilesMap = {
          for (var p in profilesResponse as List) p['user_id'] as String: p
        };

        for (var order in ordersJson) {
          order['profiles'] = profilesMap[order['user_id']];
        }
      }

      final orders = ordersJson.map((json) => Order.fromJson(json)).toList();
      print('Admin: Parsed ${orders.length} orders successfully');
      return orders;
    } catch (e, stack) {
      print('Admin: Error fetching orders: $e');
      print('Admin: Stack trace: $stack');
      rethrow;
    }
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      print('Admin: Updating order $orderId status to $newStatus');
      await _client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      print('Admin: Order status updated successfully');
    } catch (e) {
      print('Admin: Error updating order status: $e');
      rethrow;
    }
  }

  Future<void> updateOrderItem({
    required String orderId,
    required String productId,
    required double packedQty,
  }) async {
    try {
      print('Admin: Updating order item - Order: $orderId, Product: $productId, Qty: $packedQty');
      await _client
          .from('order_items')
          .update({'packed_qty': packedQty})
          .eq('order_id', orderId)
          .eq('product_id', productId);
      print('Admin: Order item updated successfully');
    } catch (e) {
      print('Admin: Error updating order item: $e');
      rethrow;
    }
  }

  Future<void> updateFinalAmount(String orderId, double finalAmount, [double deliveryCost = 0]) async {
    try {
      print('Admin: Updating final amount for order $orderId to $finalAmount (Delivery: $deliveryCost)');
      await _client
          .from('orders')
          .update({
            'final_amount': finalAmount,
            'delivery_cost': deliveryCost,
          })
          .eq('id', orderId);
      print('Admin: Final amount updated successfully');
    } catch (e) {
      print('Admin: Error updating final amount: $e');
      rethrow;
    }
  }

  Future<void> updatePaymentStatus(String orderId, String paymentStatus) async {
    try {
      print('Admin: Updating payment status for order $orderId to $paymentStatus');
      await _client
          .from('orders')
          .update({'payment_status': paymentStatus})
          .eq('id', orderId);
      print('Admin: Payment status updated successfully');
    } catch (e) {
      print('Admin: Error updating payment status: $e');
      rethrow;
    }
  }

  Future<void> lockAllOrders() async {
    try {
      print('Admin: Locking all processing orders');
      await _client
          .from('orders')
          .update({'is_editable': false})
          .eq('status', 'processing');
      print('Admin: All orders locked successfully');
    } catch (e) {
      print('Admin: Error locking orders: $e');
      rethrow;
    }
  }

  Future<void> unlockAllOrders() async {
    try {
      print('Admin: Unlocking all processing orders');
      await _client
          .from('orders')
          .update({'is_editable': true})
          .eq('status', 'processing');
      print('Admin: All orders unlocked successfully');
    } catch (e) {
      print('Admin: Error unlocking orders: $e');
      rethrow;
    }
  }

  Future<bool> areOrdersLocked() async {
    try {
      final result = await _client
          .from('orders')
          .select('id')
          .eq('status', 'processing')
          .eq('is_editable', false)
          .limit(1);
      
      return (result as List).isNotEmpty;
    } catch (e) {
      print('Admin: Error checking lock status: $e');
      return false;
    }
  }

  /// Batch update packed quantities from an uploaded Excel sheet.
  /// 
  /// 1. Resolves product names → product IDs from the products table.
  /// 2. Updates packed_qty for each matching order_item.
  /// 3. Recalculates final_amount for each affected order.
  /// 4. Marks affected orders as 'packed'.
  Future<BatchUpdateResult> batchUpdatePackedQuantities(ImportResult importResult) async {
    try {
      print('Admin: Starting batch update for ${importResult.totalOrders} orders...');

      // 1. Build product name → ID mapping
      final productsResponse = await _client.from('products').select('id, name');
      final productNameToId = <String, String>{};
      for (var p in productsResponse as List) {
        productNameToId[p['name'] as String] = p['id'] as String;
      }

      int updatedItems = 0;
      int skippedItems = 0;
      final affectedOrderIds = <String>{};

      // 2. Update each packed_qty
      for (var update in importResult.updates) {
        final productId = productNameToId[update.productName];
        if (productId == null) {
          print('Admin: Skipping unknown product: ${update.productName}');
          skippedItems++;
          continue;
        }

        try {
          await _client
              .from('order_items')
              .update({'packed_qty': update.packedQty})
              .eq('order_id', update.orderId)
              .eq('product_id', productId);

          updatedItems++;
          affectedOrderIds.add(update.orderId);
        } catch (e) {
          print('Admin: Error updating item (order: ${update.orderId}, product: ${update.productName}): $e');
          skippedItems++;
        }
      }

      // 3. Recalculate final_amount for each affected order
      for (var orderId in affectedOrderIds) {
        try {
          // Fetch updated order items with product prices
          final items = await _client
              .from('order_items')
              .select('packed_qty, ordered_qty, price_at_order')
              .eq('order_id', orderId);

          double finalAmount = 0;
          for (var item in items as List) {
            final packedQty = (item['packed_qty'] as num?)?.toDouble();
            final orderedQty = (item['ordered_qty'] as num?)?.toDouble() ?? 0;
            final price = (item['price_at_order'] as num?)?.toDouble() ?? 0;
            finalAmount += (packedQty ?? orderedQty) * price;
          }

          await _client
              .from('orders')
              .update({
                'final_amount': finalAmount,
                'status': 'packed',
              })
              .eq('id', orderId);

          print('Admin: Order $orderId final_amount updated to $finalAmount, status → packed');
        } catch (e) {
          print('Admin: Error recalculating order $orderId: $e');
        }
      }

      print('Admin: Batch update complete. Updated: $updatedItems, Skipped: $skippedItems');

      return BatchUpdateResult(
        updatedItems: updatedItems,
        skippedItems: skippedItems,
        affectedOrders: affectedOrderIds.length,
      );
    } catch (e, stack) {
      print('Admin: Batch update failed: $e');
      print('Admin: Stack: $stack');
      rethrow;
    }
  }

  /// Fetches a user's default delivery cost from their profile using the order's user_id.
  Future<double> getUserDeliveryCost(String orderId) async {
    try {
      final orderResponse = await _client
          .from('orders')
          .select('user_id')
          .eq('id', orderId)
          .single();

      final userId = orderResponse['user_id'] as String;

      final profileResponse = await _client
          .from('user_profiles')
          .select('delivery_cost')
          .eq('user_id', userId)
          .maybeSingle();

      return (profileResponse?['delivery_cost'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('Admin: Could not fetch delivery cost: $e');
      return 0.0;
    }
  }

  /// Marks all currently packed orders as delivered in one batch (for Saturday delivery day).
  Future<int> markAllPackedAsDelivered() async {
    try {
      final packed = await _client
          .from('orders')
          .select('id')
          .eq('status', 'packed');

      final ids = (packed as List).map((o) => o['id'] as String).toList();
      if (ids.isEmpty) return 0;

      await _client
          .from('orders')
          .update({'status': 'delivered'})
          .eq('status', 'packed');

      print('Admin: Marked ${ids.length} orders as delivered');
      return ids.length;
    } catch (e) {
      print('Admin: Error marking as delivered: $e');
      rethrow;
    }
  }
}

class BatchUpdateResult {
  final int updatedItems;
  final int skippedItems;
  final int affectedOrders;

  BatchUpdateResult({
    required this.updatedItems,
    required this.skippedItems,
    required this.affectedOrders,
  });
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(Supabase.instance.client);
});

final allOrdersProvider = FutureProvider<List<Order>>((ref) async {
  return ref.watch(ordersRepositoryProvider).getAllOrders();
});
