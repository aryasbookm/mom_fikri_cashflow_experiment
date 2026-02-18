import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSharing = false;

  Future<void> _shareReceipt() async {
    if (_isSharing) {
      return;
    }
    setState(() {
      _isSharing = true;
    });

    try {
      final image = await _screenshotController.capture();
      if (image == null) {
        throw Exception('Gagal membuat gambar struk.');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'struk_${widget.transaction.id ?? 'tx'}.png'),
      );
      await file.writeAsBytes(image);
      await Share.shareXFiles([XFile(file.path)], text: 'Struk Mom Fiqry');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan struk: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<List<TransactionItemModel>> _loadItems() async {
    final txId = widget.transaction.id;
    if (txId == null) {
      return [];
    }
    final provider = context.read<TransactionProvider>();
    final items = await provider.getTransactionItems(txId);
    if (items.isNotEmpty) {
      return items;
    }
    final tx = widget.transaction;
    if (tx.productId != null && tx.quantity != null && tx.quantity! > 0) {
      final product = context.read<ProductProvider>().getById(tx.productId!);
      final unitPrice =
          tx.quantity == 0 ? tx.amount : (tx.amount ~/ tx.quantity!);
      return [
        TransactionItemModel(
          transactionId: txId,
          productId: tx.productId,
          productName: product?.name ?? 'Produk',
          unitPrice: unitPrice,
          quantity: tx.quantity!,
          total: tx.amount,
        ),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;
    final parsedDate = DateTime.tryParse(widget.transaction.date);
    final dateLabel = DateFormat(
      'dd MMMM y, HH:mm',
      'id_ID',
    ).format(parsedDate ?? DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Transaksi')),
      body: FutureBuilder<List<TransactionItemModel>>(
        future: _loadItems(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          final total = items.fold<int>(0, (sum, item) => sum + item.total);
          final displayTotal = total > 0 ? total : widget.transaction.amount;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSafeInset),
            children: [
              Screenshot(
                controller: _screenshotController,
                child: _ReceiptCard(
                  transaction: widget.transaction,
                  items: items,
                  currency: currency,
                  total: displayTotal,
                  dateLabel: dateLabel,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      widget.transaction.type != 'IN' || _isSharing
                          ? null
                          : _shareReceipt,
                  icon:
                      _isSharing
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.share),
                  label: const Text('Bagikan Struk'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.transaction,
    required this.items,
    required this.currency,
    required this.total,
    required this.dateLabel,
  });

  final TransactionModel transaction;
  final List<TransactionItemModel> items;
  final NumberFormat currency;
  final int total;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Mom Fiqry',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const Divider(),
          if (items.isEmpty)
            Text(
              transaction.description ?? 'Transaksi',
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          else
            Column(
              children:
                  items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${item.quantity} x ${currency.format(item.unitPrice)}',
                          ),
                          const SizedBox(width: 8),
                          Text(currency.format(item.total)),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                currency.format(total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Terima kasih atas pembeliannya!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
