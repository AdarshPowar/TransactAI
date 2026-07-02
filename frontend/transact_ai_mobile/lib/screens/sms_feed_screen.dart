import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../theme/constants.dart';

class SmsFeedScreen extends StatefulWidget {
  final List<SmsAlert> smsAlerts;
  final Function(SmsAlert) onClassifySms;
  final Future<void> Function() onFetchSms;

  const SmsFeedScreen({
    super.key,
    required this.smsAlerts,
    required this.onClassifySms,
    required this.onFetchSms,
  });

  @override
  State<SmsFeedScreen> createState() => _SmsFeedScreenState();
}

class _SmsFeedScreenState extends State<SmsFeedScreen> {
  String _selectedFilter = 'All'; // 'All', 'Pending', 'Classified'
  bool _isScanning = false;

  Future<void> _handleScan() async {
    setState(() {
      _isScanning = true;
    });
    // Premium feedback simulation scan delay
    await Future.delayed(const Duration(milliseconds: 1200));
    await widget.onFetchSms();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Filter alerts
    final filteredAlerts = widget.smsAlerts.where((sms) {
      if (_selectedFilter == 'Pending') return !sms.isClassified;
      if (_selectedFilter == 'Classified') return sms.isClassified;
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'TRANSACT AI',
            style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2.0,
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SMS Inbox',
                style: theme.textTheme.headlineMedium,
              ),
              Row(
                children: [
                  if (_isScanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.cell_tower, color: Colors.white, size: 20),
                      tooltip: 'Fetch Mobile SMS',
                      onPressed: _handleScan,
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border, width: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.smsAlerts.where((s) => !s.isClassified).length} Pending',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filters row
          Row(
            children: ['All', 'Pending', 'Classified'].map((filter) {
              final isSelected = _selectedFilter == filter;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.black : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    }
                  },
                  selectedColor: Colors.white,
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.white : AppColors.border,
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Message Feed List
          Expanded(
            child: filteredAlerts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mail_outline_outlined,
                          size: 48,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No $_selectedFilter alerts in feed.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredAlerts.length,
                    itemBuilder: (context, index) {
                      final sms = filteredAlerts[index];
                      return _buildSmsCard(context, sms);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsCard(BuildContext context, SmsAlert sms) {
    final dateStr = DateFormat('MMM dd, yyyy • h:mm a').format(sms.timestamp);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: sms.isClassified ? AppColors.border : AppColors.borderBright,
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info: Sender, Timestamp, Status Tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      sms.sender[0],
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sms.sender,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Message Body (Monospace font style for alert logs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sms.body,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status Badge
              Row(
                children: [
                  Icon(
                    sms.isClassified ? Icons.check_circle_outline : Icons.pending_outlined,
                    size: 14,
                    color: sms.isClassified ? AppColors.categoryGroceries : Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    sms.isClassified ? 'Classified' : 'Pending Review',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sms.isClassified ? AppColors.categoryGroceries : Colors.amber,
                    ),
                  ),
                ],
              ),

              // CTA Action
              if (!sms.isClassified) ...[
                ElevatedButton(
                  onPressed: () => widget.onClassifySms(sms),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Classify',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 10),
                    ],
                  ),
                ),
              ] else ...[
                // Shows a linked badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 10, color: AppColors.textSecondary.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      const Text(
                        'Linked',
                        style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
