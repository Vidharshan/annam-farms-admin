import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../orders/data/orders_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../../main.dart';

class _BuyingPricesNotifier extends Notifier<Map<String, double>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Map<String, double> build() {
    final Map<String, double> prices = {};
    try {
      final keys = _prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith('buying_price:')) {
          final val = _prefs.getDouble(key);
          if (val != null) {
            final cleanKey = key.replaceFirst('buying_price:', '');
            prices[cleanKey] = val;
          }
        }
      }
    } catch (e) {
      print('Error loading buying prices: $e');
    }
    return prices;
  }

  void updatePrice(String weekKey, String productId, double price) {
    try {
      final storageKey = 'buying_price:$weekKey:$productId';
      _prefs.setDouble(storageKey, price);
    } catch (e) {
      print('Error saving buying price: $e');
    }
    state = {...state, "$weekKey:$productId": price};
  }
}
final buyingPricesProvider = NotifierProvider<_BuyingPricesNotifier, Map<String, double>>(() => _BuyingPricesNotifier());

class _SourcesNotifier extends Notifier<Map<String, String>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Map<String, String> build() {
    final Map<String, String> sources = {};
    try {
      final keys = _prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith('source:')) {
          final val = _prefs.getString(key);
          if (val != null) {
            final cleanKey = key.replaceFirst('source:', '');
            sources[cleanKey] = val;
          }
        }
      }
    } catch (e) {
      print('Error loading sources: $e');
    }
    return sources;
  }

  void updateSource(String weekKey, String productId, String source) {
    try {
      final storageKey = 'source:$weekKey:$productId';
      _prefs.setString(storageKey, source);
    } catch (e) {
      print('Error saving source: $e');
    }
    state = {...state, "$weekKey:$productId": source};
  }
}
final sourcesProvider = NotifierProvider<_SourcesNotifier, Map<String, String>>(() => _SourcesNotifier());

class _SelectedWeekNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void setWeek(DateTime? week) => state = week;
}
final selectedWeekProvider = NotifierProvider<_SelectedWeekNotifier, DateTime?>(() => _SelectedWeekNotifier());

class ProfitReportsScreen extends ConsumerStatefulWidget {
  const ProfitReportsScreen({super.key});

  @override
  ConsumerState<ProfitReportsScreen> createState() => _ProfitReportsScreenState();
}

class _ProfitReportsScreenState extends ConsumerState<ProfitReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Reports & Analytics'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Weekly Profit Calculator'),
            Tab(text: 'Suggested Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WeeklyProfitCalculator(),
          _SuggestedReports(),
        ],
      ),
    );
  }
}

DateTime getStartOfWeek(DateTime date) {
  final localDate = date.toLocal();
  final normalized = DateTime(localDate.year, localDate.month, localDate.day);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

class _WeeklyProfitCalculator extends ConsumerWidget {
  const _WeeklyProfitCalculator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(allOrdersProvider);
    final productsAsync = ref.watch(productsProvider);
    final buyingPrices = ref.watch(buyingPricesProvider);
    final sources = ref.watch(sourcesProvider);

    return ordersAsync.when(
      data: (orders) {
        return productsAsync.when(
          data: (products) {
            // Group orders by week
            final weeksWithOrders = <DateTime>{};
            for (var order in orders) {
              if (order.status != 'cancelled') {
                weeksWithOrders.add(getStartOfWeek(order.createdAt));
              }
            }
            // Always ensure the current week is in the list
            weeksWithOrders.add(getStartOfWeek(DateTime.now()));

            final sortedWeeks = weeksWithOrders.toList()
              ..sort((a, b) => b.compareTo(a));

            final selectedWeek = ref.watch(selectedWeekProvider) ?? sortedWeeks.first;
            final weekKey = DateFormat('yyyy-MM-dd').format(selectedWeek);

            final startOfWeek = selectedWeek;
            final endOfWeek = startOfWeek.add(const Duration(days: 7));

            final currentWeekOrders = orders.where((o) {
              final isAfterOrEqual = o.createdAt.isAfter(startOfWeek) || o.createdAt.isAtSameMomentAs(startOfWeek);
              final isBefore = o.createdAt.isBefore(endOfWeek);
              return isAfterOrEqual && isBefore && o.status != 'cancelled';
            }).toList();

            // Calculate quantities sold
            final quantitiesSold = <String, double>{};
            for (var order in currentWeekOrders) {
              for (var item in order.items) {
                final qty = (item.deliveredQuantity != null && item.deliveredQuantity! > 0) ? item.deliveredQuantity! : item.orderedQuantity;
                quantitiesSold[item.productId] = (quantitiesSold[item.productId] ?? 0) + qty;
              }
            }

            // Calculate profit per source
            final profitBySource = <String, double>{};
            double totalProfit = 0;
            double totalRevenue = 0;
            double totalCost = 0;

            for (var product in products) {
              final qty = quantitiesSold[product.id] ?? 0;
              if (qty > 0) {
                final buyingPrice = buyingPrices["$weekKey:${product.id}"] ?? 0.0;
                final source = sources["$weekKey:${product.id}"] ?? 'Unknown / Not Set';
                
                final revenue = product.price * qty;
                final cost = buyingPrice * qty;
                final profit = revenue - cost;

                totalRevenue += revenue;
                totalCost += cost;
                totalProfit += profit;

                profitBySource[source] = (profitBySource[source] ?? 0) + profit;
              }
            }

            final displayEndOfWeek = endOfWeek.subtract(const Duration(seconds: 1));

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Week Selection Dropdown
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.green),
                          const SizedBox(width: 12),
                          const Text('Select Week: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<DateTime>(
                              initialValue: selectedWeek,
                              items: sortedWeeks.map((week) {
                                final end = week.add(const Duration(days: 6));
                                final label = '${DateFormat('MMM dd, yyyy').format(week)} - ${DateFormat('MMM dd, yyyy').format(end)}';
                                return DropdownMenuItem<DateTime>(
                                  value: week,
                                  child: Text(label),
                                );
                              }).toList(),
                              onChanged: (val) {
                                ref.read(selectedWeekProvider.notifier).setWeek(val);
                              },
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Week: ${DateFormat('MMM dd, yyyy').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(displayEndOfWeek)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SummaryCard('Revenue', totalRevenue, Colors.blue),
                      _SummaryCard('Cost', totalCost, Colors.red),
                      _SummaryCard('Profit', totalProfit, totalProfit >= 0 ? Colors.green : Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Profit by Source (Party)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (profitBySource.isEmpty)
                    const Text('No sales this week or sources not set.')
                  else
                    ...profitBySource.entries.map((e) => ListTile(
                      title: Text(e.key),
                      trailing: Text('₹${e.value.toStringAsFixed(2)}', 
                        style: TextStyle(
                          color: e.value >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )
                      ),
                    )),
                  const SizedBox(height: 24),
                  const Text('Enter Buying Prices & Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final soldQty = quantitiesSold[product.id] ?? 0;
                      if (soldQty == 0) return const SizedBox.shrink();

                      return Card(
                        key: ValueKey('$weekKey:${product.id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('${product.name} (Sold: $soldQty ${product.unit})'),
                              ),
                              Expanded(
                                child: TextFormField(
                                  initialValue: buyingPrices["$weekKey:${product.id}"]?.toString() ?? '',
                                  decoration: const InputDecoration(labelText: 'Buying Price (₹)'),
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) {
                                    final parsed = double.tryParse(val) ?? 0.0;
                                    ref.read(buyingPricesProvider.notifier).updatePrice(weekKey, product.id, parsed);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: sources["$weekKey:${product.id}"] ?? '',
                                  decoration: const InputDecoration(labelText: 'Source/Party'),
                                  onChanged: (val) {
                                    ref.read(sourcesProvider.notifier).updateSource(weekKey, product.id, val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading products: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading orders: $e')),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;

  const _SummaryCard(this.title, this.amount, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.28,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedReports extends ConsumerWidget {
  const _SuggestedReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(allOrdersProvider);
    final productsAsync = ref.watch(productsProvider);

    return ordersAsync.when(
      data: (orders) {
        return productsAsync.when(
          data: (products) {
            final now = DateTime.now();

            // 1. Payment Collection Status
            final unpaidDelivered = orders.where((o) => o.status == 'delivered' && o.paymentStatus != 'paid').toList();
            double totalUnpaid = 0;
            int unpaid0to7 = 0;
            int unpaid7Plus = 0;
            for (var o in unpaidDelivered) {
              totalUnpaid += o.totalAmount;
              if (now.difference(o.createdAt).inDays <= 7) {
                unpaid0to7++;
              } else {
                unpaid7Plus++;
              }
            }

            // 2. Customer Churn (Last 30 days vs 30-60 days ago)
            final last30Days = now.subtract(const Duration(days: 30));
            final last60Days = now.subtract(const Duration(days: 60));
            
            final recentUsers = orders.where((o) => o.createdAt.isAfter(last30Days)).map((o) => o.userId).toSet();
            final olderUsers = orders.where((o) => o.createdAt.isAfter(last60Days) && o.createdAt.isBefore(last30Days)).map((o) => o.userId).toSet();
            
            int churnedCount = 0;
            for (var u in olderUsers) {
              if (!recentUsers.contains(u)) churnedCount++;
            }

            // 3. Veg Demand (Top & Bottom by quantity over last 30 days)
            final recentOrders = orders.where((o) => o.createdAt.isAfter(last30Days) && o.status != 'cancelled').toList();
            final qtySold = <String, double>{};
            for (var o in recentOrders) {
              for (var item in o.items) {
                qtySold[item.productId] = (qtySold[item.productId] ?? 0) + ((item.deliveredQuantity != null && item.deliveredQuantity! > 0) ? item.deliveredQuantity! : item.orderedQuantity);
              }
            }

            final demandList = products.map((p) {
              return MapEntry(p.name, qtySold[p.id] ?? 0.0);
            }).toList();
            
            demandList.sort((a, b) => b.value.compareTo(a.value)); // Descending
            
            final topVeg = demandList.take(3).map((e) => '${e.key} (${e.value} sold)').join(', ');
            final bottomVeg = demandList.reversed.take(3).where((e) => e.value > 0).map((e) => '${e.key} (${e.value} sold)').join(', ');


            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Calculated Reports & Analytics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _ReportCard(
                  title: 'Vegetables in Demand (Last 30 Days)',
                  value: 'Top: ${topVeg.isEmpty ? 'N/A' : topVeg}\nBottom: ${bottomVeg.isEmpty ? 'N/A' : bottomVeg}',
                  description: 'Based on total quantity sold recently.',
                  icon: Icons.trending_up,
                ),
                _ReportCard(
                  title: 'Payment Collection Status',
                  value: '₹${totalUnpaid.toStringAsFixed(2)} Unpaid',
                  description: '$unpaid0to7 orders (0-7 days old)\n$unpaid7Plus orders (7+ days old)',
                  icon: Icons.account_balance_wallet,
                  valueColor: totalUnpaid > 0 ? Colors.red : Colors.green,
                ),
                _ReportCard(
                  title: 'Customer Churn Risk',
                  value: '$churnedCount customers',
                  description: 'Ordered 30-60 days ago, but haven\'t ordered in the last 30 days. Consider sending them a reminder.',
                  icon: Icons.people_outline,
                ),
                const Divider(height: 32),
                const Text('Pending Implementation (Needs Input)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                const SizedBox(height: 16),
                _ReportSuggestion(
                  title: 'Wastage & Spoilage Report',
                  description: 'Needs input: We need a way to input the EXACT quantity bought from parties to compare against the quantity sold. Should I add a "Qty Bought" field to the Weekly Profit Calculator?',
                  icon: Icons.delete_sweep,
                ),
                _ReportSuggestion(
                  title: 'Delivery Route Efficiency',
                  description: 'Needs input: We need geographical grouping (Area/Pincode) and actual delivery expenses (Fuel/Driver cost) recorded somewhere to calculate this. How do you want to track fuel costs?',
                  icon: Icons.local_shipping,
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading products: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading orders: $e')),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final String description;
  final IconData icon;
  final Color? valueColor;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.description,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor ?? Colors.green)),
                  const SizedBox(height: 8),
                  Text(description, style: TextStyle(color: Colors.grey[400])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSuggestion extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _ReportSuggestion({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: Colors.orange),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 8),
                  Text(description, style: TextStyle(color: Colors.grey[300])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
