import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../providers/cart_provider.dart';
import '../providers/profile_provider.dart';
import 'cart_screen.dart';
import 'login_screen.dart';

// ============================================================================
// GOCART BRAND COLORS
// ============================================================================

class _GoCartColors {
  static const Color purple = Color(0xFF6F4B9B);
  static const Color darkPurple = Color(0xFF4D2D73);
  static const Color pearlWhite = Color(0xFFFFF9FF);
}

// ============================================================================
// PROFILE SCREEN
// ============================================================================

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      backgroundColor: _GoCartColors.pearlWhite,
      body: RefreshIndicator(
        color: _GoCartColors.purple,
        onRefresh: () {
          return ref.read(profileProvider.notifier).refreshProfile();
        },
        child: profileAsync.when(
          loading: () {
            return const _LoadingView();
          },
          error: (error, stackTrace) {
            return _ErrorView(
              onRetry: () {
                ref.read(profileProvider.notifier).refreshProfile();
              },
            );
          },
          data: (profile) {
            return _ProfileContent(
              profile: profile,
              cartCount: cartCount,
              ref: ref,
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// PROFILE CONTENT
// ============================================================================

class _ProfileContent extends StatelessWidget {
  final Profile profile;
  final int cartCount;
  final WidgetRef ref;

  const _ProfileContent({
    required this.profile,
    required this.cartCount,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 18,
        28,
        isDesktop ? 32 : 18,
        40,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==========================================================
                // PAGE TITLE
                // ==========================================================
                const Text(
                  'My Profile',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Manage your GoCart account and preferences.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),

                const SizedBox(height: 24),

                // ==========================================================
                // PROFILE HEADER
                // ==========================================================
                _ProfileHeader(profile: profile),

                const SizedBox(height: 28),

                // ==========================================================
                // QUICK ACCESS
                // ==========================================================
                const _SectionTitle(
                  title: 'Quick Access',
                  subtitle: 'Shortcuts to your shopping activity',
                ),

                const SizedBox(height: 12),

                _QuickAccessCard(
                  icon: Icons.shopping_cart_rounded,
                  title: 'My Cart',
                  subtitle:
                      '$cartCount item${cartCount == 1 ? '' : 's'} in your cart',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CartScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // ==========================================================
                // ACCOUNT
                // ==========================================================
                const _SectionTitle(
                  title: 'Account',
                  subtitle: 'Personal details and app preferences',
                ),

                const SizedBox(height: 12),

                _AccountMenu(
                  onPersonalInformation: () {
                    _showPersonalInformation(context, profile);
                  },
                  onSettings: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Settings will be available soon.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 22),

                // ==========================================================
                // LOGOUT
                // ==========================================================
                _LogoutCard(
                  onTap: () {
                    _logout(context, ref);
                  },
                ),

                const SizedBox(height: 30),

                // ==========================================================
                // FOOTER
                // ==========================================================
                const _ProfileFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // LOGOUT
  // ==========================================================================

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout?'),
          content: const Text(
            'Are you sure you want to logout of your GoCart account?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(profileProvider.notifier).signOut();

      ref.invalidate(profileProvider);

      ref.invalidate(cartProvider);

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ==========================================================================
  // PERSONAL INFORMATION
  // ==========================================================================

  void _showPersonalInformation(BuildContext context, Profile profile) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: _GoCartColors.pearlWhite,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _GoCartColors.purple,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                _InfoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Name',
                  value: profile.name,
                ),

                const SizedBox(height: 18),

                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: profile.email,
                ),

                const SizedBox(height: 18),

                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Account Type',
                  value: profile.isMerchant ? 'Merchant' : 'User / Buyer',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// PROFILE HEADER
// ============================================================================

class _ProfileHeader extends StatelessWidget {
  final Profile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.trim().isNotEmpty
        ? profile.name.trim().substring(0, 1).toUpperCase()
        : '?';

    final accountTitle = profile.isMerchant
        ? 'Merchant Account'
        : 'Buyer Account';

    final accountDescription = profile.isMerchant
        ? 'Manage your products and store.'
        : 'Browse products and manage your cart.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_GoCartColors.purple, _GoCartColors.darkPurple],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _GoCartColors.purple.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          // ================================================================
          // AVATAR
          // ================================================================
          Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: _GoCartColors.darkPurple,
              ),
            ),
          ),

          const SizedBox(width: 20),

          // ================================================================
          // DETAILS
          // ================================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.80),
                  ),
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        profile.isMerchant
                            ? Icons.storefront_rounded
                            : Icons.shopping_bag_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        accountTitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  accountDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SECTION TITLE
// ============================================================================

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ============================================================================
// QUICK ACCESS
// ============================================================================

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _GoCartColors.purple,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: Colors.grey.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ACCOUNT MENU
// ============================================================================

class _AccountMenu extends StatelessWidget {
  final VoidCallback onPersonalInformation;
  final VoidCallback onSettings;

  const _AccountMenu({
    required this.onPersonalInformation,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _AccountItem(
            icon: Icons.person_outline_rounded,
            title: 'Personal Information',
            subtitle: 'View your account details',
            onTap: onPersonalInformation,
          ),

          Divider(
            height: 1,
            indent: 68,
            endIndent: 18,
            color: Colors.grey.shade200,
          ),

          _AccountItem(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'App preferences',
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ACCOUNT ITEM
// ============================================================================

class _AccountItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _GoCartColors.purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: _GoCartColors.purple),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LOGOUT
// ============================================================================

class _LogoutCard extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                  size: 21,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sign out of your GoCart account',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: Colors.red.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PERSONAL INFORMATION ROW
// ============================================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _GoCartColors.purple.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: _GoCartColors.purple),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FOOTER
// ============================================================================

class _ProfileFooter extends StatelessWidget {
  const _ProfileFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _GoCartColors.purple,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.shopping_bag_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 9),

        const Text(
          'GoCart',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _GoCartColors.darkPurple,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          'Mini E-Commerce App',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ============================================================================
// LOADING
// ============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: _GoCartColors.purple),
    );
  }
}

// ============================================================================
// ERROR
// ============================================================================

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 130),

        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.red.shade600,
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Could not load your profile',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Text(
          'Please try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),

        const SizedBox(height: 20),

        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ),
      ],
    );
  }
}
