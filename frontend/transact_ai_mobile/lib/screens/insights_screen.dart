import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../theme/constants.dart';
import '../widgets/donut_chart.dart';

class InsightsScreen extends StatelessWidget {
  final List<Transaction> transactions;

  const InsightsScreen({
    super.key,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final totalSpent = transactions.fold<double>(0, (sum, t) => sum + t.amount);
    
    final Map<String, double> categorySums = {};
    final Map<String, int> categoryCounts = {};
    
    for (var t in transactions) {
      categorySums[t.category] = (categorySums[t.category] ?? 0) + t.amount;
      categoryCounts[t.category] = (categoryCounts[t.category] ?? 0) + 1;
    }
    
    final List<DonutChartData> chartData = [];
    categorySums.forEach((cat, amt) {
      chartData.add(DonutChartData(
        label: cat,
        amount: amt,
        color: AppColors.getCategoryColor(cat),
      ));
    });
    
    chartData.sort((a, b) => b.amount.compareTo(a.amount));

    return SingleChildScrollView(
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
                  '${chartData.length} categories',
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
                '-\$${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$percentage%',
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
