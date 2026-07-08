import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../theme/constants.dart';
import '../widgets/donut_chart.dart';
import '../services/api_service.dart';

class InsightsScreen extends StatefulWidget {
  final List<Transaction> transactions;

  const InsightsScreen({
    super.key,
    required this.transactions,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.getSummary();
      if (mounted) setState(() { _summary = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load insights.'; _loading = false; });
    }
  }
    
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, color: AppColors.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadSummary, child: const Text('Retry')),
          ],
        ),
      );
    }

    final categorySummary = (_summary?['category_summary'] as Map<String, dynamic>?) ?? {};
    final totalSpent = (_summary?['total_spent'] as num?)?.toDouble() ?? 0.0;

    final Map<String, double> categorySums = categorySummary.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    final Map<String, int> categoryCounts = {
  for (var entry in categorySums.entries)
    entry.key: 1, // default 1 per category since /summary doesn't return counts
};

    final List<DonutChartData> chartData = [];
    categorySums.forEach((cat, amt) {
      chartData.add(DonutChartData(
        label: cat,
        amount: amt,
        color: AppColors.getCategoryColor(cat),
      ));
    });

    chartData.sort((a, b) => b.amount.compareTo(a.amount));

    return RefreshIndicator(
      onRefresh: _loadSummary,
      color: Colors.white,
      backgroundColor: AppColors.surface,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TRANSACT AI',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2.0,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Spending Insights',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            
            Center(
              child: totalSpent > 0
                  ? DonutChart(
                      data: chartData,
                      totalAmount: totalSpent,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.pie_chart_outline,
                            size: 40,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No transaction data available',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 40),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SPENDING BREAKDOWN',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.5,
                        color: AppColors.textSecondary,
                      ),
                ),
                Text(
                  'Rs{chartData.length} categories',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (chartData.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'Add classifications to see breakdown details.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              )
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: chartData.length,
                itemBuilder: (context, index) {
                  final item = chartData[index];
                  final count = categoryCounts[item.label] ?? 0;
                  final percentage = totalSpent > 0 ? (item.amount / totalSpent * 100).round() : 0;
                  
                  return _buildCategoryDetailRow(
                    context,
                    item.label,
                    item.amount,
                    percentage,
                    count,
                    item.color,
                  );
                },
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
      ), // RefreshIndicator
    );
  }

  Widget _buildCategoryDetailRow(
    BuildContext context,
    String label,
    double amount,
    int percentage,
    int count,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? "transaction" : "transactions"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹{amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rspercentage%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}