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

## Merchant security review status

Merchant signup currently submits a merchant role and the database signup
trigger assigns `pending`; the Flutter signup flow does not call the legacy
self-approval RPC. The reviewed SQL that revokes that RPC and adds database
guards for product visibility, cart writes, and legacy checkout is still a
local draft. It has not been applied to GoCart, and the last verified live
audit found the self-approval and suspension protections incomplete. Treat
the live database as unpatched until an approved deployment is completed and
verified.

The local notification inbox and event migration cover merchant status and
reinstatement decisions, orders, and captured payments. They are local changes
and have not been applied or tested against a database. Merchant registration
continues to use the existing admin registration inbox.

The admin dashboard calls the reason-aware
`admin_set_merchant_status(uuid, text, text)` contract in the local lifecycle
migration. The last verified legacy live schema exposed the older two-argument
contract. Reconcile that mismatch before deployment; do not replay the local
migration chain to resolve it. No database regression test has completed
against an owner-approved restored baseline. See the [merchant security
deployment checklist](supabase/drafts/critical_merchant_security_deployment_checklist.md)
for current evidence, blockers, and safe validation steps.

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

---

## Run locally

For normal application testing with existing GoCart data, create the ignored
`.env` JSON file using the URL and publishable anonymous key for the
developer-approved hosted GoCart project. Do not copy the local URL from
`.env.example` for this workflow; it targets the local Docker stack. Flutter
reads the JSON file through `--dart-define-from-file`:

```bash
flutter run --dart-define-from-file=.env
```

Checkout keeps a demo path that places an unpaid order without a charge. On
Android and iOS, a separate Razorpay test-mode flow uses the server-created
order and server-side verification; it refuses non-test public keys. It has
not been exercised with Razorpay credentials or provider traffic. The signed
webhook foundation is present. FCM, reviews, commission, and payouts are not yet
implemented. Read `DATABASE_AND_PAYMENT_GUIDE.md` and
`ORDER_STATUS_AND_LOCAL_DEV.md` for payment limitations and decisions still
needed. Use the hosted project only for non-destructive app verification with
existing data. Use an isolated disposable database for database development;
never reset or seed the hosted project.

GitHub Pages builds need repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
