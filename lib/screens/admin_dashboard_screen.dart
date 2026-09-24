import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
                    ? const Color(0xFF6F4B9B)
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
      await supabase
          .from('profiles')
          .update({'merchant_status': newStatus})
          .eq('id', merchantId)
          .eq('role', 'merchant');

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
              : const Color(0xFF6F4B9B),
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
      backgroundColor: const Color(0xFFF8F5FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            color: Color(0xFF21172A),
            fontWeight: FontWeight.w800,
          ),
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
              child: CircularProgressIndicator(color: Color(0xFF6F4B9B)),
            )
          : errorMessage != null
          ? _ErrorState(message: errorMessage!, onRetry: _loadDashboard)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                if (isWide) {
                  return Row(
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1E5FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0xFF6F4B9B),
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'GoCart Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF21172A),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

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

          const Spacer(),

          Text(
            'ADMIN ONLY',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Colors.grey.shade500,
            ),
          ),
        ],
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
      indicatorColor: const Color(0xFFEAD9FA),
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
      title: 'Overview',
      subtitle: 'Manage your GoCart marketplace.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                title: 'Products',
                value: products.length.toString(),
                icon: Icons.inventory_2_outlined,
              ),
              _StatCard(
                title: 'Merchants',
                value: merchants.length.toString(),
                icon: Icons.storefront_outlined,
              ),
              _StatCard(
                title: 'Approved',
                value: approvedMerchants.toString(),
                icon: Icons.verified_outlined,
              ),
              _StatCard(
                title: 'Suspended',
                value: suspendedMerchants.toString(),
                icon: Icons.block_outlined,
              ),
              _StatCard(
                title: 'Total Stock',
                value: totalStock.toString(),
                icon: Icons.inventory_outlined,
              ),
            ],
          ),

          const SizedBox(height: 30),

          const Text(
            'Recent Products',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF21172A),
            ),
          ),

          const SizedBox(height: 14),

          if (products.isEmpty)
            const _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No products yet',
              message: 'Products added by merchants will appear here.',
            )
          else
            ...products.take(5).map(_buildProductTile),
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

  Widget _buildProductTile(Map<String, dynamic> product) {
    final imageUrl = product['image_url'] as String?;
    final price = (product['offer_price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DFED)),
      ),
      child: Row(
        children: [
          _ProductThumbnail(imageUrl: imageUrl),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ?? 'Unnamed product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF21172A),
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  product['category']?.toString() ?? 'Other',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 5),

                Text(
                  '₹${price.toStringAsFixed(2)} • Stock: $stock',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6F4B9B),
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Delete product',
            onPressed: () => _deleteProduct(product),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade700,
            ),
          ),
        ],
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
        border: Border.all(color: const Color(0xFFE8DFED)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: isSuspended
                ? const Color(0xFFFFE5E5)
                : const Color(0xFFF1E5FF),
            child: Icon(
              Icons.storefront_outlined,
              color: isSuspended
                  ? Colors.red.shade700
                  : const Color(0xFF6F4B9B),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 7),

                _StatusBadge(status: status),
              ],
            ),
          ),

          const SizedBox(width: 8),

          FilledButton.tonal(
            onPressed: () => _toggleMerchantStatus(merchant),
            style: FilledButton.styleFrom(
              foregroundColor: isSuspended
                  ? const Color(0xFF6F4B9B)
                  : Colors.red.shade700,
            ),
            child: Text(isSuspended ? 'Restore' : 'Suspend'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PAGE CONTAINER
// ============================================================================

class _PageContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PageContainer({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF21172A),
                ),
              ),

              const SizedBox(height: 5),

              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 25),

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
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8DFED)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF1E5FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF6F4B9B)),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF21172A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selectedTileColor: const Color(0xFFF1E5FF),
        leading: Icon(
          icon,
          color: selected ? const Color(0xFF6F4B9B) : Colors.grey.shade600,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? const Color(0xFF6F4B9B) : const Color(0xFF4A4050),
          ),
        ),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isSuspended ? const Color(0xFFFFE8E8) : const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isSuspended ? 'Suspended' : 'Approved',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isSuspended ? Colors.red.shade700 : Colors.green.shade700,
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

  const _ProductThumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0F8),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.trim().isEmpty
          ? const Icon(Icons.image_outlined, color: Color(0xFF9A8EA2))
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF9A8EA2),
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
        border: Border.all(color: const Color(0xFFE8DFED)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFFB2A5BA)),
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
              color: Color(0xFF9A8EA2),
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
                backgroundColor: const Color(0xFF6F4B9B),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
