import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/orders_repository.dart';
import '../../../shared/domain/order_model.dart';
import 'order_detail_screen.dart';
import '../../../main.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(allOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Orders'),
        actions: [
          // Lock/Unlock button
          Consumer(
            builder: (context, ref, child) {
              return FutureBuilder<bool>(
                future: ref.read(ordersRepositoryProvider).areOrdersLocked(),
                builder: (context, snapshot) {
                  final isLocked = snapshot.data ?? false;
                  return ElevatedButton.icon(
                    onPressed: () => _toggleLock(context, ref, isLocked),
                    icon: Icon(isLocked ? Icons.lock : Icons.lock_open),
                    label: Text(isLocked ? 'Unlock Orders' : 'Lock Orders'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: isLocked ? Colors.orange : Colors.green,
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allOrdersProvider),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet'));
          }

          // Group orders by status
          final processing = orders.where((o) => o.status == 'processing').toList();
          final packed = orders.where((o) => o.status == 'packed').toList();
          final delivered = orders.where((o) => o.status == 'delivered').toList();

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusSection(context, ref, 'Processing', processing, Colors.blue),
                  const SizedBox(height: 24),
                  // Packed section with Saturday batch-deliver button
                  _buildStatusSection(context, ref, 'Packed', packed, Colors.green,
                      batchAction: packed.isEmpty
                          ? null
                          : () => _markAllDelivered(context, ref, packed.length)),
                  const SizedBox(height: 24),
                  _buildStatusSection(context, ref, 'Delivered', delivered, Colors.teal),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildStatusSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<Order> orders,
    Color color, {
    VoidCallback? batchAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 24, color: color),
            const SizedBox(width: 8),
            Text(
              '$title (${orders.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (batchAction != null)
              TextButton.icon(
                onPressed: batchAction,
                icon: const Icon(Icons.local_shipping, size: 16),
                label: const Text('Mark All Delivered'),
                style: TextButton.styleFrom(foregroundColor: Colors.blue),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No $title orders', style: TextStyle(color: Colors.grey[600])),
          )
        else
          ...orders.map((order) => _buildOrderCard(context, ref, order, color)),
      ],
    );
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, Order order, Color statusColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(order: order),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.customerName ?? 'Order #${order.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      order.status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('MMM dd, yyyy • hh:mm a').format(order.createdAt),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text('${order.items.length} items', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.currency_rupee, size: 16, color: Colors.grey[600]),
                      Text('₹${order.totalAmount.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: order.paymentStatus == 'paid' ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.paymentStatus.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (order.status == 'packed') ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showDeliveryCostDialog(context, ref, order),
                    icon: const Icon(Icons.local_shipping, size: 16),
                    label: Text(
                      order.deliveryCost > 0 
                          ? 'Delivery: ₹${order.deliveryCost.toStringAsFixed(2)}' 
                          : 'Add Delivery Cost'
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeliveryCostDialog(BuildContext context, WidgetRef ref, Order order) async {
    final controller = TextEditingController(text: order.deliveryCost > 0 ? order.deliveryCost.toString() : '');
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Delivery Cost'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (₹)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(controller.text) ?? 0;
              
              // Calculate new final amount: (Current Total - Old Delivery Cost) + New Delivery Cost
              // OR simpler: Recalculate from items.
              // Since we don't have items map here easily, and Order model has totalAmount (which implies final_amount from DB),
              // We assume totalAmount = itemsTotal + deliveryCost.
              // So itemsTotal = totalAmount - order.deliveryCost.
              
              final itemsTotal = order.totalAmount - order.deliveryCost;
              final newFinalAmount = itemsTotal + cost;

              try {
                await ref.read(ordersRepositoryProvider).updateFinalAmount(order.id, newFinalAmount, cost);
                ref.invalidate(allOrdersProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                 if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                 }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static Future<void> _markAllDelivered(BuildContext context, WidgetRef ref, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All as Delivered?'),
        content: Text('This will mark all $count packed orders as delivered and notify users that payment is due.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Mark All Delivered'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = await ref.read(ordersRepositoryProvider).markAllPackedAsDelivered();
      ref.invalidate(allOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$updated orders marked as delivered ✓'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static Future<void> _toggleLock(BuildContext context, WidgetRef ref, bool currentlyLocked) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentlyLocked ? 'Unlock Orders?' : 'Lock Orders?'),
        content: Text(
          currentlyLocked
              ? 'This will allow customers to edit their orders and place new orders.'
              : 'This will prevent customers from editing orders or placing new orders. Use this when you are ready to start packing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(currentlyLocked ? 'Unlock' : 'Lock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (currentlyLocked) {
        await ref.read(ordersRepositoryProvider).unlockAllOrders();
      } else {
        await ref.read(ordersRepositoryProvider).lockAllOrders();
      }

      ref.invalidate(allOrdersProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyLocked ? 'Orders unlocked successfully!' : 'Orders locked successfully!'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
