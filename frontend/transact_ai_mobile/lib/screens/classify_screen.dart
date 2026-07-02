import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../theme/constants.dart';
import '../services/api_service.dart';

class ClassifyScreen extends StatefulWidget {
  final Function(Transaction) onAddTransaction;
  final String? initialText;

  const ClassifyScreen({
    super.key,
    required this.onAddTransaction,
    this.initialText,
  });

  @override
  State<ClassifyScreen> createState() => _ClassifyScreenState();
}

class _ClassifyScreenState extends State<ClassifyScreen> {
  final _controller = TextEditingController();
  final _newCatController = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _classifyResult;
  bool _isAutoSaved = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _newCatController.dispose();
    super.dispose();
  }

  Future<void> _classify() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _classifyResult = null;
      _isAutoSaved = false;
    });

    try {
      final result = await ApiService.classify(msg);
      setState(() {
        _classifyResult = result;
        _isAutoSaved =
            result['status'] == 'saved' || result['status'] == 'classified';
      });
      if (_isAutoSaved) _notifyParent(result);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } catch (e) {
      setState(() => _error =
          'Cannot reach backend. Is the Python server running?\n$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveManual(String chosenCategory) async {
    final r = _classifyResult!;
    setState(() { _loading = true; _error = null; });
    try {
      final saved = await ApiService.manualCategory(
        message: _controller.text.trim(),
        category: chosenCategory,
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        receiver: r['receiver'] ?? '',
        cleanText: r['clean_text'] ?? '',
      );
      setState(() {
        _classifyResult = {...r, 'status': 'saved', 'category': chosenCategory};
        _isAutoSaved = true;
      });
      _notifyParent(saved);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _notifyParent(Map<String, dynamic> result) {
    // Convert API result to Transaction model for main.dart compatibility
    final txn = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      merchant: result['receiver'] ?? result['receiver_name'] ?? 'Unknown',
      amount: (result['amount'] as num?)?.toDouble() ?? 0.0,
      category: result['category'] ?? result['predicted_category'] ?? 'Other',
      date: DateTime.now(),
      strategy: ClassificationStrategy.ml,
      confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
      rawSms: _controller.text.trim(),
    );
    widget.onAddTransaction(txn);
  }

  Future<void> _addNewCategory() async {
    final newCat = _newCatController.text.trim();
    if (newCat.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.addCategory(newCat);
      await _saveManual(newCat);
      _newCatController.clear();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showAddCategoryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Category',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _newCatController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Pet Care, Rent, EMI',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addNewCategory,
                child: const Text('Add & Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('TRANSACT AI',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2.0,
                  color: AppColors.textSecondary,
                )),
            const SizedBox(height: 4),
            Text('Classify SMS', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 20),

            // Input
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    'Paste bank SMS e.g. Rs. 500 debited via UPI to Swiggy...',
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _classify,
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_loading ? 'Classifying…' : 'Classify with AI'),
              ),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(fontSize: 12,
                              color: Colors.red))),
                ]),
              ),
            ],

            // Result
            if (_classifyResult != null) ...[
              const SizedBox(height: 20),
              _isAutoSaved
                  ? _AutoSavedCard(result: _classifyResult!)
                  : _LowConfidenceCard(
                      result: _classifyResult!,
                      onPickCategory: _saveManual,
                      onAddNew: _showAddCategoryDialog,
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutoSavedCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _AutoSavedCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final category = result['category'] ?? result['predicted_category'] ?? 'Unknown';
    final confidence =
        ((result['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final amount = (result['amount'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF534AB7).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF534AB7).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle, color: Color(0xFF534AB7), size: 18),
          const SizedBox(width: 8),
          const Text('Auto-categorized',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF534AB7))),
          const Spacer(),
          Text('${confidence.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D9E75))),
        ]),
        const SizedBox(height: 12),
        _Row('Category', category),
        if (amount > 0) _Row('Amount', '₹${amount.toStringAsFixed(2)}'),
        if ((result['receiver'] ?? result['receiver_name'] ?? '')
            .toString()
            .isNotEmpty)
          _Row('Receiver',
              result['receiver'] ?? result['receiver_name'] ?? ''),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: confidence / 100,
          backgroundColor: AppColors.border,
          color: const Color(0xFF534AB7),
          borderRadius: BorderRadius.circular(99),
          minHeight: 4,
        ),
      ]),
    );
  }

  Widget _Row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ]),
      );
}

class _LowConfidenceCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final Future<void> Function(String) onPickCategory;
  final VoidCallback onAddNew;

  const _LowConfidenceCard({
    required this.result,
    required this.onPickCategory,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final options = (result['options'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final confidence =
        ((result['confidence'] as num?)?.toDouble() ?? 0) * 100;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Text(
            'Low confidence (${confidence.toStringAsFixed(0)}%). Pick a category:',
            style: const TextStyle(fontSize: 12, color: Colors.amber),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      ...options.map((cat) => _OptionTile(
            label: cat,
            onTap: () => onPickCategory(cat),
          )),
      const SizedBox(height: 4),
      _OptionTile(label: '+ Add new category', isNew: true, onTap: onAddNew),
    ]);
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isNew;
  final VoidCallback onTap;
  const _OptionTile(
      {required this.label, required this.onTap, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isNew
              ? const Color(0xFF534AB7).withOpacity(0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isNew
                  ? const Color(0xFF534AB7).withOpacity(0.4)
                  : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isNew ? FontWeight.w600 : FontWeight.w400,
                color: isNew
                    ? const Color(0xFF534AB7)
                    : AppColors.textPrimary)),
      ),
    );
  }
}