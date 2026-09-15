import 'package:flutter/material.dart';

import 'cart_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(),
              ),
              child: const Center(child: Icon(Icons.image_outlined, size: 100)),
            ),

            const SizedBox(height: 24),

            const Text(
              'Product Name',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            const Text(
              '₹0.00',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            const Text(
              'Product Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text('Product description will be loaded from Supabase.'),

            const SizedBox(height: 20),

            const Text('Stock: Available', style: TextStyle(fontSize: 16)),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Add to cart will be connected to Supabase.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Add to Cart'),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CartScreen()),
                  );
                },
                child: const Text('View Cart'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
