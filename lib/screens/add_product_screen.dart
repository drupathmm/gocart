import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product_category.dart';
import '../providers/product_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/product_form_components.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  final String merchantId;

  const AddProductScreen({super.key, required this.merchantId});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final originalPriceController = TextEditingController();
  final offerPriceController = TextEditingController();
  final stockController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  XFile? selectedImage;
  Uint8List? selectedImageBytes;

  // ==========================================================
  // CATEGORY
  // ==========================================================

  // Uses the first category from the single centralized
  // GoCart category list.
  String selectedCategory = ProductCategory.all.first.name;

  bool isSaving = false;

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    originalPriceController.dispose();
    offerPriceController.dispose();
    stockController.dispose();

    super.dispose();
  }

  // ==========================================================
  // PICK IMAGE
  // ==========================================================

  Future<void> pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (image == null || !mounted) {
        return;
      }

      final bytes = await image.readAsBytes();

      if (!mounted) {
        return;
      }

      if (bytes.isEmpty || bytes.length > _maxImageSizeBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bytes.isEmpty
                  ? 'The selected image could not be read.'
                  : 'Image size must be 5 MB or less.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        selectedImage = image;
        selectedImageBytes = bytes;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ==========================================================
  // REMOVE IMAGE
  // ==========================================================

  void removeSelectedImage() {
    setState(() {
      selectedImage = null;
      selectedImageBytes = null;
    });
  }

  // ==========================================================
  // SAVE PRODUCT
  // ==========================================================

  Future<void> saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final originalPrice = double.tryParse(originalPriceController.text.trim());

    final offerPrice = double.tryParse(offerPriceController.text.trim());

    final stock = int.tryParse(stockController.text.trim());

    if (originalPrice == null || offerPrice == null || stock == null) {
      return;
    }

    // Make sure the selected category belongs to the
    // centralized GoCart category list.
    if (!ProductCategory.isValid(selectedCategory)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid product category.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (offerPrice > originalPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Offer price cannot be greater than the original price.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await ref
          .read(myProductsProvider(widget.merchantId).notifier)
          .addProduct(
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
            originalPrice: originalPrice,
            offerPrice: offerPrice,
            stock: stock,
            category: selectedCategory,
            imageFile: selectedImage,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product added successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add product: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  // ==========================================================
  // VALIDATORS
  // ==========================================================

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter product name';
    }

    if (value.trim().length > 150) {
      return 'Product name must be 150 characters or less';
    }

    return null;
  }

  String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter product description';
    }

    return null;
  }

  String? validateOriginalPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter original price';
    }

    final price = double.tryParse(value.trim());

    if (price == null || !price.isFinite || price <= 0) {
      return 'Enter a valid price greater than 0';
    }

    return null;
  }

  String? validateOfferPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter offer price';
    }

    final offerPrice = double.tryParse(value.trim());

    if (offerPrice == null || !offerPrice.isFinite || offerPrice <= 0) {
      return 'Enter a valid price greater than 0';
    }

    final originalPrice = double.tryParse(originalPriceController.text.trim());

    if (originalPrice != null && offerPrice > originalPrice) {
      return 'Cannot be greater than original price';
    }

    return null;
  }

  String? validateStock(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter stock quantity';
    }

    final stock = int.tryParse(value.trim());

    if (stock == null || stock < 0) {
      return 'Enter a valid stock quantity';
    }

    return null;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1080;

    final basicInformation = ProductFormSection(
      icon: Icons.edit_note_rounded,
      title: 'Product details',
      subtitle: 'Give your listing a clear name and description.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel(text: 'Product name'),
          const SizedBox(height: 8),
          TextFormField(
            controller: nameController,
            enabled: !isSaving,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLength: 150,
            decoration: const InputDecoration(
              hintText: 'e.g. Wireless Headphones',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            validator: validateName,
          ),
          const SizedBox(height: 18),
          const _FieldLabel(text: 'Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: descriptionController,
            enabled: !isSaving,
            minLines: 4,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Describe the features and benefits of your product.',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
            validator: validateDescription,
          ),
          const SizedBox(height: 18),
          const _FieldLabel(text: 'Category'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedCategory,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: ProductCategory.all.map((category) {
              return DropdownMenuItem<String>(
                value: category.name,
                child: Row(
                  children: [
                    Icon(category.icon, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(category.name),
                  ],
                ),
              );
            }).toList(),
            onChanged: isSaving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => selectedCategory = value);
                  },
          ),
        ],
      ),
    );

    final productImage = ProductFormSection(
      icon: Icons.add_photo_alternate_outlined,
      title: 'Product photography',
      subtitle: 'Use a clear, well-lit photo to showcase your product.',
      child: Column(
        children: [
          _ImagePreview(
            imageBytes: selectedImageBytes,
            onRemove: selectedImage == null ? null : removeSelectedImage,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: isSaving ? null : pickImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                selectedImage == null
                    ? 'Choose product photo'
                    : 'Replace photo',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'JPG, PNG or WebP · Up to 5 MB',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final priceAndInventory = ProductFormSection(
      icon: Icons.price_change_outlined,
      title: 'Price & inventory',
      subtitle: 'Set your pricing and available quantity.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;

          final originalPriceField = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel(text: 'Original price'),
              const SizedBox(height: 8),
              TextFormField(
                controller: originalPriceController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '2999.00',
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}),
                validator: validateOriginalPrice,
              ),
            ],
          );

          final offerPriceField = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel(text: 'Offer price'),
              const SizedBox(height: 8),
              TextFormField(
                controller: offerPriceController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '2399.00',
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                onChanged: (_) => setState(() {}),
                validator: validateOfferPrice,
              ),
            ],
          );

          final stockField = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel(text: 'Available stock'),
              const SizedBox(height: 8),
              TextFormField(
                controller: stockController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                ),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: '25',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                onChanged: (_) => setState(() {}),
                validator: validateStock,
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              children: [
                originalPriceField,
                const SizedBox(height: 16),
                offerPriceField,
                const SizedBox(height: 16),
                stockField,
              ],
            );
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: originalPriceField),
                  const SizedBox(width: 14),
                  Expanded(child: offerPriceField),
                ],
              ),
              const SizedBox(height: 16),
              stockField,
            ],
          );
        },
      ),
    );

    final listingPreview = ProductListingPreview(
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
      category: selectedCategory,
      imageBytes: selectedImageBytes,
      showImagePlaceholder: selectedImageBytes == null,
      offerPrice: double.tryParse(offerPriceController.text.trim()),
      originalPrice: double.tryParse(originalPriceController.text.trim()),
      stock: int.tryParse(stockController.text.trim()),
    );

    final publishButton = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: isSaving ? null : saveProduct,
            icon: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.publish_rounded),
            label: Text(
              isSaving ? 'Uploading & saving…' : 'Publish product',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your product will appear in your store after it is saved.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(
        title: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: GoCartTheme.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFFCF8), Color(0xFFF5E5D9)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: GoCartTheme.outline),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF541B3D,
                              ).withValues(alpha: 0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFF541B3D),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.add_box_rounded,
                                color: Colors.white,
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MERCHANT STUDIO  ·  NEW LISTING',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Add a product',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(fontSize: 28),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Create a polished listing for your store.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isWide)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: const Color(0xFFEAD8C9),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.verified_outlined,
                                      size: 16,
                                      color: Color(0xFF541B3D),
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'STORE LISTING',
                                      style: TextStyle(
                                        color: Color(0xFF541B3D),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  basicInformation,
                                  const SizedBox(height: 18),
                                  productImage,
                                  const SizedBox(height: 18),
                                  priceAndInventory,
                                  const SizedBox(height: 22),
                                  publishButton,
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  listingPreview,
                                  const SizedBox(height: 16),
                                  const ProductListingTipsCard(),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        basicInformation,
                        const SizedBox(height: 16),
                        productImage,
                        const SizedBox(height: 16),
                        priceAndInventory,
                        const SizedBox(height: 16),
                        listingPreview,
                        const SizedBox(height: 16),
                        const ProductListingTipsCard(),
                        const SizedBox(height: 22),
                        publishButton,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// IMAGE PREVIEW
// ==========================================================

class _ImagePreview extends StatelessWidget {
  final Uint8List? imageBytes;
  final VoidCallback? onRemove;

  const _ImagePreview({required this.imageBytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imageBytes == null) {
      return Container(
        height: 210,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFCF8), Color(0xFFF5EBE7)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEADDD5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFF1E1E6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                size: 29,
                color: Color(0xFF541B3D),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Your product photo will appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF281622),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use a square or landscape image for best results.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.memory(
            imageBytes!,
            width: double.infinity,
            height: 210,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 210,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Could not preview image',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            },
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: Colors.black.withValues(alpha: 0.65),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Remove image',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
