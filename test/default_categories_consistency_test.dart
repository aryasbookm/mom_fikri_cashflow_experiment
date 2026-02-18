import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/constants/default_categories.dart';

void main() {
  group('DefaultCategories consistency', () {
    test('system categories contain expected baseline', () {
      final names = DefaultCategories.system.map((e) => e.name).toSet();
      expect(names.contains(DefaultCategories.incomePrimary), isTrue);
      expect(names.contains(DefaultCategories.incomeFallback), isTrue);
      expect(names.contains(DefaultCategories.expenseRawMaterials), isTrue);
      expect(names.contains(DefaultCategories.expenseOperational), isTrue);
      expect(names.contains(DefaultCategories.expenseSalary), isTrue);
    });

    test('system category pairs are unique by name+type', () {
      final keySet =
          DefaultCategories.system
              .map((e) => '${e.name.toLowerCase().trim()}|${e.type}')
              .toSet();
      expect(keySet.length, DefaultCategories.system.length);
    });

    test('isSystemCategoryName is case/space insensitive', () {
      expect(
        DefaultCategories.isSystemCategoryName('  penjualan kue '),
        isTrue,
      );
      expect(DefaultCategories.isSystemCategoryName('PEMASUKAN LAIN'), isTrue);
      expect(DefaultCategories.isSystemCategoryName('kategori bebas'), isFalse);
    });

    test('byType returns categories with matching type only', () {
      final income = DefaultCategories.byType('IN');
      final expense = DefaultCategories.byType('OUT');
      expect(income.every((e) => e.type == 'IN'), isTrue);
      expect(expense.every((e) => e.type == 'OUT'), isTrue);
    });
  });
}
