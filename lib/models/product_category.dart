import 'package:flutter/material.dart';

class ProductCategory {
  final String name;
  final IconData icon;

  const ProductCategory({required this.name, required this.icon});

  // ============================================================
  // GOCART MASTER PRODUCT CATEGORIES
  //
  // This is the single source of truth for categories across
  // Buyer Home, Merchant Dashboard, Add Product, Edit Product,
  // Product Service, and product filtering.
  // ============================================================

  static const List<ProductCategory> all = [
    ProductCategory(name: 'Electronics', icon: Icons.devices_outlined),
    ProductCategory(
      name: 'Mobiles & Tablets',
      icon: Icons.phone_android_outlined,
    ),
    ProductCategory(name: 'Fashion', icon: Icons.checkroom_outlined),
    ProductCategory(
      name: 'Beauty & Personal Care',
      icon: Icons.face_retouching_natural_outlined,
    ),
    ProductCategory(name: 'Home & Kitchen', icon: Icons.home_outlined),
    ProductCategory(name: 'Appliances', icon: Icons.kitchen_outlined),
    ProductCategory(
      name: 'Grocery & Food',
      icon: Icons.shopping_basket_outlined,
    ),
    ProductCategory(
      name: 'Sports & Fitness',
      icon: Icons.sports_soccer_outlined,
    ),
    ProductCategory(name: 'Toys & Baby', icon: Icons.toys_outlined),
    ProductCategory(name: 'Automotive', icon: Icons.directions_car_outlined),
  ];

  // ============================================================
  // CATEGORY NAMES ONLY
  //
  // Useful for:
  // - Supabase validation
  // - Dropdowns
  // - Filtering
  // - Form validation
  // ============================================================

  static List<String> get names {
    return all.map((category) => category.name).toList();
  }

  // ============================================================
  // FIND CATEGORY BY NAME
  // ============================================================

  static ProductCategory? findByName(String name) {
    for (final category in all) {
      if (category.name == name) {
        return category;
      }
    }

    return null;
  }

  // ============================================================
  // CHECK WHETHER A CATEGORY IS VALID
  // ============================================================

  static bool isValid(String name) {
    return all.any((category) => category.name == name);
  }
}
