import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProductFormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const ProductFormSection({
    super.key,
    required this.icon,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF541B3D).withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1E1E6),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: const Color(0xFF541B3D), size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class ProductListingPreview extends StatelessWidget {
  final String name;
  final String description;
  final String category;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final bool showImagePlaceholder;
  final double? offerPrice;
  final double? originalPrice;
  final int? stock;

  const ProductListingPreview({
    super.key,
    required this.name,
    required this.description,
    required this.category,
    this.imageBytes,
    this.imageUrl,
    this.showImagePlaceholder = false,
    required this.offerPrice,
    required this.originalPrice,
    required this.stock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validOffer =
        offerPrice != null && offerPrice!.isFinite && offerPrice! > 0;
    final validOriginal =
        originalPrice != null &&
        originalPrice!.isFinite &&
        originalPrice! > 0 &&
        (offerPrice == null || originalPrice! >= offerPrice!);
    final validStock = stock != null && stock! >= 0;
    final hasStock = validStock && stock! > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEADDD5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF541B3D).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, color: Color(0xFF541B3D)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Customer preview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1E1E6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PREVIEW',
                  style: TextStyle(
                    color: Color(0xFF541B3D),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: _previewImage(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            category.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: const Color(0xFF8C6A72),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name.isEmpty ? 'Your product name' : name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description.isEmpty
                ? 'Add a short description to help customers understand your product.'
                : description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF76666C),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    validOffer ? '₹${offerPrice!.toStringAsFixed(2)}' : '₹ —',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF541B3D),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (validOriginal)
                Flexible(
                  child: Text(
                    '₹${originalPrice!.toStringAsFixed(2)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF89757D),
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: !validStock
                  ? const Color(0xFFF5EBE7)
                  : hasStock
                  ? const Color(0xFFEAF8F0)
                  : const Color(0xFFFFEBEB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 15,
                  color: !validStock
                      ? const Color(0xFF76666C)
                      : hasStock
                      ? const Color(0xFF29965A)
                      : const Color(0xFFD84A4A),
                ),
                const SizedBox(width: 7),
                Text(
                  !validStock
                      ? 'Stock quantity not set'
                      : hasStock
                      ? '$stock in stock'
                      : 'Out of stock',
                  style: TextStyle(
                    color: !validStock
                        ? const Color(0xFF76666C)
                        : hasStock
                        ? const Color(0xFF287A4D)
                        : const Color(0xFFD84A4A),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewImage(BuildContext context) {
    if (!showImagePlaceholder && imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }

    final url = imageUrl?.trim();
    if (!showImagePlaceholder && url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Color(0xFF541B3D)),
              ),
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF9F1), Color(0xFFEEDBD0)],
        ),
      ),
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 54,
        color: Color(0xFF9A673A),
      ),
    );
  }
}

class ProductListingTipsCard extends StatelessWidget {
  const ProductListingTipsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFCF8), Color(0xFFF7EBDD)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAD8C9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF9A673A)),
              SizedBox(width: 9),
              Text(
                'Tips for a great listing',
                style: TextStyle(
                  color: Color(0xFF281622),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final tip in const [
            'Use a clear, well-lit product photo.',
            'Keep the product name easy to scan.',
            'Double-check your price and stock.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: Color(0xFF9A673A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip, style: textStyle)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
