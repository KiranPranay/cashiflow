import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cashi_flow/presentation/core/theme.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'dart:math';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsyncValue = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Burn Rate',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.electricMint,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your spending over the last 7 days',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 48),
              Expanded(
                child: transactionsAsyncValue.when(
                  data: (transactions) => _buildChart(transactions),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, __) => Center(child: Text('Error: $error')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(List<TransactionModel> transactions) {
    // Process transactions into daily sums for the last 7 days
    final now = DateTime.now();
    final List<double> dailyTotals = List.filled(7, 0.0);
    
    for (var tx in transactions) {
      if (tx.type.toLowerCase() == 'sent') {
        final diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(tx.timestamp.year, tx.timestamp.month, tx.timestamp.day))
            .inDays;
        if (diff >= 0 && diff < 7) {
          // Index 0 means 'today'
          dailyTotals[diff] += tx.amount;
        }
      }
    }
    
    // Reverse so index 0 is 7 days ago and index 6 is today
    final chartData = dailyTotals.reversed.toList();
    
    final maxY = chartData.isEmpty ? 1000.0 : max<double>(1000.0, chartData.reduce(max) * 1.2);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppTheme.surfaceColor,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '₹${rod.toY.toStringAsFixed(0)}',
                const TextStyle(color: AppTheme.electricMint, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                // value is 0..6
                final daysAgo = 6 - value.toInt();
                final date = now.subtract(Duration(days: daysAgo));
                final dayLabel = _getShortWeekday(date.weekday);
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    daysAgo == 0 ? 'Today' : dayLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false), // Hide vertical axis
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4 == 0 ? 1 : maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(
          7,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: chartData[i],
                color: AppTheme.electricMint,
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: AppTheme.surfaceColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getShortWeekday(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}

