import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../data/inventory_repository.dart';
import '../../../shared/domain/product_model.dart';
import 'product_form_dialog.dart';
import 'categories_screen.dart';
import '../../../main.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Product Inventory'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SizedBox(
              width: 150,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddProductDialog(context),
            tooltip: 'Add Product',
          ),
          IconButton(
            icon: const Icon(Icons.category),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              );
            },
            tooltip: 'Manage Categories',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(productsProvider),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: productsAsync.when(
        data: (products) {
          final filteredProducts = products.where((p) {
            return p.name.toLowerCase().contains(_searchQuery);
          }).toList();

          if (filteredProducts.isEmpty) {
            return const Center(child: Text('No products found'));
          }

          return DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 900,
            fixedLeftColumns: 1,
            columns: const [
              DataColumn2(label: Text('Product Name'), size: ColumnSize.M),
              DataColumn2(label: Text('Category'), size: ColumnSize.S),
              DataColumn2(label: Text('Price'), size: ColumnSize.S),
              DataColumn2(label: Text('Unit'), size: ColumnSize.S),
              DataColumn2(label: Text('Stock'), size: ColumnSize.S),
              DataColumn2(label: Text('Status'), size: ColumnSize.S),
              DataColumn2(label: Text('Actions'), size: ColumnSize.M),
            ],
            rows: filteredProducts.map((product) {
              return DataRow2(
                cells: [
                  DataCell(Text(product.name)),
                  DataCell(const Text('Category')), // TODO: Join with categories table
                  DataCell(Text('₹${product.price}')),
                  DataCell(Text(product.unit)),
                  DataCell(
                    InkWell(
                      onTap: () => _editStock(context, product),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: product.currentStock > 10
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${product.currentStock}',
                          style: TextStyle(
                            color: product.currentStock > 10 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Icon(
                      product.isActive ? Icons.check_circle : Icons.cancel,
                      color: product.isActive ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _editProduct(context, product),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          onPressed: () => _deleteProduct(context, product),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  void _editStock(BuildContext context, ProductModel product) {
    final controller = TextEditingController(text: product.currentStock.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Stock: ${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Stock Quantity',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newStock = double.tryParse(controller.text);
              if (newStock != null) {
                try {
                  print('Updating stock to $newStock for product ${product.id}');
                  await ref.read(inventoryRepositoryProvider).updateProductStock(
                    product.id,
                    newStock,
                  );
                  ref.invalidate(productsProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stock updated successfully!')),
                    );
                  }
                } catch (e) {
                  print('Error updating stock: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _editProduct(BuildContext context, ProductModel product) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (context) => ProductFormDialog(product: product),
    );
  }

  void _deleteProduct(BuildContext context, ProductModel product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(inventoryRepositoryProvider).deleteProduct(product.id);
              ref.invalidate(productsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ProductFormDialog(),
    );
  }
}
