import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/product_service.dart';
import '../theme/app_theme.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final supabase = Supabase.instance.client;

  int selectedIndex = 0;

  bool isLoading = true;
  String? errorMessage;

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> merchants = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  // ==========================================================================
  // LOAD DASHBOARD
  // ==========================================================================

  Future<void> _loadDashboard() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final results = await Future.wait([
        supabase
            .from('products')
            .select(
              'id, name, description, offer_price, stock, category, image_url, merchant_id, created_at',
            )
            .order('created_at', ascending: false),
        supabase
            .from('profiles')
            .select('id, name, email, role, merchant_status, created_at')
            .eq('role', 'merchant')
            .order('created_at', ascending: false),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        products = List<Map<String, dynamic>>.from(results[0]);
        merchants = List<Map<String, dynamic>>.from(results[1]);
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage = 'Could not load admin data.';
      });
    }
  }

  // ==========================================================================
  // DELETE PRODUCT
  // ==========================================================================

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final productId = product['id'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete product?'),
          content: Text('This will permanently delete "${product['name']}".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await supabase.from('products').delete().eq('id', productId);
      await ProductService().deleteProductImage(
        product['image_url']?.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        products.removeWhere((item) => item['id'] == productId);
      });

      _showMessage('Product deleted successfully.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not delete the product.', isError: true);
    }
  }

  // ==========================================================================
  // SUSPEND / RESTORE MERCHANT
  // ==========================================================================

  Future<void> _toggleMerchantStatus(Map<String, dynamic> merchant) async {
    final merchantId = merchant['id'];
    final currentStatus = merchant['merchant_status'] as String? ?? 'approved';

    final isSuspended = currentStatus == 'suspended';
    final newStatus = isSuspended ? 'approved' : 'suspended';

    final action = isSuspended ? 'restore' : 'suspend';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isSuspended ? 'Restore merchant?' : 'Suspend merchant?'),
          content: Text(
            isSuspended
                ? 'This will allow ${merchant['name']} to manage products again.'
                : 'This will prevent ${merchant['name']} from managing products.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isSuspended
                    ? const Color(0xFF541B3D)
                    : Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(isSuspended ? 'Restore' : 'Suspend'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await supabase.rpc(
        'admin_set_merchant_status',
        params: {'p_merchant_id': merchantId, 'p_status': newStatus},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final index = merchants.indexWhere((item) => item['id'] == merchantId);

        if (index != -1) {
          merchants[index] = {
            ...merchants[index],
            'merchant_status': newStatus,
          };
        }
      });

      _showMessage(
        isSuspended
            ? 'Merchant restored successfully.'
            : 'Merchant suspended successfully.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not $action the merchant.', isError: true);
    }
  }

  // ==========================================================================
  // LOGOUT
  // ==========================================================================

  Future<void> _logout() async {
    await supabase.auth.signOut();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  // ==========================================================================
  // MESSAGE
  // ==========================================================================

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Colors.red.shade700
              : const Color(0xFF541B3D),
          content: Text(message),
        ),
      );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AdminBrandMark(size: 36),
            const SizedBox(width: 11),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GoCart',
                  style: TextStyle(
                    color: GoCartTheme.ink,
                    fontSize: 16,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'ADMIN CONSOLE',
                  style: TextStyle(
                    color: Color(0xFF76666C),
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF541B3D)),
            )
          : errorMessage != null
          ? _ErrorState(message: errorMessage!, onRetry: _loadDashboard)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSidebar(),
                      Expanded(child: _buildContent()),
                    ],
                  );
                }

                return _buildContent();
              },
            ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? _buildBottomNavigation()
          : null,
    );
  }

  // ==========================================================================
  // SIDEBAR
  // ==========================================================================

  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF28101F), Color(0xFF42192E), Color(0xFF311123)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x33F0C5A1)),
                    ),
                    child: const Row(
                      children: [
                        _AdminBrandMark(size: 44),
                        SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GoCart',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'ADMIN CONSOLE',
                                style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFCDB8C2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  _NavItem(
                    icon: Icons.dashboard_outlined,
                    title: 'Overview',
                    selected: selectedIndex == 0,
                    onTap: () {
                      setState(() {
                        selectedIndex = 0;
                      });
                    },
                  ),

                  _NavItem(
                    icon: Icons.inventory_2_outlined,
                    title: 'Products',
                    selected: selectedIndex == 1,
                    onTap: () {
                      setState(() {
                        selectedIndex = 1;
                      });
                    },
                  ),

                  _NavItem(
                    icon: Icons.storefront_outlined,
                    title: 'Merchants',
                    selected: selectedIndex == 2,
                    onTap: () {
                      setState(() {
                        selectedIndex = 2;
                      });
                    },
                  ),

                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0x33F0C5A1)),
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: Color(0xFFE7B98A),
                          child: Icon(
                            Icons.verified_user_rounded,
                            size: 19,
                            color: Color(0xFF541B3D),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin access',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Secure marketplace tools',
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1.3,
                                  color: Color(0xFFD4C1C8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // BOTTOM NAVIGATION
  // ==========================================================================

  Widget _buildBottomNavigation() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFF2D0AA),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Overview',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2_rounded),
          label: 'Products',
        ),
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront_rounded),
          label: 'Merchants',
        ),
      ],
    );
  }

  // ==========================================================================
  // CONTENT
  // ==========================================================================

  Widget _buildContent() {
    switch (selectedIndex) {
      case 1:
        return _buildProductsPage();

      case 2:
        return _buildMerchantsPage();

      default:
        return _buildOverviewPage();
    }
  }

  // ==========================================================================
  // OVERVIEW
  // ==========================================================================

  Widget _buildOverviewPage() {
    final approvedMerchants = merchants
        .where((merchant) => merchant['merchant_status'] == 'approved')
        .length;

    final suspendedMerchants = merchants
        .where((merchant) => merchant['merchant_status'] == 'suspended')
        .length;

    final totalStock = products.fold<int>(
      0,
      (sum, product) => sum + ((product['stock'] as num?)?.toInt() ?? 0),
    );

    return _PageContainer(
      title: 'Welcome back, Admin! 👋',
      subtitle: 'Manage your GoCart marketplace.',
      featured: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 14.0;
              final columns = constraints.maxWidth >= 1040
                  ? 5
                  : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _StatCard(
                    width: cardWidth,
                    title: 'Products',
                    value: products.length.toString(),
                    icon: Icons.inventory_2_outlined,
                    accent: const Color(0xFF67223F),
                    softAccent: const Color(0xFFF4E8E7),
                    detail: 'In marketplace',
                  ),
                  _StatCard(
                    width: cardWidth,
                    title: 'Merchants',
                    value: merchants.length.toString(),
                    icon: Icons.storefront_outlined,
                    accent: const Color(0xFFEB8500),
                    softAccent: const Color(0xFFFFF0DB),
                    detail: 'Registered stores',
                  ),
                  _StatCard(
                    width: cardWidth,
                    title: 'Approved',
                    value: approvedMerchants.toString(),
                    icon: Icons.verified_outlined,
                    accent: const Color(0xFF12A66A),
                    softAccent: const Color(0xFFE2F8ED),
                    detail: 'Active merchants',
                  ),
                  _StatCard(
                    width: cardWidth,
                    title: 'Suspended',
                    value: suspendedMerchants.toString(),
                    icon: Icons.block_outlined,
                    accent: const Color(0xFFE14D75),
                    softAccent: const Color(0xFFFFE8EE),
                    detail: 'Restricted stores',
                  ),
                  _StatCard(
                    width: cardWidth,
                    title: 'Total Stock',
                    value: totalStock.toString(),
                    icon: Icons.inventory_outlined,
                    accent: const Color(0xFF3979E8),
                    softAccent: const Color(0xFFE7F0FF),
                    detail: 'Units available',
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 22),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFEADDD5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C5C31A6),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _RecentProductsHeader(
                  productCount: products.length,
                  onViewAll: () => setState(() => selectedIndex = 1),
                ),
                const SizedBox(height: 14),
                if (products.isEmpty)
                  const _EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products yet',
                    message: 'Products added by merchants will appear here.',
                  )
                else
                  ...products
                      .take(5)
                      .map(
                        (product) => _buildProductTile(product, compact: true),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PRODUCTS
  // ==========================================================================

  Widget _buildProductsPage() {
    return _PageContainer(
      title: 'Products',
      subtitle: 'Manage every product published on GoCart.',
      child: products.isEmpty
          ? const _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No products found',
              message: 'There are currently no products.',
            )
          : Column(children: products.map(_buildProductTile).toList()),
    );
  }

  Widget _buildProductTile(
    Map<String, dynamic> product, {
    bool compact = false,
  }) {
    final imageUrl = product['image_url'] as String?;
    final price = (product['offer_price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock'] as num?)?.toInt() ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 9 : 12),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFEADDD5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product['name']?.toString() ?? 'Unnamed product',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF21172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product['category']?.toString() ?? 'Other',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (narrow) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '₹${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF541B3D),
                      ),
                    ),
                    _StockBadge(stock: stock),
                  ],
                ),
              ],
            ],
          );

          return Row(
            children: [
              _ProductThumbnail(imageUrl: imageUrl, size: compact ? 54 : 64),
              const SizedBox(width: 12),
              Expanded(child: details),
              if (!narrow) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    '₹${price.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF541B3D),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(width: 102, child: _StockBadge(stock: stock)),
              ],
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Delete product',
                onPressed: () => _deleteProduct(product),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFEEF1),
                  foregroundColor: const Color(0xFFE14668),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // MERCHANTS
  // ==========================================================================

  Widget _buildMerchantsPage() {
    return _PageContainer(
      title: 'Merchants',
      subtitle: 'Manage merchant accounts and access.',
      child: merchants.isEmpty
          ? const _EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No merchants found',
              message: 'There are currently no merchant accounts.',
            )
          : Column(children: merchants.map(_buildMerchantTile).toList()),
    );
  }

  Widget _buildMerchantTile(Map<String, dynamic> merchant) {
    final status = merchant['merchant_status'] as String? ?? 'approved';

    final isSuspended = status == 'suspended';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEADDD5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 500;
          final identity = Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: isSuspended
                    ? const Color(0xFFFFE5E5)
                    : const Color(0xFFF4E8E7),
                child: Icon(
                  Icons.storefront_outlined,
                  color: isSuspended
                      ? Colors.red.shade700
                      : const Color(0xFF541B3D),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant['name']?.toString() ?? 'Unnamed merchant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF21172A),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      merchant['email']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 7),

                    _StatusBadge(status: status),
                  ],
                ),
              ),
            ],
          );
          final action = FilledButton.tonal(
            onPressed: () => _toggleMerchantStatus(merchant),
            style: FilledButton.styleFrom(
              foregroundColor: isSuspended
                  ? const Color(0xFF541B3D)
                  : Colors.red.shade700,
            ),
            child: Text(isSuspended ? 'Restore' : 'Suspend'),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// PAGE CONTAINER
// ============================================================================

class _RecentProductsHeader extends StatelessWidget {
  final int productCount;
  final VoidCallback onViewAll;

  const _RecentProductsHeader({
    required this.productCount,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;

        return Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 13 : 17,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFF7EF), Color(0xFFF0DED1), Color(0xFFFBF1E8)],
            ),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFEAD8C9)),
          ),
          child: Stack(
            children: [
              const Positioned(
                right: 90,
                top: -45,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0x33A66A35),
                  size: 88,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: Color(0xFF541B3D),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent products',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            color: const Color(0xFF21172A),
                          ),
                        ),
                        if (!compact)
                          Text(
                            '$productCount products in your marketplace',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF76666C),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF541B3D),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text(compact ? 'All' : 'View all'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockBadge extends StatelessWidget {
  final int stock;

  const _StockBadge({required this.stock});

  @override
  Widget build(BuildContext context) {
    final color = stock <= 0
        ? const Color(0xFFE14668)
        : stock <= 5
        ? const Color(0xFFB46A00)
        : const Color(0xFF138C55);
    final background = stock <= 0
        ? const Color(0xFFFFEDF1)
        : stock <= 5
        ? const Color(0xFFFFF4DF)
        : const Color(0xFFEAF9F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        stock <= 0 ? 'Out of stock' : 'Stock: $stock',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _PageContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool featured;

  const _PageContainer({
    required this.title,
    required this.subtitle,
    required this.child,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (featured)
                _AdminWelcomeBanner(title: title, subtitle: subtitle)
              else ...[
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF7E9DC), Color(0xFFEED3BA)],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        title == 'Products'
                            ? Icons.inventory_2_rounded
                            : Icons.storefront_rounded,
                        color: Color(0xFF541B3D),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: Color(0xFF21172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
              ],

              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STAT CARD
// ============================================================================

class _StatCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color softAccent;
  final String detail;

  const _StatCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.softAccent,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        height: 116,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, softAccent.withValues(alpha: 0.58)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: softAccent),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -33,
              bottom: -59,
              child: Container(
                width: 146,
                height: 100,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(80),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: softAccent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF76666C),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 25,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                          color: Color(0xFF21172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminWelcomeBanner extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AdminWelcomeBanner({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 550;

        return Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(compact ? 20 : 25),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF9F1), Color(0xFFF2E2D7), Color(0xFFFAF0E6)],
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFEAD8C9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14541B3D),
                blurRadius: 28,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: compact ? -75 : 70,
                top: -115,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.34),
                  ),
                ),
              ),
              Positioned(
                right: -15,
                bottom: -90,
                child: Container(
                  width: 245,
                  height: 145,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(130),
                    gradient: const LinearGradient(
                      colors: [Color(0x44A85274), Color(0x0FE7B98A)],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'MARKETPLACE OVERVIEW',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF541B3D),
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Text(
                          title,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 23 : 31,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: const Color(0xFF17132E),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF76666C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 22),
                    SizedBox(
                      width: 174,
                      height: 118,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.8),
                                width: 2,
                              ),
                            ),
                          ),
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF9B4965), Color(0xFF541B3D)],
                              ),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x407135D9),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.shopping_bag_rounded,
                              size: 38,
                              color: Colors.white,
                            ),
                          ),
                          const Positioned(
                            right: 10,
                            top: 12,
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xFFC28B5B),
                              size: 22,
                            ),
                          ),
                          const Positioned(
                            left: 13,
                            bottom: 11,
                            child: Icon(
                              Icons.circle,
                              color: Color(0xFFE7B98A),
                              size: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// NAV ITEM
// ============================================================================

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xFFF2D0AA), Color(0xFFE6B783)],
                    )
                  : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x336E3A4E),
                        blurRadius: 15,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? const Color(0xFF541B3D)
                      : const Color(0xFFD8C5CC),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? const Color(0xFF541B3D) : Colors.white,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF541B3D),
                    size: 19,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBrandMark extends StatelessWidget {
  final double size;

  const _AdminBrandMark({this.size = 38});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF81324F), Color(0xFF541B3D)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x336E3A4E),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Icon(
        Icons.shopping_cart_rounded,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}

// ============================================================================
// STATUS BADGE
// ============================================================================

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSuspended = status == 'suspended';
    final isApproved = status == 'approved';
    final label = switch (status) {
      'suspended' => 'Suspended',
      'approved' => 'Approved',
      'pending' => 'Pending',
      _ => 'Unknown',
    };
    final color = isSuspended
        ? Colors.red.shade700
        : isApproved
        ? Colors.green.shade700
        : const Color(0xFF9A6500);
    final backgroundColor = isSuspended
        ? const Color(0xFFFFE8E8)
        : isApproved
        ? const Color(0xFFE8F7EE)
        : const Color(0xFFFFF3D8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================================
// PRODUCT THUMBNAIL
// ============================================================================

class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _ProductThumbnail({required this.imageUrl, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF6EEE8),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.trim().isEmpty
          ? const Icon(Icons.image_outlined, color: Color(0xFF9B858C))
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF9B858C),
                );
              },
            ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEADDD5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFFB99EA9)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF21172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ERROR STATE
// ============================================================================

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Color(0xFF9B858C),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF541B3D),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
