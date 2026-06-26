import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/stats_repository.dart';
import '../../orders/data/orders_repository.dart';
import '../../../shared/services/excel_export_service.dart';
import '../../../main.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final ordersAsync = ref.watch(allOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Delivery Sheet',
            onPressed: () async {
              final orders = ordersAsync.value;
              if (orders == null || orders.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No orders to export')),
                );
                return;
              }
              
              // Only export processing/packed orders from the last 7 days (this week's orders)
              final weekAgo = DateTime.now().subtract(const Duration(days: 7));
              final toExport = orders.where((o) => 
                o.createdAt.isAfter(weekAgo) && 
                (o.status == 'processing' || o.status == 'packed')
              ).toList();
              
              if (toExport.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No active orders to export')),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generating Excel sheet...')),
              );
              
              await ExcelExportService.exportPackingSheet(toExport);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(dashboardStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Key Metrics Row
              const Text(
                'Weekly Overview',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Processing',
                      stats.pendingOrders.toString(),
                      Icons.pending_actions,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      'Packed Orders',
                      stats.packedOrders.toString(),
                      Icons.local_shipping,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMetricCard(
                'Total Unpaid Dues',
                '₹${stats.unpaidRevenue.toStringAsFixed(0)}',
                Icons.error_outline,
                Colors.red,
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Current Batch Ordered Quantities',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (stats.productWeights.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy for WhatsApp',
                      onPressed: () {
                        final buffer = StringBuffer();
                        buffer.writeln('*Current Batch Ordered Quantities*');
                        buffer.writeln('');
                        for (var e in stats.productWeights.entries) {
                          buffer.writeln('• ${e.key}: ${e.value.toStringAsFixed(1)}');
                        }
                        Clipboard.setData(ClipboardData(text: buffer.toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard for WhatsApp!')),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (stats.productWeights.isEmpty)
                const Center(child: Text('No data recorded yet'))
              else
                Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.blue.withOpacity(0.1)),
                      columns: const [
                        DataColumn(label: Expanded(child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold)))),
                        DataColumn(label: Text('Ordered Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: stats.productWeights.entries.map((e) => DataRow(
                        cells: [
                          DataCell(Text(e.key)),
                          DataCell(Text(e.value.toStringAsFixed(1), style: TextStyle(color: Colors.blue[300], fontWeight: FontWeight.bold))),
                        ],
                      )).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: 32),
              
              // Low Stock Section
              const Text(
                'Low Stock Alerts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              if (stats.lowStockProducts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text('Inventory looks good!', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stats.lowStockProducts.length,
                  itemBuilder: (context, index) {
                    final product = stats.lowStockProducts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withOpacity(0.2),
                          child: const Icon(Icons.warning, color: Colors.red, size: 20),
                        ),
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text(
                          '${product.currentStock} ${product.unit}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
