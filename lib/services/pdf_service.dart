import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';

class PdfService {
  static Future<void> generateReport({
    required String monthLabel,
    required List<TransactionModel> financialData,
    required List<TransactionModel> wasteData,
    required int totalIncome,
    required int totalExpense,
    required Map<int, List<TransactionItemModel>> itemsByTransaction,
  }) async {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final nowLabel = DateFormat('dd MMMM y, HH:mm', 'id_ID')
        .format(DateTime.now());
    final balance = totalIncome - totalExpense;

    final baseFont = await PdfGoogleFonts.openSansRegular();
    final boldFont = await PdfGoogleFonts.openSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Text(
              'Laporan Keuangan Mom Fiqry',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Periode: $monthLabel'),
            pw.Text('Tanggal Cetak: $nowLabel'),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(6),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _summaryItem(
                    label: 'Total Pemasukan',
                    value: currency.format(totalIncome),
                    color: PdfColors.green700,
                  ),
                  _summaryItem(
                    label: 'Total Pengeluaran',
                    value: currency.format(totalExpense),
                    color: PdfColors.red700,
                  ),
                  _summaryItem(
                    label: 'Saldo',
                    value: currency.format(balance),
                    color: PdfColors.blue700,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Section A - Laporan Keuangan',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            _financialTable(
              financialData: financialData,
              currency: currency,
              itemsByTransaction: itemsByTransaction,
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Section B - Laporan Barang Rusak/Waste',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            _wasteTable(wasteData),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static pw.Widget _summaryItem({
    required String label,
    required String value,
    required PdfColor color,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _financialTable({
    required List<TransactionModel> financialData,
    required NumberFormat currency,
    required Map<int, List<TransactionItemModel>> itemsByTransaction,
  }) {
    if (financialData.isEmpty) {
      return pw.Text('Belum ada transaksi pada periode ini.');
    }

    return pw.Table.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellPadding: const pw.EdgeInsets.all(6),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      data: [
        ['Tanggal', 'Keterangan', 'Masuk', 'Keluar'],
        ...financialData.map((tx) {
          final dateLabel = _formatDate(tx.date);
          final description =
              tx.description ?? tx.categoryName ?? 'Transaksi';
          final items = tx.id == null
              ? <TransactionItemModel>[]
              : (itemsByTransaction[tx.id!] ?? []);
          final itemSummary = items.isEmpty
              ? ''
              : items
                  .map((item) {
                    final unit = currency.format(item.unitPrice);
                    return '${item.productName} (${item.quantity}) @$unit';
                  })
                  .join(', ');
          final details =
              itemSummary.isEmpty ? description : '$description\n$itemSummary';
          final income = tx.type == 'IN' ? currency.format(tx.amount) : '-';
          final expense = tx.type == 'OUT' ? currency.format(tx.amount) : '-';
          return [dateLabel, details, income, expense];
        }),
      ],
    );
  }

  static pw.Widget _wasteTable(List<TransactionModel> wasteData) {
    if (wasteData.isEmpty) {
      return pw.Text('Belum ada barang rusak pada periode ini.');
    }

    return pw.Table.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellPadding: const pw.EdgeInsets.all(6),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(5),
        2: pw.FlexColumnWidth(1),
      },
      data: [
        ['Tanggal', 'Nama/Deskripsi', 'Qty'],
        ...wasteData.map((tx) {
          final dateLabel = _formatDate(tx.date);
          final description = tx.description ?? 'Barang rusak';
          final qty = tx.quantity ?? 0;
          return [dateLabel, description, qty.toString()];
        }),
      ],
    );
  }

  static String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(parsed);
  }
}
