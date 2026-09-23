import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../models/product_category.dart';
import '../providers/product_provider.dart';

class EditProductScreen extends ConsumerStatefulWidget {
  final Product product;

  const EditProductScreen({super.key, required this.product});

  @override
  ConsumerState<EditProductScreen> createState() {
    return _EditProductScreenState();
  }
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
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
          .read(myProductsProvider.notifier)
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

    if (price == null || price <= 0) {
      return 'Please enter a valid price greater than 0';
    }

    return null;
  }

  String? validateOfferPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter offer price';
    }

    final offerPrice = double.tryParse(value.trim());

    if (offerPrice == null || offerPrice <= 0) {
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Edit Product',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ==================================================
                      // HEADER
                      // ==================================================
                      Text(
                        'Edit product',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Update the details of your existing product.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ==================================================
                      // PRODUCT IMAGE
                      // ==================================================
                      _SectionCard(
                        title: 'Product image',
                        subtitle:
                            'Choose a new image or keep the existing one.',
                        child: Column(
                          children: [
                            Container(
                              height: 230,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: buildImagePreview(context),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isSaving ? null : pickImage,
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    label: Text(
                                      selectedImage == null
                                          ? 'Change Image'
                                          : 'Choose Another',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isSaving ? null : removeImage,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    label: const Text('Remove'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      foregroundColor: colorScheme.error,
                                      side: BorderSide(
                                        color: colorScheme.error.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'JPG, PNG or WebP • Maximum 5 MB',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // BASIC INFORMATION
                      // ==================================================
                      _SectionCard(
                        title: 'Basic information',
                        subtitle:
                            'Update the product name, description, and category.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _FieldLabel(text: 'Product name'),

                            const SizedBox(height: 8),

                            TextFormField(
                              controller: nameController,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Enter product name',
                                prefixIcon: Icon(Icons.shopping_bag_outlined),
                              ),
                              validator: validateName,
                            ),

                            const SizedBox(height: 20),

                            const _FieldLabel(text: 'Description'),

                            const SizedBox(height: 8),

                            TextFormField(
                              controller: descriptionController,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Enter product description',
                                prefixIcon: Icon(Icons.description_outlined),
                                alignLabelWithHint: true,
                              ),
                              validator: validateDescription,
                            ),

                            const SizedBox(height: 20),

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
                                      Icon(
                                        category.icon,
                                        size: 20,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(category.name),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: isSaving
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() {
                                        selectedCategory = value;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==================================================
                      // PRICE & INVENTORY
                      // ==================================================
                      _SectionCard(
                        title: 'Price & inventory',
                        subtitle:
                            'Update the original price, offer price, and stock.',
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 500;

                            final originalPriceField = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _FieldLabel(text: 'Original price'),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: originalPriceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    hintText: '2999.00',
                                    prefixText: '₹ ',
                                    prefixIcon: Icon(Icons.currency_rupee),
                                  ),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    hintText: '2399.00',
                                    prefixText: '₹ ',
                                    prefixIcon: Icon(
                                      Icons.local_offer_outlined,
                                    ),
                                  ),
                                  validator: validateOfferPrice,
                                ),
                              ],
                            );

                            final stockField = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _FieldLabel(text: 'Stock'),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: stockController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: '20',
                                    prefixIcon: Icon(
                                      Icons.inventory_2_outlined,
                                    ),
                                  ),
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
                      ),

                      const SizedBox(height: 24),

                      // ==================================================
                      // SAVE BUTTON
                      // ==================================================
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: isSaving ? null : saveChanges,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            isSaving ? 'Saving changes...' : 'Save Changes',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Your changes will be saved to your store.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 4),

          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 18),

          child,
        ],
      ),
    );
  }
}

// ================================================================
// FIELD LABEL
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
