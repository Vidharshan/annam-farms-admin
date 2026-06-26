import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/domain/product_model.dart';
import '../../inventory/data/inventory_repository.dart';

class DashboardStats {
  final int pendingOrders;
  final int packedOrders;
  final Map<String, double> productWeights; // product name -> total ordered qty
  final double unpaidRevenue;
  final List<ProductModel> lowStockProducts;

  DashboardStats({
    required this.pendingOrders,
    required this.packedOrders,
    required this.productWeights,
    required this.unpaidRevenue,
    required this.lowStockProducts,
  });
}

class StatsRepository {
  final SupabaseClient _client;
  final InventoryRepository _inventoryRepo;

  StatsRepository(this._client, this._inventoryRepo);

  Future<DashboardStats> getStats() async {
    // 2. Get Pending/Packed Counts
    final pendingCount = await _client
        .from('orders')
        .count()
        .eq('status', 'processing');
    
    final packedCount = await _client
        .from('orders')
        .count()
        .eq('status', 'packed');

    // 3. Get Low Stock Products
    final allProducts = await _inventoryRepo.getAllProducts();
    final lowStock = allProducts.where((p) => p.currentStock <= 0 && p.isActive).toList();

    // 5. Get Product-wise total ordered weights for current batch
    // We only care about active orders (processing or packed) for the upcoming Saturday delivery
    final activeOrdersResponse = await _client
        .from('orders')
        .select('id')
        .inFilter('status', ['processing', 'packed']);
        
    final activeOrderIds = (activeOrdersResponse as List).map((o) => o['id']).toList();

    final productWeights = <String, double>{};
    if (activeOrderIds.isNotEmpty) {
      final itemResponse = await _client
          .from('order_items')
          .select('ordered_qty, products(name)')
          .inFilter('order_id', activeOrderIds)
          .not('ordered_qty', 'is', null);
      
      for (var item in itemResponse as List) {
        final name = item['products']['name'] as String;
        final qty = (item['ordered_qty'] as num).toDouble();
        productWeights[name] = (productWeights[name] ?? 0) + qty;
      }
    }

    // 6. Unpaid Revenue (All active unpaid)
    // We fetch all orders that are unpaid or pending payment to track dues
    final revenueResponse = await _client
        .from('orders')
        .select('final_amount, total_estimated_amount, payment_status')
        .inFilter('payment_status', ['pending', 'unpaid'])
        .not('status', 'eq', 'cancelled');
    
    double unpaidTotal = 0;
    
    for (var order in revenueResponse as List) {
      final amount = (order['final_amount'] ?? order['total_estimated_amount'] as num?)?.toDouble() ?? 0.0;
      unpaidTotal += amount;
    }

    return DashboardStats(
      pendingOrders: pendingCount,
      packedOrders: packedCount,
      productWeights: productWeights,
      unpaidRevenue: unpaidTotal,
      lowStockProducts: lowStock,
    );
  }
}

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final inventoryRepo = ref.watch(inventoryRepositoryProvider);
  return StatsRepository(Supabase.instance.client, inventoryRepo);
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  return ref.watch(statsRepositoryProvider).getStats();
});
