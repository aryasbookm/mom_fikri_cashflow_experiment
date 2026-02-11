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
          return CircleAvatar(
            radius: radius,
            backgroundImage: FileImage(file),
            backgroundColor: Colors.grey.shade200,
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
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFF3E5E5),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF8D1B3D),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
