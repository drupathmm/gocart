import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product_category.dart';
import '../providers/product_provider.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
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
          .read(myProductsProvider.notifier)
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

    if (price == null || price <= 0) {
      return 'Enter a valid price greater than 0';
    }

    return null;
  }

  String? validateOfferPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter offer price';
    }

    final offerPrice = double.tryParse(value.trim());

    if (offerPrice == null || offerPrice <= 0) {
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Add Product',
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
                      Text(
                        'Create a product',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add the details below to publish a new product to your store.',
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
                            'Choose a JPG, PNG, or WebP image from your device.',
                        child: Column(
                          children: [
                            _ImagePreview(
                              imageBytes: selectedImageBytes,
                              onRemove: selectedImage == null
                                  ? null
                                  : removeSelectedImage,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: isSaving ? null : pickImage,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  selectedImage == null
                                      ? 'Choose Image'
                                      : 'Choose Another Image',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Maximum size: 5 MB',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
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
                        subtitle: 'Tell customers what you are selling.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _FieldLabel(text: 'Product name'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: nameController,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                hintText: 'e.g. Wireless Headphones',
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
                                hintText: 'Describe your product...',
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
                            'Set the original price, offer price, and stock.',
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
                                    hintText: '25',
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
                          onPressed: isSaving ? null : saveProduct,
                          icon: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                            isSaving ? 'Uploading & saving...' : 'Save Product',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'The image will be securely stored in Supabase Storage.',
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
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No image selected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
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

// ==========================================================
// SECTION CARD
// ==========================================================

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

// ==========================================================
// FIELD LABEL
// ==========================================================

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
