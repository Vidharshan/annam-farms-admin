import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class ImageUploadService {
  final SupabaseClient _client;
  final ImagePicker _picker = ImagePicker();

  ImageUploadService(this._client);

  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  Future<String?> uploadProductImage(XFile imageFile, String productId) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.name.split('.').last;
      final fileName = '$productId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'products/$fileName';

      // Upload to Supabase Storage
      await _client.storage.from('product-images').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExt',
          upsert: true,
        ),
      );

      // Get public URL
      final publicUrl = _client.storage.from('product-images').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print('Error uploading image: $e');
      throw Exception('Image upload failed: $e');
    }
  }

  Future<String?> uploadCategoryImage(XFile imageFile, String categoryId) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final fileExt = imageFile.name.split('.').last;
      final fileName = '$categoryId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'categories/$fileName';

      // Upload to Supabase Storage
      await _client.storage.from('product-images').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExt',
          upsert: true,
        ),
      );

      // Get public URL
      final publicUrl = _client.storage.from('product-images').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print('Error uploading category image: $e');
      throw Exception('Category image upload failed: $e');
    }
  }
}

final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  return ImageUploadService(Supabase.instance.client);
});
