import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../../shared/domain/category_model.dart';

import 'package:image_picker/image_picker.dart';
import '../../../core/services/image_upload_service.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No categories found. Add one!'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final category = categories[index];
              return ListTile(
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(category.imageUrl),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    ),
                  ),
                  child: category.imageUrl.isEmpty 
                      ? const Icon(Icons.category, color: Colors.white) 
                      : null,
                ),
                title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Sort Order: ${category.sortOrder}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showAddEditDialog(context, category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDelete(context, category),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddEditDialog(BuildContext context, CategoryModel? category) async {
    final isEditing = category != null;
    final nameController = TextEditingController(text: category?.name ?? '');
    final imageUrlController = TextEditingController(text: category?.imageUrl ?? '');
    final sortController = TextEditingController(text: category?.sortOrder.toString() ?? '0');
    
    // State for dialog
    XFile? selectedImage;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          // Inner function to handle image picking
          Future<void> pickImage(ImageSource source) async {
            final image = await ref.read(imageUploadServiceProvider).pickImage(source: source);
            if (image != null) {
              setState(() => selectedImage = image);
            }
          }

          return AlertDialog(
            title: Text(isEditing ? 'Edit Category' : 'Add Category'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Category Name'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Image Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        if (selectedImage != null)
                          Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(selectedImage!.path), // For web/local this works differently in some contexts, but usually OK for XFile.path on mobile/desktop
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else if (imageUrlController.text.isNotEmpty)
                          Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(imageUrlController.text),
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.image, color: Colors.white, size: 40),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: isUploading ? null : () => pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: isUploading ? null : () => pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Camera'),
                            ),
                          ],
                        ),
                        if (selectedImage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              selectedImage!.name,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextField(
                    controller: sortController,
                    decoration: const InputDecoration(labelText: 'Sort Order'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUploading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isUploading ? null : () async {
                  if (nameController.text.isEmpty) return;

                  setState(() => isUploading = true);

                  try {
                    String finalImageUrl = imageUrlController.text;

                    // Upload Image if selected
                    if (selectedImage != null) {
                      final categoryId = category?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                      final uploadedUrl = await ref.read(imageUploadServiceProvider).uploadCategoryImage(
                        selectedImage!, 
                        categoryId,
                      );
                      if (uploadedUrl != null) {
                        finalImageUrl = uploadedUrl;
                      }
                    }

                    final repo = ref.read(inventoryRepositoryProvider);
                    
                    if (isEditing) {
                      await repo.updateCategory(category!.id, {
                        'name': nameController.text,
                        'image_url': finalImageUrl,
                        'sort_order': int.tryParse(sortController.text) ?? 0,
                      });
                    } else {
                      await repo.createCategory(
                        nameController.text,
                        finalImageUrl,
                        int.tryParse(sortController.text) ?? 0,
                      );
                    }

                    ref.invalidate(categoriesProvider);
                    if (mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => isUploading = false);
                  }
                },
                child: isUploading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : Text(isEditing ? 'Save' : 'Add'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(inventoryRepositoryProvider).deleteCategory(category.id);
        ref.invalidate(categoriesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          String message = 'Error: $e';
          if (e.toString().contains('permission denied') || e.toString().contains('403')) {
            message = 'Database Permission Error: Please enable DELETE on categories table in Supabase RLS.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'SQL Fix',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supabase RLS Fix'),
                      content: const SelectableText(
                        'Run this in Supabase SQL Editor:\n\n'
                        'ALTER POLICY "Enable delete for authenticated users" ON "public"."categories" '
                        'USING (auth.role() = \'authenticated\');'
                        '\n\n(Adjust policy name if needed)',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    }
  }
}
