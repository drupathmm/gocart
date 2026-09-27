import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../models/product_category.dart';
import '../providers/product_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/product_form_components.dart';

class EditProductScreen extends ConsumerStatefulWidget {
  final Product product;

  const EditProductScreen({super.key, required this.product});

  @override
  ConsumerState<EditProductScreen> createState() {
    return _EditProductScreenState();
  }
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController originalPriceController;
  late TextEditingController offerPriceController;
  late TextEditingController stockController;

  XFile? selectedImage;
  Uint8List? selectedImageBytes;

  late String selectedCategory;

  bool removeExistingImage = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.product.name);

    descriptionController = TextEditingController(
      text: widget.product.description,
    );

    originalPriceController = TextEditingController(
      text: widget.product.originalPrice.toStringAsFixed(2),
    );

    offerPriceController = TextEditingController(
      text: widget.product.offerPrice.toStringAsFixed(2),
    );

    stockController = TextEditingController(
      text: widget.product.stock.toString(),
    );

    // Use the existing category if it belongs to the centralized
    // GoCart category list.
    //
    // Older products may contain category names from the previous
    // category system. Until the database migration is completed,
    // those products temporarily fall back to the first valid
    // category so the dropdown always has a valid value.
    selectedCategory = ProductCategory.isValid(widget.product.category)
        ? widget.product.category
        : ProductCategory.all.first.name;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    originalPriceController.dispose();
    offerPriceController.dispose();
    stockController.dispose();

    super.dispose();
  }

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (image == null) {
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
        removeExistingImage = false;
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

  // ============================================================
  // REMOVE IMAGE
  // ============================================================

  void removeImage() {
    setState(() {
      if (selectedImageBytes != null) {
        selectedImage = null;
        selectedImageBytes = null;
        return;
      }

      selectedImage = null;
      selectedImageBytes = null;
      removeExistingImage = true;
    });
  }

  // ============================================================
  // SAVE CHANGES
  // ============================================================

  Future<void> saveChanges() async {
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
    // centralized GoCart category system.
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
          .read(myProductsProvider(widget.product.merchantId).notifier)
          .updateProduct(
            productId: widget.product.id,
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
            originalPrice: originalPrice,
            offerPrice: offerPrice,
            stock: stock,
            category: selectedCategory,
            imageFile: selectedImage,
            removeImage: removeExistingImage,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product updated successfully'),
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
          content: Text('Failed to update product: $error'),
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

  // ============================================================
  // VALIDATORS
  // ============================================================

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter product name';
    }

    if (value.trim().length > 150) {
      return 'Product name must be 150 characters or less';
    }

    return null;
  }

  String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter description';
    }

    return null;
  }

  String? validateOriginalPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter original price';
    }

    final price = double.tryParse(value.trim());

    if (price == null || !price.isFinite || price <= 0) {
      return 'Please enter a valid price greater than 0';
    }

    return null;
  }

  String? validateOfferPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter offer price';
    }

    final offerPrice = double.tryParse(value.trim());

    if (offerPrice == null || !offerPrice.isFinite || offerPrice <= 0) {
      return 'Please enter a valid price greater than 0';
    }

    final originalPrice = double.tryParse(originalPriceController.text.trim());

    if (originalPrice != null && offerPrice > originalPrice) {
      return 'Cannot be greater than original price';
    }

    return null;
  }

  String? validateStock(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter stock';
    }

    final stock = int.tryParse(value.trim());

    if (stock == null || stock < 0) {
      return 'Please enter a valid stock quantity';
    }

    return null;
  }

  // ============================================================
  // IMAGE PREVIEW
  // ============================================================

  Widget buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // New image selected.
    if (selectedImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(
          selectedImageBytes!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const _EmptyImagePreview(
              message: 'Unable to preview image',
              icon: Icons.broken_image_outlined,
            );
          },
        ),
      );
    }

    // Existing image removed.
    if (removeExistingImage) {
      return const _EmptyImagePreview(
        message: 'No product image',
        icon: Icons.image_not_supported_outlined,
      );
    }

    // Existing Supabase image.
    final existingImageUrl = widget.product.imageUrl;

    if (existingImageUrl != null && existingImageUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          existingImageUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const _EmptyImagePreview(
              message: 'Unable to load image',
              icon: Icons.broken_image_outlined,
            );
          },
        ),
      );
    }

    // No image.
    return _EmptyImagePreview(
      message: 'No product image',
      icon: Icons.image_outlined,
      iconColor: colorScheme.onSurfaceVariant,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1080;
    final existingImageUrl = widget.product.imageUrl?.trim();
    final hasExistingImage =
        existingImageUrl != null && existingImageUrl.isNotEmpty;

    final productDetails = ProductFormSection(
      icon: Icons.edit_note_rounded,
      title: 'Product details',
      subtitle: 'Keep the listing name and description clear and accurate.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel(text: 'Product name'),
          const SizedBox(height: 8),
          TextFormField(
            controller: nameController,
            enabled: !isSaving,
            maxLength: 150,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Enter product name',
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

    final photoControls = LayoutBuilder(
      builder: (context, constraints) {
        final pickButton = FilledButton.icon(
          onPressed: isSaving ? null : pickImage,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            selectedImage == null ? 'Choose product photo' : 'Replace photo',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
        );
        final removeButton = OutlinedButton.icon(
          onPressed:
              isSaving ||
                  (selectedImageBytes == null &&
                      (removeExistingImage || !hasExistingImage))
              ? null
              : removeImage,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Remove photo'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pickButton, const SizedBox(height: 10), removeButton],
          );
        }

        return Row(
          children: [
            Expanded(child: pickButton),
            const SizedBox(width: 12),
            Expanded(child: removeButton),
          ],
        );
      },
    );

    final productPhotography = ProductFormSection(
      icon: Icons.add_photo_alternate_outlined,
      title: 'Product photography',
      subtitle: 'Keep the existing photo or choose a clearer one.',
      child: Column(
        children: [
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF5EBE7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEADDD5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: buildImagePreview(context),
          ),
          const SizedBox(height: 16),
          photoControls,
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
      subtitle: 'Review pricing and stock before saving your changes.',
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
                  hintText: '20',
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
      imageUrl: widget.product.imageUrl,
      showImagePlaceholder: removeExistingImage,
      offerPrice: double.tryParse(offerPriceController.text.trim()),
      originalPrice: double.tryParse(originalPriceController.text.trim()),
      stock: int.tryParse(stockController.text.trim()),
    );

    final saveButton = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: isSaving ? null : saveChanges,
            icon: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              isSaving ? 'Saving changes…' : 'Save changes',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your updated listing will appear in your store after it is saved.',
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
          'Edit Product',
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
                                Icons.edit_note_rounded,
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
                                    'MERCHANT STUDIO  ·  EDIT LISTING',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Edit your product',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(fontSize: 28),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Review every detail before saving your listing.',
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
                                      Icons.storefront_outlined,
                                      size: 16,
                                      color: Color(0xFF541B3D),
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'STORE LISTING',
                                      style: TextStyle(
                                        color: Color(0xFF541B3D),
                                        fontSize: 11,
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
                                  productDetails,
                                  const SizedBox(height: 18),
                                  productPhotography,
                                  const SizedBox(height: 18),
                                  priceAndInventory,
                                  const SizedBox(height: 22),
                                  saveButton,
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
                        productDetails,
                        const SizedBox(height: 16),
                        productPhotography,
                        const SizedBox(height: 16),
                        priceAndInventory,
                        const SizedBox(height: 16),
                        listingPreview,
                        const SizedBox(height: 16),
                        const ProductListingTipsCard(),
                        const SizedBox(height: 22),
                        saveButton,
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

// ================================================================
// SECTION CARD
// ================================================================

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

// ================================================================
// EMPTY IMAGE PREVIEW
// ================================================================

class _EmptyImagePreview extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? iconColor;

  const _EmptyImagePreview({
    required this.message,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 32,
            color: iconColor ?? colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 10),

        Text(message, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
