import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/domain/product_model.dart';
import '../../../shared/domain/category_model.dart';

class InventoryRepository {
  final SupabaseClient _client;

  InventoryRepository(this._client);

  Future<List<ProductModel>> getAllProducts() async {
    final response = await _client
        .from('products')
        .select('*, categories(*)')
        .order('name');
    
    return (response as List)
        .map((json) => ProductModel.fromJson(json))
        .toList();
  }



  Future<void> updateProductStock(String productId, double newStock) async {
    try {
      print('Admin: Updating stock for product $productId to $newStock');
      await _client
          .from('products')
          .update({'current_stock': newStock})
          .eq('id', productId);
      print('Admin: Stock updated successfully');
    } catch (e) {
      print('Admin: Error updating stock: $e');
      rethrow;
    }
  }

  Future<void> updateProduct(String productId, Map<String, dynamic> updates) async {
    await _client
        .from('products')
        .update(updates)
        .eq('id', productId);
  }

  Future<void> createProduct(Map<String, dynamic> productData) async {
    await _client.from('products').insert(productData);
  }

  Future<void> deleteProduct(String productId) async {
    await _client.from('products').delete().eq('id', productId);
  }

  // Categories
  Future<List<CategoryModel>> getAllCategories() async {
    final response = await _client
        .from('categories')
        .select()
        .order('sort_order');
    
    return (response as List)
        .map((json) => CategoryModel.fromJson(json))
        .toList();
  }

  Future<void> createCategory(String name, String imageUrl, int sortOrder) async {
    await _client.from('categories').insert({
      'name': name,
      'image_url': imageUrl,
      'sort_order': sortOrder,
    });
  }

  Future<void> updateCategory(String id, Map<String, dynamic> updates) async {
    await _client.from('categories').update(updates).eq('id', id);
  }

  Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(Supabase.instance.client);
});

final productsProvider = FutureProvider<List<ProductModel>>((ref) async {
  return ref.watch(inventoryRepositoryProvider).getAllProducts();
});

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  return ref.watch(inventoryRepositoryProvider).getAllCategories();
});
