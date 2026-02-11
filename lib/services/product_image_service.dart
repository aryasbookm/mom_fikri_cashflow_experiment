import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProductImageService {
  ProductImageService._();

  static const String _directoryName = 'product_images';

  static Future<Directory> _getImageDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(docsDir.path, _directoryName));
    if (!imageDir.existsSync()) {
      imageDir.createSync(recursive: true);
    }
    return imageDir;
  }

  static Future<File> _getImageFile(int productId) async {
    final imageDir = await _getImageDirectory();
    return File(p.join(imageDir.path, 'prod_$productId.jpg'));
  }

  static Future<File?> getProductImage(int productId) async {
    try {
      final file = await _getImageFile(productId);
      if (!file.existsSync()) {
        return null;
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveProductImage({
    required int productId,
    required XFile sourceImage,
  }) async {
    try {
      final target = await _getImageFile(productId);
      await FileImage(target).evict();
      if (target.existsSync()) {
        await target.delete();
      }
      await File(sourceImage.path).copy(target.path);
      await FileImage(target).evict();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteProductImage(int productId) async {
    try {
      final target = await _getImageFile(productId);
      await FileImage(target).evict();
      if (!target.existsSync()) {
        return true;
      }
      await target.delete();
      await FileImage(target).evict();
      return true;
    } catch (_) {
      return false;
    }
  }
}
