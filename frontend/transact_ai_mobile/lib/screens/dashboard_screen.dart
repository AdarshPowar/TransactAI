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

            // ── Transactions ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Transactions',
                        style: theme.textTheme.titleMedium),
                    if (_apiError)
                      const Text('(local)',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // API transactions list
            if (!_apiLoading && !_apiError && _apiTransactions.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ApiTransactionTile(tx: _apiTransactions[i]),
                  childCount: _apiTransactions.length,
                ),
              )
            // Fallback: local mock transactions
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