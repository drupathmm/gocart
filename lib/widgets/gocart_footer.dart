import 'package:flutter/material.dart';

import '../models/product_category.dart';
import '../screens/login_screen.dart';

class GoCartFooter extends StatelessWidget {
  final ValueChanged<String> onCategorySelected;

  const GoCartFooter({super.key, required this.onCategorySelected});

  static const Color footerBackground = Color(0xFF070A1B);
  static const Color footerSurface = Color(0xFF0D1228);
  static const Color footerSurfaceLight = Color(0xFF121936);
  static const Color footerHeading = Color(0xFFF8F4FF);
  static const Color footerText = Color(0xFF9CA6C0);
  static const Color footerMuted = Color(0xFF69738D);
  static const Color footerAccent = Color(0xFF7C5BB3);
  static const Color footerAccentSoft = Color(0xFFB89AE2);
  static const Color footerBorder = Color(0xFF202742);

  // Add the official GoCart Instagram URL here when it is provided.
  // Keeping it in this file means the Home screen never needs to change.
  static const String instagramUrl = '';

  static const List<String> customerCareItems = [
    'Help Center & FAQ',
    'Track Your Order',
    'Returns & Exchanges',
    'Shipping Policy',
    'Contact Support',
  ];

  static const List<String> legalItems = [
    'Privacy Policy',
    'Terms & Conditions',
    'Help & Support',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: footerBackground,
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FooterMain(onCategorySelected: onCategorySelected),
              const SizedBox(height: 48),
              Container(height: 1, color: footerBorder),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 680;

                  if (isMobile) {
                    return Column(
                      children: [
                        const _FooterLegalLinks(),
                        const SizedBox(height: 13),
                        Text(
                          '© ${DateTime.now().year} GoCart. All rights reserved.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: footerMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Text(
                        '© ${DateTime.now().year} GoCart. All rights reserved.',
                        style: const TextStyle(
                          color: footerMuted,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      const _FooterLegalLinks(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterMain extends StatelessWidget {
  final ValueChanged<String> onCategorySelected;

  const _FooterMain({required this.onCategorySelected});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FooterBrand(),
              const SizedBox(height: 42),
              _FooterCategories(onCategorySelected: onCategorySelected),
              const SizedBox(height: 42),
              const _FooterCustomerCare(),
              const SizedBox(height: 42),
              const _FooterSeller(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 4, child: _FooterBrand()),
            const SizedBox(width: 56),
            Expanded(
              flex: 4,
              child: _FooterCategories(onCategorySelected: onCategorySelected),
            ),
            const SizedBox(width: 48),
            const Expanded(flex: 3, child: _FooterCustomerCare()),
            const SizedBox(width: 48),
            const Expanded(flex: 3, child: _FooterSeller()),
          ],
        );
      },
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GoCartFooter.footerAccentSoft,
                    GoCartFooter.footerAccent,
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: GoCartFooter.footerAccent.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shopping_bag_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 13),
            const Text(
              'GoCart',
              style: TextStyle(
                color: GoCartFooter.footerHeading,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SizedBox(
          width: 320,
          child: Text(
            'Shop smarter with products from GoCart merchants, all in one simple and convenient place.',
            style: TextStyle(
              color: GoCartFooter.footerText,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ),
        const SizedBox(height: 25),
        Row(
          children: [
            _FooterSocialButton(
              icon: Icons.facebook_rounded,
              label: 'Facebook',
            ),
            const SizedBox(width: 10),
            _FooterSocialButton(
              icon: Icons.camera_alt_outlined,
              label: 'Instagram',
              isInstagram: true,
            ),
            const SizedBox(width: 10),
            _FooterSocialButton(
              icon: Icons.play_arrow_rounded,
              label: 'YouTube',
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterCategories extends StatelessWidget {
  final ValueChanged<String> onCategorySelected;

  const _FooterCategories({required this.onCategorySelected});

  @override
  Widget build(BuildContext context) {
    // Keep the footer synchronized with the buyer category model.
    // Automotive is excluded because it is not part of the current buyer
    // category navigation shown on the Home screen.
    final categories = ProductCategory.all
        .where((category) => category.name != 'Automotive')
        .toList();

    final firstColumn = <String>['All Products'];
    final secondColumn = <String>[];

    for (var index = 0; index < categories.length; index++) {
      if (index.isEven) {
        firstColumn.add(categories[index].name);
      } else {
        secondColumn.add(categories[index].name);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FooterSectionHeading(
          eyebrow: 'EXPLORE',
          title: 'Shop by category',
        ),
        const SizedBox(height: 17),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 330;

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...firstColumn.map(
                    (item) => _FooterCategoryLink(
                      label: item,
                      onTap: () => onCategorySelected(
                        item == 'All Products' ? 'All' : item,
                      ),
                    ),
                  ),
                  ...secondColumn.map(
                    (item) => _FooterCategoryLink(
                      label: item,
                      onTap: () => onCategorySelected(item),
                    ),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: firstColumn
                        .map(
                          (item) => _FooterCategoryLink(
                            label: item,
                            onTap: () => onCategorySelected(
                              item == 'All Products' ? 'All' : item,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: secondColumn
                        .map(
                          (item) => _FooterCategoryLink(
                            label: item,
                            onTap: () => onCategorySelected(item),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FooterCustomerCare extends StatelessWidget {
  const _FooterCustomerCare();

  @override
  Widget build(BuildContext context) {
    return _FooterLinkColumn(
      eyebrow: 'SUPPORT',
      title: 'Customer care',
      items: GoCartFooter.customerCareItems,
      onItemTap: (item) {
        _showFooterInfoDialog(
          context,
          title: item,
          message: _customerCareMessage(item),
        );
      },
    );
  }
}

class _FooterSeller extends StatelessWidget {
  const _FooterSeller();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FooterSectionHeading(
          eyebrow: 'MERCHANTS',
          title: 'Sell on GoCart',
        ),
        const SizedBox(height: 17),
        const Text(
          'Have products to sell?',
          style: TextStyle(
            color: GoCartFooter.footerText,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Start selling with GoCart.',
          style: TextStyle(
            color: GoCartFooter.footerText,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 19),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    GoCartFooter.footerSurfaceLight,
                    GoCartFooter.footerSurface,
                  ],
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: GoCartFooter.footerAccent.withValues(alpha: 0.45),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Become a Seller',
                    style: TextStyle(
                      color: GoCartFooter.footerHeading,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 9),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: GoCartFooter.footerAccentSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterLinkColumn extends StatelessWidget {
  final String eyebrow;
  final String title;
  final List<String> items;
  final ValueChanged<String> onItemTap;

  const _FooterLinkColumn({
    required this.eyebrow,
    required this.title,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FooterSectionHeading(eyebrow: eyebrow, title: title),
        const SizedBox(height: 17),
        ...items.map(
          (item) => _FooterTextLink(label: item, onTap: () => onItemTap(item)),
        ),
      ],
    );
  }
}

class _FooterSectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;

  const _FooterSectionHeading({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: GoCartFooter.footerAccentSoft,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(
            color: GoCartFooter.footerHeading,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _FooterCategoryLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterCategoryLink({required this.label, required this.onTap});

  @override
  State<_FooterCategoryLink> createState() => _FooterCategoryLinkState();
}

class _FooterCategoryLinkState extends State<_FooterCategoryLink> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: hovering ? 5 : 0,
                height: 5,
                margin: EdgeInsets.only(right: hovering ? 7 : 0),
                decoration: const BoxDecoration(
                  color: GoCartFooter.footerAccentSoft,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                widget.label,
                style: TextStyle(
                  color: hovering
                      ? GoCartFooter.footerHeading
                      : GoCartFooter.footerText,
                  fontSize: 12,
                  fontWeight: hovering ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterTextLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterTextLink({required this.label, required this.onTap});

  @override
  State<_FooterTextLink> createState() => _FooterTextLinkState();
}

class _FooterTextLinkState extends State<_FooterTextLink> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: hovering
                    ? GoCartFooter.footerAccentSoft
                    : GoCartFooter.footerMuted,
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: hovering
                      ? GoCartFooter.footerHeading
                      : GoCartFooter.footerText,
                  fontSize: 12,
                  fontWeight: hovering ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterSocialButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isInstagram;

  const _FooterSocialButton({
    required this.icon,
    required this.label,
    this.isInstagram = false,
  });

  @override
  State<_FooterSocialButton> createState() => _FooterSocialButtonState();
}

class _FooterSocialButtonState extends State<_FooterSocialButton> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: Material(
          color: hovering
              ? GoCartFooter.footerAccent.withValues(alpha: 0.24)
              : GoCartFooter.footerSurface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              if (widget.isInstagram && GoCartFooter.instagramUrl.isNotEmpty) {
                _showFooterInfoDialog(
                  context,
                  title: 'Instagram',
                  message:
                      'The official GoCart Instagram profile will open here once the app URL launcher is connected.',
                );
                return;
              }

              _showFooterInfoDialog(
                context,
                title: widget.label,
                message:
                    '${widget.label} is ready to be connected to the official GoCart profile.',
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hovering
                      ? GoCartFooter.footerAccent.withValues(alpha: 0.65)
                      : GoCartFooter.footerBorder,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 19,
                color: hovering
                    ? GoCartFooter.footerHeading
                    : GoCartFooter.footerText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLegalLinks extends StatelessWidget {
  const _FooterLegalLinks();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final item in GoCartFooter.legalItems)
          _FooterTextLink(
            label: item,
            onTap: () {
              _showFooterInfoDialog(
                context,
                title: item,
                message: _legalMessage(item),
              );
            },
          ),
      ],
    );
  }
}

String _customerCareMessage(String item) {
  switch (item) {
    case 'Help Center & FAQ':
      return 'Help and frequently asked questions will be available here. This is ready to be connected to a dedicated help page later.';
    case 'Track Your Order':
      return 'Order tracking will appear here once the GoCart order system is connected.';
    case 'Returns & Exchanges':
      return 'Return and exchange information will be added here when those policies are finalized.';
    case 'Shipping Policy':
      return 'Shipping information will be added here when the delivery policy is finalized.';
    case 'Contact Support':
      return 'Support contact details can be connected here once the official support channel is configured.';
    default:
      return 'This section is ready to be connected.';
  }
}

String _legalMessage(String item) {
  switch (item) {
    case 'Privacy Policy':
      return 'The GoCart privacy policy page can be connected here when the final policy is ready.';
    case 'Terms & Conditions':
      return 'The GoCart terms and conditions page can be connected here when the final terms are ready.';
    case 'Help & Support':
      return 'Help and support information can be connected here when the dedicated support page is ready.';
    default:
      return 'This page is ready to be connected.';
  }
}

void _showFooterInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFFFFF9FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          message,
          style: TextStyle(color: Colors.grey.shade700, height: 1.5),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: GoCartFooter.footerAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
