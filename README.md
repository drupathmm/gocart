# 🛒 GoCart

> A modern mini e-commerce application built with Flutter and Supabase.

<p align="center">
  <a href="https://drupathmm.github.io/gocart/">
    <strong>🌐 Live Demo</strong>
  </a>
  &nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="https://github.com/drupathmm/gocart">
    <strong>💻 Source Code</strong>
  </a>
</p>

---

## 📌 About

GoCart is a full-stack mini e-commerce application developed using Flutter and Supabase.

The application supports two types of users:

- **Merchant** - Manage products by adding, editing, and deleting products.
- **Buyer** - Browse products, search for products, view product details, and manage a shopping cart.

The project uses Supabase for authentication and database operations, with Row Level Security (RLS) policies to control access to application data.

---

## 🚀 Live Demo

### 🌐 [Open GoCart Live Demo](https://drupathmm.github.io/gocart/)

The application is deployed using **GitHub Pages** with a GitHub Actions workflow that automatically builds and deploys the Flutter web application.

---

## ✨ Features

### 🔐 Authentication

- User signup
- User login
- Email and password authentication
- Role selection during signup
- Automatic routing based on user role

### 🛍️ Buyer

- Browse available products
- Search products
- View product details
- View stock availability
- Add products to cart
- Increase/decrease cart quantity
- Remove products from cart
- View cart total
- Profile page
- Logout

### 🏪 Merchant

- Merchant dashboard
- View own products
- Add new products
- Edit existing products
- Delete products
- Manage product price
- Manage stock
- Add product image URL
- Product descriptions

### 🗄️ Backend

- Supabase Authentication
- PostgreSQL database
- Row Level Security (RLS)
- Supabase CRUD operations
- User profiles
- Products
- Cart items

---

## 🧰 Tech Stack

| Technology | Purpose |
|---|---|
| Flutter | Frontend application |
| Dart | Programming language |
| Supabase | Backend platform |
| PostgreSQL | Database |
| Riverpod | State management |
| Git | Version control |
| GitHub | Source code hosting |
| GitHub Actions | CI/CD |
| GitHub Pages | Web deployment |

---

## 🏗️ Project Structure

```text
gocart/
│
├── assets/
│   └── images/
│       └── gocart_logo.png
│
├── lib/
│   ├── models/
│   │   ├── cart_item.dart
│   │   ├── product.dart
│   │   └── profile.dart
│   │
│   ├── providers/
│   │   ├── cart_provider.dart
│   │   ├── product_provider.dart
│   │   └── profile_provider.dart
│   │
│   ├── screens/
│   │   ├── add_product_screen.dart
│   │   ├── cart_screen.dart
│   │   ├── edit_product_screen.dart
│   │   ├── login_screen.dart
│   │   ├── merchant_dashboard_screen.dart
│   │   ├── product_detail_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── splash_screen.dart
│   │   └── user_home_screen.dart
│   │
│   ├── services/
│   │   ├── cart_service.dart
│   │   ├── product_service.dart
│   │   └── profile_service.dart
│   │
│   ├── widgets/
│   │   └── gocart_logo.dart
│   │
│   └── main.dart
│
├── web/
│   ├── icons/
│   ├── favicon.png
│   ├── index.html
│   └── manifest.json
│
├── .github/
│   └── workflows/
│       └── deploy.yml
│
├── pubspec.yaml
└── README.md
