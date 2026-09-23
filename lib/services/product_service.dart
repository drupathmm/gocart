import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/product_category.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucketName = 'product-images';
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;

  // ============================================================
  // GOCART PRODUCT CATEGORIES
  // ============================================================
  //
  // Product categories come from one central source.
  //
  // This means Add Product, Edit Product, Buyer Home,
  // Merchant Dashboard, filtering, and validation all use
  // exactly the same category names.
  //

  static List<String> get categories => ProductCategory.names;

  // --------------------------------------------------
  // Get all products
  // --------------------------------------------------

  Future<List<Product>> getAllProducts() async {
    final response = await _supabase
        .from('products')
        .select()
        .order('created_at', ascending: false);

    return _mapProducts(response);
  }

  // --------------------------------------------------
  // Get products belonging to logged-in merchant
  // --------------------------------------------------

  Future<List<Product>> getMyProducts() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final response = await _supabase
        .from('products')
        .select()
        .eq('merchant_id', user.id)
        .order('created_at', ascending: false);

    return _mapProducts(response);
  }

  // --------------------------------------------------
  // Get single product
  // --------------------------------------------------

  Future<Product> getProductById(int productId) async {
    final response = await _supabase
        .from('products')
        .select()
        .eq('id', productId)
        .single();

    return Product.fromMap(response);
  }

  // --------------------------------------------------
  // Check that the current account is a merchant
  // --------------------------------------------------

  Future<void> _ensureMerchant() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null || profile['role'] != 'merchant') {
      throw Exception('Only merchants can manage products.');
    }
  }

  // --------------------------------------------------
  // Validate product data
  // --------------------------------------------------

  void _validateProductData({
    required String name,
    required double originalPrice,
    required double offerPrice,
    required int stock,
    required String category,
  }) {
    if (name.trim().isEmpty) {
      throw Exception('Product name is required.');
    }

    if (name.trim().length > 150) {
      throw Exception('Product name must be 150 characters or less.');
    }

    if (originalPrice <= 0) {
      throw Exception('Original price must be greater than 0.');
    }

    if (offerPrice <= 0) {
      throw Exception('Offer price must be greater than 0.');
    }

    if (offerPrice > originalPrice) {
      throw Exception('Offer price cannot be greater than the original price.');
    }

    if (stock < 0) {
      throw Exception('Stock cannot be negative.');
    }

    final normalizedCategory = category.trim();

    if (normalizedCategory.isEmpty) {
      throw Exception('Please select a category.');
    }

    // Validate against the single central category source.
    if (!ProductCategory.isValid(normalizedCategory)) {
      throw Exception('Please select a valid product category.');
    }
  }

  // --------------------------------------------------
  // Convert Supabase response into Product objects
  // --------------------------------------------------

  List<Product> _mapProducts(dynamic response) {
    return (response as List)
        .map((item) => Product.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------
  // Upload product image to Supabase Storage
  // --------------------------------------------------

  Future<String> _uploadProductImage(XFile imageFile) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final bytes = await imageFile.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception('The selected image is empty.');
    }

    if (bytes.length > _maxImageSizeBytes) {
      throw Exception('Image size must be 5 MB or less.');
    }

    final mimeType = _getMimeType(imageFile);

    if (mimeType == null) {
      throw Exception(
        'Unsupported image format. Please select JPG, PNG, or WebP.',
      );
    }

    final extension = _getExtension(mimeType);

    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';

    // Every merchant gets their own Storage folder.
    final storagePath = '${user.id}/$fileName';

    await _supabase.storage
        .from(_bucketName)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            cacheControl: '3600',
            upsert: false,
          ),
        );

    return _supabase.storage.from(_bucketName).getPublicUrl(storagePath);
  }

  // --------------------------------------------------
  // Detect image MIME type
  // --------------------------------------------------

  String? _getMimeType(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();

    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return mimeType;
    }

    final name = file.name.toLowerCase();

    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return 'image/jpeg';
    }

    if (name.endsWith('.png')) {
      return 'image/png';
    }

    if (name.endsWith('.webp')) {
      return 'image/webp';
    }

    return null;
  }

  // --------------------------------------------------
  // Get file extension
  // --------------------------------------------------

  String _getExtension(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return 'png';

      case 'image/webp':
        return 'webp';

      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }

  // --------------------------------------------------
  // Delete image from Supabase Storage
  // --------------------------------------------------

  Future<void> _deleteProductImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return;
    }

    try {
      final uri = Uri.tryParse(imageUrl);

      if (uri == null) {
        return;
      }

      final segments = uri.pathSegments;

      final bucketIndex = segments.indexOf(_bucketName);

      if (bucketIndex == -1) {
        // Not a Supabase Storage URL.
        return;
      }

      final storagePath = segments.sublist(bucketIndex + 1).join('/');

      if (storagePath.isEmpty) {
        return;
      }

      await _supabase.storage.from(_bucketName).remove([storagePath]);
    } catch (error) {
      // Storage cleanup should not make an otherwise
      // successful product operation fail.
      debugPrint('Product image cleanup failed: $error');
    }
  }

  // --------------------------------------------------
  // Create product
  // --------------------------------------------------

  Future<Product> createProduct({
    required String name,
    required String description,
    required double originalPrice,
    required double offerPrice,
    required int stock,
    required String category,
    XFile? imageFile,
  }) async {
    await _ensureMerchant();

    _validateProductData(
      name: name,
      originalPrice: originalPrice,
      offerPrice: offerPrice,
      stock: stock,
      category: category,
    );

    final user = _supabase.auth.currentUser!;

    String? imageUrl;

    try {
      // Upload image first.
      if (imageFile != null) {
        imageUrl = await _uploadProductImage(imageFile);
      }

      final response = await _supabase
          .from('products')
          .insert({
            'merchant_id': user.id,
            'name': name.trim(),
            'description': description.trim(),
            'original_price': originalPrice,
            'offer_price': offerPrice,

            // Keep the old column synchronized during migration.
            'price': offerPrice,

            'stock': stock,
            'category': category.trim(),
            'image_url': imageUrl,
          })
          .select()
          .single();

      return Product.fromMap(response);
    } catch (error) {
      // If database insertion fails after image upload,
      // clean up the uploaded image.
      if (imageUrl != null) {
        await _deleteProductImage(imageUrl);
      }

      rethrow;
    }
  }

  // --------------------------------------------------
  // Update product
  // --------------------------------------------------

  Future<Product> updateProduct({
    required int productId,
    required String name,
    required String description,
    required double originalPrice,
    required double offerPrice,
    required int stock,
    required String category,
    XFile? imageFile,
    bool removeImage = false,
  }) async {
    await _ensureMerchant();

    _validateProductData(
      name: name,
      originalPrice: originalPrice,
      offerPrice: offerPrice,
      stock: stock,
      category: category,
    );

    final existingProduct = await getProductById(productId);

    String? newImageUrl;

    try {
      // Upload replacement image if selected.
      if (imageFile != null) {
        newImageUrl = await _uploadProductImage(imageFile);
      }

      String? finalImageUrl = existingProduct.imageUrl;

      if (newImageUrl != null) {
        finalImageUrl = newImageUrl;
      } else if (removeImage) {
        finalImageUrl = null;
      }

      final response = await _supabase
          .from('products')
          .update({
            'name': name.trim(),
            'description': description.trim(),
            'original_price': originalPrice,
            'offer_price': offerPrice,

            // Keep the old column synchronized during migration.
            'price': offerPrice,

            'stock': stock,
            'category': category.trim(),
            'image_url': finalImageUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', productId)
          .select()
          .single();

      // Remove the old image only after the database update
      // has succeeded.
      if (newImageUrl != null ||
          (removeImage && existingProduct.imageUrl != null)) {
        await _deleteProductImage(existingProduct.imageUrl);
      }

      return Product.fromMap(response);
    } catch (error) {
      // If a replacement image was uploaded but the
      // database update failed, remove the new image.
      if (newImageUrl != null) {
        await _deleteProductImage(newImageUrl);
      }

      rethrow;
    }
  }

  // --------------------------------------------------
  // Delete product
  // --------------------------------------------------

  Future<void> deleteProduct(int productId) async {
    await _ensureMerchant();

    final existingProduct = await getProductById(productId);

    await _supabase.from('products').delete().eq('id', productId);

    // Clean up the associated Storage image after
    // the database deletion succeeds.
    await _deleteProductImage(existingProduct.imageUrl);
  }

  // --------------------------------------------------
  // Search products
  // --------------------------------------------------

  Future<List<Product>> searchProducts(String searchText) async {
    final query = searchText.trim();

    if (query.isEmpty) {
      return getAllProducts();
    }

    final response = await _supabase
        .from('products')
        .select()
        .or(
          'name.ilike.%$query%,description.ilike.%$query%,category.ilike.%$query%',
        )
        .order('created_at', ascending: false);

    return _mapProducts(response);
  }

  // --------------------------------------------------
  // Get products by category
  // --------------------------------------------------

  Future<List<Product>> getProductsByCategory(String category) async {
    final normalizedCategory = category.trim();

    if (normalizedCategory.isEmpty || normalizedCategory == 'All') {
      return getAllProducts();
    }

    // Category filtering uses the same canonical category names
    // used by the rest of the application.
    if (!ProductCategory.isValid(normalizedCategory)) {
      throw Exception('Invalid product category.');
    }

    final response = await _supabase
        .from('products')
        .select()
        .eq('category', normalizedCategory)
        .order('created_at', ascending: false);

    return _mapProducts(response);
  }
}
