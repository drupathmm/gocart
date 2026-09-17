import 'package:flutter/material.dart';

class GoCartLogo extends StatelessWidget {
  final double width;
  final double? height;

  const GoCartLogo({super.key, required this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/gocart_logo.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}
