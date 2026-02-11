import 'dart:io';

import 'package:flutter/material.dart';

import '../services/product_image_service.dart';

class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    required this.productId,
    required this.productName,
    this.radius = 20,
  });

  final int? productId;
  final String productName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (productId == null) {
      return _fallbackAvatar();
    }

    return FutureBuilder<File?>(
      future: ProductImageService.getProductImage(productId!),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(_cornerRadius()),
            child: SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: Image.file(
                file,
                fit: BoxFit.cover,
              ),
            ),
          );
        }
        return _fallbackAvatar();
      },
    );
  }

  Widget _fallbackAvatar() {
    final initial =
        productName.trim().isEmpty
            ? '?'
            : productName.trim().substring(0, 1).toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5E5),
        borderRadius: BorderRadius.circular(_cornerRadius()),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF8D1B3D),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  double _cornerRadius() {
    return (radius * 0.35).clamp(8.0, 12.0);
  }
}
