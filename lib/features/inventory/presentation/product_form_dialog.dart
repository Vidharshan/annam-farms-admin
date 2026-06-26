import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/domain/product_model.dart';
import '../../../shared/domain/category_model.dart';
import '../data/inventory_repository.dart';
import '../../../core/services/image_upload_service.dart';

class ProductFormDialog extends ConsumerStatefulWidget {
  final ProductModel? product; // null for add, non-null for edit
  
  const ProductFormDialog({super.key, this.product});

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _unitController;
  late TextEditingController _imageUrlController;
  late TextEditingController _orderTypeController;
  late TextEditingController _denomSetController;
  String? _selectedCategoryId;
  bool _isActive = true;
  XFile? _selectedImage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _priceController = TextEditingController(text: p?.price.toString() ?? '');
    _stockController = TextEditingController(text: p?.currentStock.toString() ?? '');
    _unitController = TextEditingController(text: p?.unit ?? 'kg');
    _imageUrlController = TextEditingController(text: p?.imageUrl ?? '');
    _orderTypeController = TextEditingController(text: p?.orderType ?? 'weight');
    _denomSetController = TextEditingController(text: p?.denomSet ?? '');
    _selectedCategoryId = p?.categoryId;
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _unitController.dispose();
    _imageUrlController.dispose();
    _orderTypeController.dispose();
    _denomSetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return AlertDialog(
      title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                categoriesAsync.when(
                  data: (categories) => DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category *',
                      border: OutlineInputBorder(),
                    ),
                    items: categories.map((cat) {
                      return DropdownMenuItem(
                        value: cat.id,
                        child: Text(cat.name),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedCategoryId = value),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const Text('Error loading categories'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price (₹) *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Unit *',
                          border: OutlineInputBorder(),
                          hintText: 'kg, bunch, pack',
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _stockController,
                  decoration: const InputDecoration(
                    labelText: 'Current Stock *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _orderTypeController,
                        decoration: const InputDecoration(
                          labelText: 'Order Type',
                          border: OutlineInputBorder(),
                          hintText: 'weight, piece, packed',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _denomSetController,
                        decoration: const InputDecoration(
                          labelText: 'Denom Set',
                          border: OutlineInputBorder(),
                          hintText: 'cluster, small, staple, fruit',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Image Upload Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Product Image', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_selectedImage != null || _imageUrlController.text.isNotEmpty)
                        Container(
                          height: 150,
                          width: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _selectedImage != null
                              ? const Center(child: Icon(Icons.image, size: 50))
                              : Image.network(
                                  _imageUrlController.text,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                                ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Choose Photo'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take Photo'),
                          ),
                        ],
                      ),
                      if (_selectedImage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Selected: ${_selectedImage!.name}', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveProduct,
          child: Text(widget.product == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ref.read(imageUploadServiceProvider).pickImage(source: source);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUploading = true);

    try {
      String imageUrl = _imageUrlController.text.isEmpty 
          ? 'https://via.placeholder.com/150' 
          : _imageUrlController.text;

      // Upload image if selected
      if (_selectedImage != null) {
        final productId = widget.product?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
        final uploadedUrl = await ref.read(imageUploadServiceProvider).uploadProductImage(
          _selectedImage!,
          productId,
        );
        if (uploadedUrl != null) {
          imageUrl = uploadedUrl;
        }
      }

      final data = {
        'name': _nameController.text,
        'category_id': _selectedCategoryId,
        'description': _descriptionController.text,
        'price': double.parse(_priceController.text),
        'unit': _unitController.text,
        'current_stock': double.parse(_stockController.text),
        'image_url': imageUrl,
        'is_active': _isActive,
        'order_type': _orderTypeController.text,
        'denom_set': _denomSetController.text.isEmpty ? null : _denomSetController.text,
      };

      if (widget.product == null) {
        await ref.read(inventoryRepositoryProvider).createProduct(data);
      } else {
        await ref.read(inventoryRepositoryProvider).updateProduct(
          widget.product!.id,
          data,
        );
      }
      ref.invalidate(productsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}
