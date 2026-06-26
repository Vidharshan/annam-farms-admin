import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/admin_theme.dart';
import 'core/constants/app_secrets.dart';
import 'features/inventory/presentation/products_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';

import 'features/orders/presentation/orders_screen.dart';
import 'features/orders/presentation/packing_screen.dart';
import 'features/users/presentation/users_screen.dart';

/// Global key so child screens can open the drawer from their own AppBars
final GlobalKey<ScaffoldState> adminScaffoldKey = GlobalKey<ScaffoldState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: AppSecrets.supabaseUrl,
    anonKey: AppSecrets.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Annam Farms Admin',
      theme: AdminTheme.darkTheme,
      home: const AdminDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ProductsScreen(),
    const OrdersScreen(),
    const PackingScreen(),
    const UsersScreen(),
    const Center(child: Text('Subscriptions - Coming Soon')),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard'),
    _NavItem(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventory'),
    _NavItem(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Orders'),
    _NavItem(icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, label: 'Packing'),
    _NavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Customers'),
    _NavItem(icon: Icons.repeat_outlined, selectedIcon: Icons.repeat, label: 'Subscriptions'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: adminScaffoldKey,
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.eco, color: Colors.green, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Annam Farms',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Admin Panel',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _navItems.length,
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final isSelected = _selectedIndex == index;
                  return ListTile(
                    leading: Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      color: isSelected ? Colors.green : null,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.green : null,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: Colors.green.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      Navigator.pop(context); // Close drawer
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
