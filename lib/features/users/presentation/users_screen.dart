import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/profiles_repository.dart';
import '../../../shared/domain/profile_model.dart';
import '../../../main.dart';
class _CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String val) => state = val;
}
final _customerSearchProvider = NotifierProvider<_CustomerSearchNotifier, String>(() => _CustomerSearchNotifier());

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(allProfilesProvider);
    final searchQuery = ref.watch(_customerSearchProvider).toLowerCase();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Manage Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allProfilesProvider),
          ),
        ],
      ),
      body: profilesAsync.when(
        data: (profiles) {
          final filteredProfiles = profiles.where((p) {
            if (searchQuery.isEmpty) return true;
            final name = (p.fullName ?? '').toLowerCase();
            final phone = (p.phone ?? '').toLowerCase();
            return name.contains(searchQuery) || phone.contains(searchQuery);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search Customers (Name or Phone)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => ref.read(_customerSearchProvider.notifier).set(val),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredProfiles.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final profile = filteredProfiles[index];
            return ListTile(
              leading: CircleAvatar(
                child: Text(profile.fullName?.isNotEmpty == true ? profile.fullName![0] : '?'),
              ),
              title: Text(profile.fullName ?? 'Unknown'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile.phone != null) Text(profile.phone!),
                  if (profile.area != null) Text(profile.area!, style: const TextStyle(fontSize: 12)),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Route No
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Route', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(
                        profile.routeNo != null ? '#${profile.routeNo}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: profile.routeNo != null ? Colors.blue : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Delivery Cost
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Delivery', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(
                        '₹${profile.defaultDeliveryCost.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
                onTap: () => _editProfile(context, ref, profile),
              );
            },
          ),
        ),
      ],
    );
  },
  loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(child: Text('Error: $err')),
      ),
    );
  }

  void _editProfile(BuildContext context, WidgetRef ref, Profile profile) {
    final deliveryCostController = TextEditingController(text: profile.defaultDeliveryCost.toStringAsFixed(0));
    final routeNoController = TextEditingController(text: profile.routeNo?.toString() ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile.fullName ?? 'Unknown'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address Details
            const Text('Address Details', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 8),
            if (profile.addressLine1?.isNotEmpty == true) Text(profile.addressLine1!),
            if (profile.addressLine2?.isNotEmpty == true) Text(profile.addressLine2!),
            if (profile.landmark?.isNotEmpty == true) Text('Landmark: ${profile.landmark}'),
            if (profile.area?.isNotEmpty == true) Text('Area/City: ${profile.area}'),
            if (profile.pincode?.isNotEmpty == true) Text('Pincode: ${profile.pincode}'),
            if (profile.addressLine1 == null && profile.area == null) 
              const Text('No address provided.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            const Divider(height: 24),
            
            TextField(
              controller: deliveryCostController,
              decoration: const InputDecoration(
                labelText: 'Default Delivery Cost (₹)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_shipping),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: routeNoController,
              decoration: const InputDecoration(
                labelText: 'Route No.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.route),
                hintText: 'e.g. 1, 2, 3...',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(deliveryCostController.text) ?? 0.0;
              final routeNo = int.tryParse(routeNoController.text);
              await ref.read(profilesRepositoryProvider).updateProfile(profile.id, {
                'delivery_cost': cost,
                'route_no': routeNo,
              });
              ref.invalidate(allProfilesProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
