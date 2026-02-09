import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/pdf_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => ReportScreenState();
}

class ReportScreenState extends State<ReportScreen> {
  bool _showExpense = true;
  DateTime _selectedDate = DateTime.now();
  bool _isExporting = false;

  bool get isExporting => _isExporting;

  @override
  void initState() {
    super.initState();
    Provider.of<TransactionProvider>(context, listen: false).loadTransactions();
  }

  Future<void> exportPdf() async {
    if (_isExporting) {
      return;
    }
    setState(() {
      _isExporting = true;
    });

    try {
      final provider = context.read<TransactionProvider>();
      final monthLabel = DateFormat('MMMM y', 'id_ID').format(_selectedDate);
      final financial = <TransactionModel>[];
      final waste = <TransactionModel>[];
      for (final tx in provider.transactions) {
        final date = DateTime.tryParse(tx.date);
        if (date == null ||
            date.year != _selectedDate.year ||
            date.month != _selectedDate.month) {
          continue;
        }
        if (tx.type == 'WASTE') {
          waste.add(tx);
        } else if (tx.type == 'IN' || tx.type == 'OUT') {
          financial.add(tx);
        }
      }
      final totalIncome = financial
          .where((tx) => tx.type == 'IN')
          .fold<int>(0, (sum, tx) => sum + tx.amount);
      final totalExpense = financial
          .where((tx) => tx.type == 'OUT')
          .fold<int>(0, (sum, tx) => sum + tx.amount);

      await PdfService.generateReport(
        monthLabel: monthLabel,
        financialData: financial,
        wasteData: waste,
        totalIncome: totalIncome,
        totalExpense: totalExpense,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export PDF: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final monthLabel = DateFormat('MMMM y', 'id_ID').format(_selectedDate);

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final last7Days = provider.getLast7DaysCashflow();
        final hasTrendData = last7Days.any(
          (entry) => entry.income > 0 || entry.expense > 0,
        );
        final stats = _showExpense
            ? provider.getExpenseStatistics(date: _selectedDate)
            : provider.getIncomeStatistics(date: _selectedDate);
        final total = stats.fold<double>(
          0,
          (sum, item) => sum + (item['total'] as double),
        );
        final compact = NumberFormat.compact(locale: 'id_ID');
        final wasteMonthlyQty = provider.transactions.where((tx) {
          if (tx.type != 'WASTE') {
            return false;
          }
          final date = DateTime.tryParse(tx.date);
          if (date == null) {
            return false;
          }
          return date.year == _selectedDate.year &&
              date.month == _selectedDate.month;
        }).fold<int>(0, (sum, tx) => sum + (tx.quantity ?? 0));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tren 7 Hari Terakhir',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (!hasTrendData)
                const _EmptyState(
                  label: 'Belum ada transaksi 7 hari terakhir',
                )
              else
                _CashflowChart(
                  data: last7Days,
                  compactFormat: compact,
                ),
              const SizedBox(height: 24),
              Text(
                _showExpense ? 'Analisis Pengeluaran' : 'Analisis Pemasukan',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedDate =
                            DateTime(_selectedDate.year, _selectedDate.month - 1);
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedDate =
                            DateTime(_selectedDate.year, _selectedDate.month + 1);
                      });
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ToggleButton(
                      label: 'Pemasukan',
                      isActive: !_showExpense,
                      activeColor: Colors.green,
                      onTap: () {
                        setState(() {
                          _showExpense = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToggleButton(
                      label: 'Pengeluaran',
                      isActive: _showExpense,
                      activeColor: Colors.orange,
                      onTap: () {
                        setState(() {
                          _showExpense = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (stats.isEmpty)
                _EmptyState(
                  label: _showExpense
                      ? 'Belum ada data pengeluaran'
                      : 'Belum ada data pemasukan',
                )
              else
                _ChartCard(
                  total: total,
                  sections: stats
                      .map(
                        (item) => PieChartSectionData(
                          color: item['color'] as Color,
                          value: item['total'] as double,
                          radius: 70,
                          title: total <= 0
                              ? ''
                              : ((item['total'] as double) / total * 100 >= 8)
                                  ? '${((item['total'] as double) / total * 100).toStringAsFixed(0)}%'
                                  : '',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 16),
                _LegendCard(
                  items: stats,
                  total: total,
                  currency: currency,
                ),
              ],
              const SizedBox(height: 16),
              _WasteSummaryCard(totalQty: wasteMonthlyQty),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? activeColor : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.sections,
    required this.total,
  });

  final List<PieChartSectionData> sections;
  final double total;

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
      child: SizedBox(
        height: 240,
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 40,
            sections: sections,
          ),
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({
    required this.items,
    required this.total,
    required this.currency,
  });

  final List<Map<String, dynamic>> items;
  final double total;
  final NumberFormat currency;

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
        children: items.map((item) {
          final color = item['color'] as Color;
          final name = item['name'] as String;
          final value = item['total'] as double;
          final percent = total <= 0 ? 0 : (value / total * 100);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${currency.format(value)} (${percent.toStringAsFixed(0)}%)',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CashflowChart extends StatelessWidget {
  const _CashflowChart({
    required this.data,
    required this.compactFormat,
  });

  final List<DailyCashflow> data;
  final NumberFormat compactFormat;

  String _dayLabel(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Sen';
      case DateTime.tuesday:
        return 'Sel';
      case DateTime.wednesday:
        return 'Rab';
      case DateTime.thursday:
        return 'Kam';
      case DateTime.friday:
        return 'Jum';
      case DateTime.saturday:
        return 'Sab';
      case DateTime.sunday:
        return 'Min';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final int maxValue = data.fold<int>(
      0,
      (max, entry) => [
        max,
        entry.income,
        entry.expense,
      ].reduce((a, b) => a > b ? a : b),
    );
    final double maxY = maxValue == 0 ? 1 : maxValue * 1.2;
    final List<FlSpot> incomeSpots = [];
    final List<FlSpot> expenseSpots = [];

    for (int i = 0; i < data.length; i++) {
      final entry = data[i];
      incomeSpots.add(FlSpot(i.toDouble(), entry.income.toDouble()));
      expenseSpots.add(FlSpot(i.toDouble(), entry.expense.toDouble()));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              _ChartLegend(color: Colors.green, label: 'Pemasukan'),
              SizedBox(width: 16),
              _ChartLegend(color: Colors.red, label: 'Pengeluaran'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData(
                  left: true,
                  right: false,
                  top: false,
                  bottom: false,
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.black.withOpacity(0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withOpacity(0.12),
                    ),
                    left: BorderSide(
                      color: Colors.black.withOpacity(0.12),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) {
                          return const Text('0');
                        }
                        return Text(compactFormat.format(value));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _dayLabel(data[index].date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: incomeSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: Colors.green,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withOpacity(0.12),
                    ),
                  ),
                  LineChartBarData(
                    spots: expenseSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: Colors.red,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.red.withOpacity(0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pie_chart, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _WasteSummaryCard extends StatelessWidget {
  const _WasteSummaryCard({required this.totalQty});

  final int totalQty;

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
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.red.withOpacity(0.12),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total Waste Bulan Ini',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$totalQty item',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
