import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/domain/order_model.dart';
import '../data/orders_repository.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final Order order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late Map<String, double> packedQuantities;

  @override
  void initState() {
    super.initState();
    packedQuantities = {
      for (var item in widget.order.items)
        item.productId: item.deliveredQuantity?.toDouble() ?? item.orderedQuantity.toDouble()
    };
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${order.id.substring(0, 8)}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _buildStatusChip(order.status),
                        const Spacer(),
                        const Text('Payment:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _buildPaymentChip(order.paymentStatus),
                      ],
                    ),
                    const Divider(height: 24),
                    Text('Created: ${DateFormat('MMM dd, yyyy • hh:mm a').format(order.createdAt)}'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Items Total:', style: TextStyle(fontSize: 15)),
                        Text('₹${(order.totalAmount - order.deliveryCost).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 15)),
                      ],
                    ),
                    if (order.deliveryCost > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivery Cost:', style: TextStyle(fontSize: 15, color: Colors.grey)),
                          Text('₹${order.deliveryCost.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 15, color: Colors.grey)),
                        ],
                      ),
                    ],
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('₹${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text('Order Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            ...order.items.map((item) => _buildItemCard(item)),

            const SizedBox(height: 24),

            // Mark as Packed (from processing)
            if (order.status == 'processing')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsPacked(context),
                  icon: const Icon(Icons.inventory_2),
                  label: const Text('Mark as Packed'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

            // Mark as Delivered (from packed)
            if (order.status == 'packed') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _updateStatus(context, 'delivered'),
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Mark as Delivered'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _updateStatus(context, 'processing'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Revert to Processing'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
            ],

            // Mark as Paid — cash customers only
            if (order.paymentStatus == 'pending' &&
                (order.status == 'packed' || order.status == 'delivered'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _markAsPaid(context),
                    icon: const Icon(Icons.payments),
                    label: const Text('Mark as Paid (Cash)'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final colors = {
      'processing': Colors.blue,
      'packed': Colors.green,
      'delivered': Colors.teal,
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPaymentChip(String status) {
    final color = status == 'paid' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildItemCard(item) {
    final orderedQty = item.orderedQuantity;
    final packedQty = packedQuantities[item.productId] ?? orderedQty.toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('₹${item.pricePerUnit} / ${item.unit}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Ordered: $orderedQty ${item.unit}', style: const TextStyle(fontSize: 12)),
                if (packedQty != orderedQty)
                  Text('Packed: $packedQty ${item.unit}',
                      style: const TextStyle(fontSize: 12, color: Colors.blue)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    try {
      await ref.read(ordersRepositoryProvider).updateOrderStatus(widget.order.id, newStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as $newStatus ✓')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _markAsPacked(BuildContext context) async {
    try {
      for (var item in widget.order.items) {
        await ref.read(ordersRepositoryProvider).updateOrderItem(
          orderId: widget.order.id,
          productId: item.productId,
          packedQty: packedQuantities[item.productId]!,
        );
      }

      double itemsTotal = 0;
      for (var item in widget.order.items) {
        itemsTotal += packedQuantities[item.productId]! * item.pricePerUnit;
      }

      // Fetch user's default delivery cost from their profile
      final deliveryCost =
          await ref.read(ordersRepositoryProvider).getUserDeliveryCost(widget.order.id);
      final finalAmount = itemsTotal + deliveryCost;

      await ref
          .read(ordersRepositoryProvider)
          .updateFinalAmount(widget.order.id, finalAmount, deliveryCost);
      await ref.read(ordersRepositoryProvider).updateOrderStatus(widget.order.id, 'packed');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Packed! Items ₹${itemsTotal.toStringAsFixed(0)} + Delivery ₹${deliveryCost.toStringAsFixed(0)} = ₹${finalAmount.toStringAsFixed(0)} ✓',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _markAsPaid(BuildContext context) async {
    try {
      await ref.read(ordersRepositoryProvider).updatePaymentStatus(widget.order.id, 'paid');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Marked as paid ✓')));
        setState(() {});
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
