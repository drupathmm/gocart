import 'package:flutter/material.dart';

class ProductCartQuantityBadge extends StatelessWidget {
  const ProductCartQuantityBadge({super.key, required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    if (quantity <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF541B3D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'In cart: $quantity',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
