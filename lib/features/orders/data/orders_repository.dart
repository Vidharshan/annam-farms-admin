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

      // Also update the customer's permanent delivery cost in their profile
      try {
        final orderResponse = await _client.from('orders').select('user_id').eq('id', orderId).single();
        final userId = orderResponse['user_id'];
        if (userId != null) {
          await _client.from('user_profiles').update({
            'delivery_cost': deliveryCost
          }).eq('user_id', userId);
        }
      } catch (e) {
        print('Admin: Error updating user profile delivery cost: $e');
      }

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

  /// Compares the uploaded Excel sheet against the database and returns a list of human-readable changes.
  Future<List<String>> generateImportDiff(ImportResult importResult, List<Order> currentOrders) async {
    final diffs = <String>[];
    if (importResult.updates.isEmpty) return diffs;

    // Build orderId -> customerName map from UI state to avoid Supabase join errors
    final orderCustomerMap = {
      for (var order in currentOrders) order.id: order.customerName
    };

    // 1. Build product name → ID mapping
    final productsResponse = await _client.from('products').select('id, name');
    final productNameToId = <String, String>{};
    for (var p in productsResponse as List) {
      productNameToId[p['name'] as String] = p['id'] as String;
    }

    // 2. Fetch all existing items for the affected orders
    final orderIds = importResult.updates.map((u) => u.orderId).toSet().toList();
    
    // Process in batches of 100 to avoid URL length limits
    final existingItems = <Map<String, dynamic>>[];
    for (var i = 0; i < orderIds.length; i += 100) {
      final batch = orderIds.skip(i).take(100).toList();
      final response = await _client
          .from('order_items')
          .select('order_id, product_id, ordered_qty, packed_qty')
          .inFilter('order_id', batch);
      existingItems.addAll(List<Map<String, dynamic>>.from(response as List));
    }

    // 3. Compare
    for (var update in importResult.updates) {
      final productId = productNameToId[update.productName];
      if (productId == null) continue;

      final existingItem = existingItems.where((item) => 
        item['order_id'] == update.orderId && item['product_id'] == productId
      ).firstOrNull;

      if (existingItem != null) {
        final currentQty = (existingItem['packed_qty'] as num?)?.toDouble() ?? 
                           (existingItem['ordered_qty'] as num).toDouble();
                           
        if (currentQty != update.packedQty) {
          final customerName = orderCustomerMap[update.orderId] ?? 'Order #${update.orderId.substring(0, 5)}';
          diffs.add('$customerName: ${update.productName} (${currentQty.toStringAsFixed(1)} → ${update.packedQty.toStringAsFixed(1)})');
        }
      } else if (update.packedQty > 0) {
        // NEW ITEM ADDED!
        final customerName = orderCustomerMap[update.orderId] ?? 'Order #${update.orderId.substring(0, 5)}';
        diffs.add('$customerName: ${update.productName} (0.0 → ${update.packedQty.toStringAsFixed(1)}) 🆕');
      }
    }

    return diffs;
  }

  /// Batch update packed quantities from an uploaded Excel sheet.
  /// 
  /// 1. Resolves product names → product IDs from the products table.
  /// 2. Updates packed_qty for each matching order_item, or INSERTS if new.
  /// 3. Recalculates final_amount for each affected order.
  /// 4. Marks affected orders as 'packed'.
  Future<BatchUpdateResult> batchUpdatePackedQuantities(ImportResult importResult) async {
    try {
      print('Admin: Starting batch update for ${importResult.totalOrders} orders...');

      // 1. Build product name → {id, price} mapping
      final productsResponse = await _client.from('products').select('id, name, price');
      final productInfo = <String, Map<String, dynamic>>{};
      for (var p in productsResponse as List) {
        productInfo[p['name'] as String] = p;
      }

      int updatedItems = 0;
      int skippedItems = 0;
      final affectedOrderIds = <String>{};

      // 2. Fetch all existing items for the affected orders to know whether to insert or update
      final orderIds = importResult.updates.map((u) => u.orderId).toSet().toList();
      final existingItems = <Map<String, dynamic>>[];
      for (var i = 0; i < orderIds.length; i += 100) {
        final batch = orderIds.skip(i).take(100).toList();
        final response = await _client
            .from('order_items')
            .select('order_id, product_id, ordered_qty, packed_qty')
            .inFilter('order_id', batch);
        existingItems.addAll(List<Map<String, dynamic>>.from(response as List));
      }

      // 3. Update or Insert each packed_qty
      for (var update in importResult.updates) {
        final product = productInfo[update.productName];
        if (product == null) {
          print('Admin: Skipping unknown product: ${update.productName}');
          skippedItems++;
          continue;
        }
        
        final productId = product['id'] as String;
        final existingItem = existingItems.where((item) => 
          item['order_id'] == update.orderId && item['product_id'] == productId
        ).firstOrNull;

        try {
          if (existingItem != null) {
            final currentQty = (existingItem['packed_qty'] as num?)?.toDouble() ?? 
                               (existingItem['ordered_qty'] as num).toDouble();
            
            // Only update if there is an actual change
            if (currentQty != update.packedQty) {
              await _client
                  .from('order_items')
                  .update({'packed_qty': update.packedQty})
                  .eq('order_id', update.orderId)
                  .eq('product_id', productId);
              updatedItems++;
              affectedOrderIds.add(update.orderId);
            } else {
              skippedItems++; // Same value, skip DB call
            }
          } else if (update.packedQty > 0) {
            // Item wasn't ordered, but admin packed it anyway!
            await _client.from('order_items').insert({
              'order_id': update.orderId,
              'product_id': productId,
              'packed_qty': update.packedQty,
              'ordered_qty': 0.0,
              'price_at_order': product['price'],
            });
            updatedItems++;
            affectedOrderIds.add(update.orderId);
          } else {
            // Didn't exist, and packed qty is 0. Ignore.
            skippedItems++;
          }
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

          // Fetch and add the user's default delivery cost
          final deliveryCost = await getUserDeliveryCost(orderId);
          finalAmount += deliveryCost;

          await _client
              .from('orders')
              .update({
                'final_amount': finalAmount,
                'delivery_cost': deliveryCost,
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
