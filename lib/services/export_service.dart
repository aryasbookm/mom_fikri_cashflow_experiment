import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';

class ExportService {
  static Future<void> exportTransactionsToExcel(
    List<TransactionModel> transactions, {
    required String filterLabel,
  }
  ) async {
    final excel = Excel.createExcel();
    final sheetName = excel.sheets.keys.isNotEmpty
        ? excel.sheets.keys.first
        : 'Sheet1';
    final sheet = excel[sheetName];

    final thinBorder = Border(borderStyle: BorderStyle.Thin);
    final rupiahFormat = NumFormat.custom(formatCode: '"Rp "#,##0');
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFFFE082'),
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final titleStyle = CellStyle(bold: true);
    final dataStyle = CellStyle(
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final qtyStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final nominalStyle = CellStyle(
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      numberFormat: rupiahFormat,
    );
    final footerLabelStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final footerValueStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      numberFormat: rupiahFormat,
    );
    final totalBoldStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Right,
      backgroundColorHex: ExcelColor.fromHexString('FFA5D6A7'),
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
      numberFormat: rupiahFormat,
    );

    sheet.setColumnWidth(0, 20.0);
    sheet.setColumnWidth(1, 8.0);
    sheet.setColumnWidth(2, 15.0);
    sheet.setColumnWidth(3, 20.0);
    sheet.setColumnWidth(4, 8.0);
    sheet.setColumnWidth(5, 15.0);
    sheet.setColumnWidth(6, 25.0);
    sheet.setColumnWidth(7, 35.0);
    sheet.setColumnWidth(8, 12.0);

    final titleCell = CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0);
    sheet.merge(
      titleCell,
      CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 0),
    );
    sheet.cell(titleCell)
      ..value = TextCellValue('LAPORAN KEUANGAN MOM FIQRY')
      ..cellStyle = titleStyle;

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = TextCellValue('Periode: $filterLabel');

    const headerRowIndex = 3;
    final headers = [
      'Tanggal',
      'Tipe',
      'Kategori',
      'Produk',
      'Jumlah',
      'Nominal',
      'Keterangan',
      'Rincian Item',
      'User',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRowIndex),
      );
      cell
        ..value = TextCellValue(headers[i])
        ..cellStyle = headerStyle;
    }

    final Database db = await DatabaseHelper.instance.database;
    final userRows = await db.query('users', columns: ['id', 'username']);
    final productRows = await db.query('products', columns: ['id', 'name']);
    final categoryRows = await db.query('categories', columns: ['id', 'name']);

    final userMap = {
      for (final row in userRows)
        row['id'] as int: row['username'] as String,
    };
    final productMap = {
      for (final row in productRows) row['id'] as int: row['name'] as String,
    };
    final categoryMap = {
      for (final row in categoryRows) row['id'] as int: row['name'] as String,
    };

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    print('Mengekspor ${transactions.length} transaksi...');

    int currentRow = headerRowIndex + 1;
    int totalIncome = 0;
    int totalExpense = 0;

    final txIds = transactions
        .where((tx) => tx.id != null)
        .map((tx) => tx.id!)
        .toList();
    final Map<int, List<TransactionItemModel>> itemsByTx = {};
    if (txIds.isNotEmpty) {
      final placeholders = List.filled(txIds.length, '?').join(', ');
      final itemRows = await db.query(
        'transaction_items',
        where: 'transaction_id IN ($placeholders)',
        whereArgs: txIds,
      );
      for (final row in itemRows) {
        final item = TransactionItemModel.fromMap(row);
        itemsByTx.putIfAbsent(item.transactionId, () => []).add(item);
      }
    }

    for (final tx in transactions) {
      final parsedDate = DateTime.tryParse(tx.date);
      final formattedDate = parsedDate == null
          ? tx.date
          : dateFormat.format(
              parsedDate.isUtc ? parsedDate.toLocal() : parsedDate,
            );

      if (tx.type == 'IN') {
        totalIncome += tx.amount;
      } else if (tx.type == 'OUT') {
        totalExpense += tx.amount;
      }

      final items = tx.id == null ? <TransactionItemModel>[] : (itemsByTx[tx.id!] ?? []);
      final itemSummary = items.isEmpty
          ? '-'
          : items
              .map((item) {
                final unit = currency.format(item.unitPrice);
                return '${item.productName} (${item.quantity}) @$unit';
              })
              .join(', ');

      final values = [
        TextCellValue(formattedDate),
        TextCellValue(tx.type),
        TextCellValue(tx.categoryName ?? categoryMap[tx.categoryId] ?? '-'),
        TextCellValue(
          tx.productId != null ? (productMap[tx.productId!] ?? '-') : '-',
        ),
        tx.quantity == null ? TextCellValue('-') : IntCellValue(tx.quantity!),
        IntCellValue(tx.amount),
        TextCellValue(
          tx.description?.isNotEmpty == true ? tx.description! : '-',
        ),
        TextCellValue(itemSummary),
        TextCellValue(userMap[tx.userId] ?? '-'),
      ];

      for (var i = 0; i < values.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: i,
            rowIndex: currentRow,
          ),
        );
        cell
          ..value = values[i]
          ..cellStyle = i == 5
              ? nominalStyle
              : i == 4
                  ? qtyStyle
                  : dataStyle;
      }
      currentRow += 1;
    }

    final footerRows = [
      ('TOTAL PEMASUKAN', totalIncome),
      ('TOTAL PENGELUARAN', totalExpense),
      ('TOTAL BERSIH', totalIncome - totalExpense),
    ];

    currentRow += 1;

    for (var i = 0; i < footerRows.length; i++) {
      final rowIndex = currentRow + i;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
      );
      final labelCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
      );
      final valueCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex),
      );
      final isNet = i == footerRows.length - 1;
      labelCell
        ..value = TextCellValue(footerRows[i].$1)
        ..cellStyle = isNet ? totalBoldStyle : footerLabelStyle;
      valueCell
        ..value = IntCellValue(footerRows[i].$2)
        ..cellStyle = isNet ? totalBoldStyle : footerValueStyle;
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Laporan_MomFiqry_$timestamp.xlsx';
    final filePath = p.join(tempDir.path, fileName);

    final file = File(filePath);
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Gagal membuat file Excel');
    }
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Laporan transaksi',
    );
  }
}
