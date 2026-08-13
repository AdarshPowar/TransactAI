import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../theme/constants.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final List<Transaction> transactions;
  final Function(Transaction) onUpdateTransaction;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final int activeAvatarIndex;
  final Function(int) onAvatarChanged;

  const DashboardScreen({
    super.key,
    required this.transactions,
    required this.onUpdateTransaction,
    required this.onSync,
    required this.onLogout,
    required this.activeAvatarIndex,
    required this.onAvatarChanged,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _apiTransactions = [];
  bool _apiLoading = true;
  bool _apiError = false;

  // Month filter — null means "All"
  DateTime? _selectedMonth;

  // Filtered transactions based on selected month
  List<Map<String, dynamic>> get _filteredTransactions {
    if (_selectedMonth == null) return _apiTransactions;
    return _apiTransactions.where((tx) {
      final raw = tx['txn_time'] ?? tx['created_at'] ?? '';
      if (raw.isEmpty) return false;
      try {
        final date = DateTime.parse(raw.toString());
        return date.year == _selectedMonth!.year &&
            date.month == _selectedMonth!.month;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  // Get unique months from transactions for the filter dropdown
  List<DateTime> get _availableMonths {
    final months = <DateTime>{};
    for (final tx in _apiTransactions) {
      final raw = tx['txn_time'] ?? tx['created_at'] ?? '';
      if (raw.isEmpty) continue;
      try {
        final date = DateTime.parse(raw.toString());
        months.add(DateTime(date.year, date.month));
      } catch (_) {}
    }
    final list = months.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  void refreshData() {
    _loadFromApi();
  }

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

  Future<void> _loadFromApi() async {
    try {
      final results = await Future.wait([
        ApiService.getSummary(),
        ApiService.getTransactions(limit: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0];
        final txList = results[1]['results'] as List<dynamic>? ?? [];
        _apiTransactions =
            txList.map((t) => t as Map<String, dynamic>).toList();
        _apiLoading = false;
        _apiError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiLoading = false;
        _apiError = true;
      });
    }
  }

  String _monthLabel(DateTime month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '\${months[month.month - 1]} \${month.year}';
  }

  void _showMonthPicker(BuildContext context) {
    final months = _availableMonths;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderBright,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'FILTER BY MONTH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined,
                color: AppColors.textSecondary, size: 20),
            title: const Text('All Transactions',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            trailing: _selectedMonth == null
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
            onTap: () {
              setState(() => _selectedMonth = null);
              Navigator.pop(context);
            },
          ),
          const Divider(height: 1, color: AppColors.border),
          ...months.map((month) {
            final isSelected = _selectedMonth?.year == month.year &&
                _selectedMonth?.month == month.month;
            return ListTile(
              leading: const Icon(Icons.calendar_month_outlined,
                  color: AppColors.textSecondary, size: 20),
              title: Text(_monthLabel(month),
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
              onTap: () {
                setState(() => _selectedMonth = month);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

    @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use API transactions if available, otherwise fall back to mock
    final displayTransactions = _apiError || _apiLoading
        ? widget.transactions
        : null;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFromApi,
        color: const Color(0xFF534AB7),
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TRANSACT AI',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 2.0,
                          color: AppColors.textSecondary,
                        )),
                    Row(children: [
                      IconButton(
                        icon: const Icon(Icons.sync, size: 20),
                        onPressed: () {
                          _loadFromApi();
                          widget.onSync();
                        },
                        tooltip: 'Sync',
                      ),
                      GestureDetector(
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          activeAvatarIndex: widget.activeAvatarIndex,
          onAvatarChanged: widget.onAvatarChanged,
          onLogout: widget.onLogout,
        ),
      ),
    );
  },
  child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.surface,
                          child: Text(
                            ['A', 'B', 'C', 'D'][widget.activeAvatarIndex % 4],
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),

            // ── Summary Card from API ─────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _apiLoading
                    ? _buildLoadingCard()
                    : _apiError
                        ? _buildLocalSummary(theme)
                        : _buildApiSummary(theme),
              ),
            ),

            // ── Transactions Header + Month Filter ────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Transactions',
                        style: theme.textTheme.titleMedium),
                    // Month filter dropdown
                    if (!_apiLoading && !_apiError && _apiTransactions.isNotEmpty)
                      GestureDetector(
                        onTap: () => _showMonthPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(
                                color: _selectedMonth != null
                                    ? Colors.white
                                    : AppColors.border,
                                width: 1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 13,
                                color: _selectedMonth != null
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _selectedMonth != null
                                    ? _monthLabel(_selectedMonth!)
                                    : 'All',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedMonth != null
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(Icons.arrow_drop_down,
                                  size: 16,
                                  color: _selectedMonth != null
                                      ? Colors.white
                                      : AppColors.textSecondary),
                            ],
                          ),
                        ),
                      )
                    else if (_apiError)
                      const Text('(local)',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // Filtered count hint
            if (_selectedMonth != null && !_apiLoading && !_apiError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredTransactions.length} transactions in ${_monthLabel(_selectedMonth!)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _selectedMonth = null),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // API transactions list
            if (!_apiLoading && !_apiError && _filteredTransactions.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      _ApiTransactionTile(tx: _filteredTransactions[i]),
                  childCount: _filteredTransactions.length,
                ),
              )
            else if (!_apiLoading && !_apiError &&
                _apiTransactions.isNotEmpty &&
                _filteredTransactions.isEmpty)
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No transactions in this month.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              )
            else if (displayTransactions != null &&
                displayTransactions.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _LocalTransactionTile(
                    txn: displayTransactions[i],
                    onUpdate: widget.onUpdateTransaction,
                  ),
                  childCount: displayTransactions.length,
                ),
              )
            else
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No transactions yet.\nClassify an SMS to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() => Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF534AB7)), 
        ),
      );

  Widget _buildApiSummary(ThemeData theme) {
    final total = (_summary!['total_spent'] as num?)?.toDouble() ?? 0;
    final count = _summary!['total_transactions'] ?? 0;
    final topCat = _summary!['highest_spending_category'] ?? '—';
    final cats =
        _summary!['category_summary'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Total Spent',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text('₹${total.toStringAsFixed(2)}',
            style: theme.textTheme.headlineMedium
                ?.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          _StatChip('$count txns'),
          const SizedBox(width: 8),
          _StatChip(topCat),
        ]),
        if (cats.isNotEmpty) ...[
          const SizedBox(height: 14),
          _CategoryBar(cats: cats),
        ],
      ]),
    );
  }

  Widget _buildLocalSummary(ThemeData theme) {
    final total =
        widget.transactions.fold<double>(0, (s, t) => s + t.amount);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Total Spent',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('offline',
                style: TextStyle(fontSize: 9, color: Colors.orange)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('₹${total.toStringAsFixed(2)}',
            style: theme.textTheme.headlineMedium
                ?.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('${widget.transactions.length} local transactions',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      );
}

class _CategoryBar extends StatelessWidget {
  final Map<String, dynamic> cats;
  const _CategoryBar({required this.cats});

  static const _colors = [
    Color(0xFF534AB7), Color(0xFF1D9E75), Color(0xFFD85A30),
    Color(0xFFBA7517), Color(0xFFB4B2A9),
  ];

  @override
  Widget build(BuildContext context) {
    final total =
        cats.values.fold<double>(0, (s, v) => s + (v as num).toDouble());
    final entries = cats.entries.toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(
          children: List.generate(entries.length, (i) {
            final pct = (entries[i].value as num).toDouble() / total;
            return Flexible(
                flex: (pct * 100).round(),
                child: Container(color: _colors[i % _colors.length]));
          }),
        ),
      ),
    );
  }
}

class _ApiTransactionTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _ApiTransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final category = tx['predicted_category'] ?? tx['category'] ?? 'Other';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final receiver = tx['receiver_name'] ?? tx['receiver'] ?? '—';
    final ts = tx['timestamp'] != null
        ? DateTime.tryParse(tx['timestamp'].toString())
        : null;
    final dateStr = ts != null ? '${ts.day}/${ts.month}' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF534AB7).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.receipt_long_outlined,
              color: Color(0xFF534AB7), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(receiver,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              Text('$category · $dateStr',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
        ),
        Text('₹${amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ]),
    );
  }
}

class _LocalTransactionTile extends StatelessWidget {
  final Transaction txn;
  final Function(Transaction) onUpdate;
  const _LocalTransactionTile(
      {required this.txn, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.getCategoryColor(txn.category).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.receipt_long_outlined,
              color: AppColors.getCategoryColor(txn.category), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(txn.merchant,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              Text('${txn.category} · ${txn.date.day}/${txn.date.month}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
        ),
        Text('₹${txn.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ]),
    );
  }
}