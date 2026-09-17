import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final priceController = TextEditingController();
  final stockController = TextEditingController();
  final imageUrlController = TextEditingController();

  bool isSaving = false;
  bool showImagePreview = false;

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    imageUrlController.dispose();
    super.dispose();
  }

  Future<void> saveProduct() async {
    if (!_formKey.currentState!.validate()) {
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
            price: double.parse(priceController.text.trim()),
            stock: int.parse(stockController.text.trim()),
            imageUrl: imageUrlController.text.trim().isEmpty
                ? null
                : imageUrlController.text.trim(),
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

  String? validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter product price';
    }

    final price = double.tryParse(value.trim());

    if (price == null || price < 0) {
      return 'Enter a valid price';
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

  void updateImagePreview() {
    setState(() {
      showImagePreview = imageUrlController.text.trim().isNotEmpty;
    });
  }

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
                      // ----------------------------------------
                      // HEADER
                      // ----------------------------------------
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

                      // ----------------------------------------
                      // IMAGE PREVIEW
                      // ----------------------------------------
                      _SectionCard(
                        title: 'Product image',
                        subtitle:
                            'Add an image URL to show your product visually.',
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 210,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: _buildImagePreview(context),
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: imageUrlController,
                              keyboardType: TextInputType.url,
                              onChanged: (_) {
                                updateImagePreview();
                              },
                              decoration: InputDecoration(
                                labelText: 'Image URL',
                                hintText: 'https://example.com/image.jpg',
                                prefixIcon: const Icon(Icons.link_rounded),
                                suffixIcon:
                                    imageUrlController.text.trim().isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Preview image',
                                        onPressed: updateImagePreview,
                                        icon: const Icon(Icons.refresh_rounded),
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ----------------------------------------
                      // BASIC INFORMATION
                      // ----------------------------------------
                      _SectionCard(
                        title: 'Basic information',
                        subtitle: 'Tell customers what you are selling.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _FieldLabel(text: 'Product name'),

                            const SizedBox(height: 8),

                            TextFormField(
                              controller: nameController,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                hintText: 'e.g. Wireless Headphones',
                                prefixIcon: Icon(Icons.shopping_bag_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter product name';
                                }

                                return null;
                              },
                            ),

                            const SizedBox(height: 20),

                            _FieldLabel(text: 'Description'),

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
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter product description';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ----------------------------------------
                      // PRICE & INVENTORY
                      // ----------------------------------------
                      _SectionCard(
                        title: 'Price & inventory',
                        subtitle: 'Set the selling price and available stock.',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _FieldLabel(text: 'Price'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: priceController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      hintText: '1999.00',
                                      prefixText: '₹ ',
                                      prefixIcon: Icon(Icons.currency_rupee),
                                    ),
                                    validator: validatePrice,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
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
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ----------------------------------------
                      // SAVE BUTTON
                      // ----------------------------------------
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
                            isSaving ? 'Saving product...' : 'Save Product',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Your product will be added to your store catalog.',
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

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final url = imageUrlController.text.trim();

    if (!showImagePreview || url.isEmpty) {
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
              Icons.image_outlined,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Product image preview',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to load image',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
