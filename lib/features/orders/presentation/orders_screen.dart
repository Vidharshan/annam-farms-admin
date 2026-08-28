import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/orders_repository.dart';
import '../../../shared/domain/order_model.dart';
import 'order_detail_screen.dart';
import '../../../main.dart';

class _ShowArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool val) => state = val;
}
final _showArchivedProvider = NotifierProvider<_ShowArchivedNotifier, bool>(() => _ShowArchivedNotifier());

class _SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String val) => state = val;
}
final _searchQueryProvider = NotifierProvider<_SearchQueryNotifier, String>(() => _SearchQueryNotifier());

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(allOrdersProvider);
    final showArchived = ref.watch(_showArchivedProvider);
    final searchQuery = ref.watch(_searchQueryProvider).toLowerCase();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allOrdersProvider),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet'));
          }

          // Filter by archive status and search query
          final filteredOrders = orders.where((o) {
            if (o.isArchived != showArchived) return false;
            if (searchQuery.isNotEmpty) {
              final name = (o.customerName ?? '').toLowerCase();
              final phone = (o.customerPhone ?? '').toLowerCase();
              if (!name.contains(searchQuery) && !phone.contains(searchQuery)) return false;
            }
            return true;
          }).toList();

          // Sort so unpaid orders show up first, then by creation date descending
          filteredOrders.sort((a, b) {
            if (a.paymentStatus != 'paid' && b.paymentStatus == 'paid') return -1;
            if (a.paymentStatus == 'paid' && b.paymentStatus != 'paid') return 1;
            return b.createdAt.compareTo(a.createdAt);
          });

          if (filteredOrders.isEmpty) {
             return Column(
               children: [
                 _buildSearchBar(ref),
                 const SizedBox(height: 32),
                 Center(child: Text(showArchived ? 'No archived orders matching criteria' : 'No active orders matching criteria')),
               ],
             );
          }

          // Group orders by status
          final processing = filteredOrders.where((o) => o.status == 'processing').toList();
          final packed = filteredOrders.where((o) => o.status == 'packed').toList();
          final delivered = filteredOrders.where((o) => o.status == 'delivered').toList();
          final cancelled = filteredOrders.where((o) => o.status == 'cancelled').toList();

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(ref),
                  const SizedBox(height: 24),
                  _buildStatusSection(context, ref, 'Processing', processing, Colors.blue, showArchived: showArchived),
                  const SizedBox(height: 24),
                  // Packed section with Saturday batch-deliver button
                  _buildStatusSection(context, ref, 'Packed', packed, Colors.green,
                      batchAction: packed.isEmpty || showArchived
                          ? null
                          : () => _markAllDelivered(context, ref, packed.length), showArchived: showArchived),
                  const SizedBox(height: 24),
                  _buildStatusSection(context, ref, 'Delivered', delivered, Colors.teal,
                      batchAction: delivered.isEmpty || showArchived
                          ? null
                          : () => _archiveDelivered(context, ref, delivered.length), showArchived: showArchived, batchActionLabel: 'Archive All'),
                  const SizedBox(height: 24),
                  if (cancelled.isNotEmpty)
                    _buildStatusSection(context, ref, 'Cancelled', cancelled, Colors.red, showArchived: showArchived),
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
    bool showArchived = false,
    String batchActionLabel = 'Mark All Delivered',
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
                icon: Icon(batchActionLabel == 'Archive All' ? Icons.archive : Icons.local_shipping, size: 16),
                label: Text(batchActionLabel),
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
          ...orders.map((order) => _buildOrderCard(context, ref, order, color, showArchived: showArchived)),
      ],
    );
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, Order order, Color statusColor, {bool showArchived = false}) {
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName ?? 'Order #${order.id.substring(0, 8)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                          Text(
                            order.customerPhone!,
                            style: TextStyle(color: Colors.grey[700], fontSize: 12),
                          ),
                      ],
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
              if (order.status == 'delivered') ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showReminderOptions(context, ref, order),
                        icon: const Icon(Icons.notifications_active, size: 16),
                        label: const Text('Send Reminder'),
                        style: TextButton.styleFrom(foregroundColor: Colors.blue),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await ref.read(ordersRepositoryProvider).updateOrderStatus(order.id, 'processing');
                            ref.invalidate(allOrdersProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order reverted to processing')));
                            }
                          } catch (e) {
                             if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                             }
                          }
                        },
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Revert to Processing'),
                        style: TextButton.styleFrom(foregroundColor: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _deleteOrder(context, ref, order),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  if (showArchived)
                    TextButton.icon(
                      onPressed: () async {
                         try {
                           await ref.read(ordersRepositoryProvider).unarchiveOrder(order.id);
                           ref.invalidate(allOrdersProvider);
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order unarchived!')));
                           }
                         } catch (e) {
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                           }
                         }
                      },
                      icon: const Icon(Icons.unarchive, size: 16),
                      label: const Text('Unarchive Order'),
                    ),
                ],
              ),
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

  static Future<void> _archiveDelivered(BuildContext context, WidgetRef ref, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Delivered Orders?'),
        content: Text('This will move $count delivered (and cancelled) orders to the archive to clean up your active view. This is fully reversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Archive All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = await ref.read(ordersRepositoryProvider).archiveDeliveredOrders();
      ref.invalidate(allOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$updated orders archived ✓'), backgroundColor: Colors.teal),
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

  Widget _buildSearchBar(WidgetRef ref) {
    final showArchived = ref.watch(_showArchivedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search Orders (Name or Phone)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => ref.read(_searchQueryProvider.notifier).set(val),
              ),
            ),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('Active'),
              selected: !showArchived,
              onSelected: (_) => ref.read(_showArchivedProvider.notifier).set(false),
              selectedColor: Colors.blue.withOpacity(0.3),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Archived'),
              selected: showArchived,
              onSelected: (_) => ref.read(_showArchivedProvider.notifier).set(true),
              selectedColor: Colors.blue.withOpacity(0.3),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, child) {
            return FutureBuilder<bool>(
              future: ref.read(ordersRepositoryProvider).areOrdersLocked(),
              builder: (context, snapshot) {
                final isLocked = snapshot.data ?? false;
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleLock(context, ref, isLocked),
                    icon: Icon(isLocked ? Icons.lock : Icons.lock_open),
                    label: Text(isLocked ? 'Unlock Orders' : 'Lock Orders'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: isLocked ? Colors.orange : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteOrder(BuildContext context, WidgetRef ref, Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order?'),
        content: const Text('Are you sure you want to completely delete this order? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(ordersRepositoryProvider).deleteOrder(order.id);
      ref.invalidate(allOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order deleted successfully'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting order: $e')));
      }
    }
  }

  Future<void> _showReminderOptions(BuildContext context, WidgetRef ref, Order order) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              const ListTile(
                title: Text(
                  'Select Reminder Channel',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active, color: Colors.blue),
                title: const Text('Send Push Notification'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await Supabase.instance.client.functions.invoke(
                      'send-payment-reminder',
                      body: {'order_id': order.id, 'user_id': order.userId},
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment reminder push notification sent!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to send notification: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('Send WhatsApp Message'),
                onTap: () async {
                  Navigator.pop(ctx);
                  
                  // 1. Format Phone Number
                  String phone = order.customerPhone ?? '';
                  phone = phone.replaceAll(RegExp(r'\D'), '');
                  if (phone.length == 10) {
                    phone = '91$phone';
                  }

                  if (phone.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Customer phone number is missing!')),
                      );
                    }
                    return;
                  }

                  // 2. Prepare Payment Link
                  final paymentUrl = 'https://kptnngwdknzifnzduckd.supabase.co/functions/v1/pay?orderId=${order.id}';
                  
                  // 3. Prepare Message Text
                  final customerName = order.customerName ?? 'Customer';
                  final amountStr = order.totalAmount.toStringAsFixed(2);
                  final message = 'Hello $customerName, your order has been successfully packed! Your total pending bill is ₹$amountStr. Please complete your payment here: $paymentUrl';
                  
                  // 4. Launch WhatsApp URL
                  final whatsappUrl = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
                  try {
                    if (await canLaunchUrl(whatsappUrl)) {
                      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not launch WhatsApp.')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error launching WhatsApp: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
