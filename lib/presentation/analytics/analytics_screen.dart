import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'dart:math';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsyncValue = ref.watch(transactionsStreamProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Spending', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: transactionsAsyncValue.when(
          data: (transactions) => _buildBody(context, transactions),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, __) => Center(child: Text('Error: $error')),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TransactionModel> transactions) {
    // 1. Compute 4 months of data (past 3 months + current month)
    final now = DateTime.now();
    final List<double> monthlyTotals = [0, 0, 0, 0];
    
    // Sort transactions into buckets based on how many months ago they occurred
    for (var tx in transactions) {
      if (tx.type == 'Expense' && tx.status != 'needs_review') {
        int monthDiff = (now.year - tx.timestamp.year) * 12 + now.month - tx.timestamp.month;
        if (monthDiff >= 0 && monthDiff < 4) {
          monthlyTotals[3 - monthDiff] += tx.amount; // 3 is current, 0 is 3 months ago
        }
      }
    }

    final maxY = monthlyTotals.isEmpty ? 1000.0 : max<double>(1000.0, monthlyTotals.reduce(max) * 1.5);
    final monthLabels = _getLast4MonthsLabels(now);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Top Chart Section wrapped in a Sliver constraint
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, right: 32, left: 16),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value >= 4) return const SizedBox.shrink();
                          final isHighlighted = value.toInt() == 2; // Always highlight the 3rd element visually
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Text(
                              monthLabels[value.toInt()],
                              style: TextStyle(
                                color: isHighlighted ? Theme.of(context).colorScheme.primary : Colors.grey,
                                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: maxY / 3,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const Text('0', style: TextStyle(color: Colors.grey, fontSize: 12));
                          return Text('${(value / 1000).toStringAsFixed(0)}k', style: const TextStyle(color: Colors.grey, fontSize: 12));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 3,
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        FlSpot(0, monthlyTotals[0]),
                        FlSpot(1, monthlyTotals[1]),
                        FlSpot(2, monthlyTotals[2]),
                        FlSpot(3, monthlyTotals[3]),
                      ],
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) => spot.x == 2, // Highlight peak explicitly
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: Theme.of(context).colorScheme.primary,
                            strokeWidth: 4,
                            strokeColor: Theme.of(context).scaffoldBackgroundColor,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '₹${spot.y.toStringAsFixed(0)}',
                            TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Bottom Dashboard Cards overlapping visual trick
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Inner Dark Budget Card
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Budget for ${monthLabels.last}', 
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('₹${monthlyTotals.last.toStringAsFixed(0)}', 
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: 0.7, 
                      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Activities Title
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                  child: const Text('Your Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                ),
              ],
            ),
          ),
        ),

        // Activity List cleanly unconstrained
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 120),
          sliver: _buildRecentTransactionsList(context, transactions),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsList(BuildContext context, List<TransactionModel> txs) {
    final recent = txs.where((t) => t.status != 'needs_review').toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (recent.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: Text('No transactions yet.', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final tx = recent[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  tx.type == 'Expense' ? Icons.shopping_bag_rounded : Icons.account_balance_rounded,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
              title: Text(tx.title.isNotEmpty ? tx.title : 'Payment', 
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              subtitle: Text(
                '${tx.timestamp.day} ${_getMonthName(tx.timestamp.month)} ${tx.timestamp.year}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${tx.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: tx.type == 'Expense' ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(tx.type, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          );
        },
        childCount: min(15, recent.length),
      ),
    );
  }

  List<String> _getLast4MonthsLabels(DateTime now) {
    List<String> labels = [];
    for (int i = 3; i >= 0; i--) {
      int prevMonth = now.month - i;
      if (prevMonth <= 0) prevMonth += 12;
      labels.add(_getMonthNameShort(prevMonth));
    }
    return labels;
  }

  String _getMonthNameShort(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month - 1];
  }
  
  String _getMonthName(int month) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month - 1];
  }
}
