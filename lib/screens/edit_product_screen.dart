import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
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

  late TextEditingController nameController;
  late TextEditingController descriptionController;
  late TextEditingController priceController;
  late TextEditingController stockController;
  late TextEditingController imageUrlController;

  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.product.name);

    descriptionController = TextEditingController(
      text: widget.product.description,
    );

    priceController = TextEditingController(
      text: widget.product.price.toStringAsFixed(2),
    );

    stockController = TextEditingController(
      text: widget.product.stock.toString(),
    );

    imageUrlController = TextEditingController(
      text: widget.product.imageUrl ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    imageUrlController.dispose();

    super.dispose();
  }

  Future<void> saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final price = double.tryParse(priceController.text.trim());

    final stock = int.tryParse(stockController.text.trim());

    if (price == null || stock == null) {
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
            price: price,
            stock: stock,
            imageUrl: imageUrlController.text.trim().isEmpty
                ? null
                : imageUrlController.text.trim(),
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

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter product name';
    }

    return null;
  }

  String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter description';
    }

    return null;
  }

  String? validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter price';
    }

    final price = double.tryParse(value.trim());

    if (price == null || price < 0) {
      return 'Please enter a valid price';
    }

    return null;
  }

  String? validateStock(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter stock';
    }

    final stock = int.tryParse(value.trim());

    if (stock == null || stock < 0) {
      return 'Please enter a valid stock';
    }

    return null;
  }

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
                      // ----------------------------------------
                      // HEADER
                      // ----------------------------------------
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

                      // ----------------------------------------
                      // IMAGE
                      // ----------------------------------------
                      _SectionCard(
                        title: 'Product image',
                        subtitle:
                            'Update the image URL if you want to change the product image.',
                        child: Column(
                          children: [
                            Container(
                              height: 210,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: _ProductImage(
                                imageUrl: imageUrlController.text,
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: imageUrlController,
                              keyboardType: TextInputType.url,
                              onChanged: (_) {
                                setState(() {});
                              },
                              decoration: InputDecoration(
                                labelText: 'Image URL',
                                hintText: 'https://example.com/image.jpg',
                                prefixIcon: const Icon(Icons.link_rounded),
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
                        subtitle: 'Update the product name and description.',
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
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ----------------------------------------
                      // PRICE & INVENTORY
                      // ----------------------------------------
                      _SectionCard(
                        title: 'Price & inventory',
                        subtitle:
                            'Update the selling price and available stock.',
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
                                      hintText: '20',
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

class _ProductImage extends StatelessWidget {
  final String imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final url = imageUrl.trim();

    if (url.isEmpty) {
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
          const SizedBox(height: 10),
          Text(
            'No product image',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
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
