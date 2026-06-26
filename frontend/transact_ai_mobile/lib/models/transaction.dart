import 'dart:math';

enum ClassificationStrategy { rule, ml, hybrid }

class Transaction {
  final String id;
  final String merchant;
  final double amount;
  String category;
  final DateTime date;
  final ClassificationStrategy strategy;
  final double confidence;
  final String? rawSms;
  bool isConfirmed;

  Transaction({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.category,
    required this.date,
    required this.strategy,
    required this.confidence,
    this.rawSms,
    this.isConfirmed = false,
  });

  String get strategyLabel {
    switch (strategy) {
      case ClassificationStrategy.rule:
        return 'Rule';
      case ClassificationStrategy.ml:
        return 'ML';
      case ClassificationStrategy.hybrid:
        return 'Hybrid';
    }
  }

  // Clone with changes
  Transaction copyWith({
    String? category,
    bool? isConfirmed,
  }) {
    return Transaction(
      id: id,
      merchant: merchant,
      amount: amount,
      category: category ?? this.category,
      date: date,
      strategy: strategy,
      confidence: confidence,
      rawSms: rawSms,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}

class TransactionMock {
  static List<Transaction> get mockTransactions {
    return [
      Transaction(
        id: '1',
        merchant: 'Whole Foods Market',
        amount: 84.50,
        category: 'Groceries',
        date: DateTime.now().subtract(const Duration(hours: 2)),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: 'Txn: \$84.50 spent at Whole Foods on card ending 4209.',
        isConfirmed: true,
      ),
      Transaction(
        id: '2',
        merchant: 'City Medical Group',
        amount: 120.00,
        category: 'Healthcare',
        date: DateTime.now().subtract(const Duration(days: 1)),
        strategy: ClassificationStrategy.ml,
        confidence: 0.942,
        rawSms: 'Debited \$120.00 at City Medical Group. Ref: CMD8421.',
        isConfirmed: false,
      ),
      Transaction(
        id: '3',
        merchant: 'Power Grid Co.',
        amount: 72.35,
        category: 'Utilities',
        date: DateTime.now().subtract(const Duration(days: 2)),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: 'Auto-pay: \$72.35 to Power Grid Co successful.',
        isConfirmed: true,
      ),
      Transaction(
        id: '4',
        merchant: 'Netflix Subscription',
        amount: 15.49,
        category: 'Entertainment',
        date: DateTime.now().subtract(const Duration(days: 3)),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: 'Netflix Inc. debited \$15.49 on 20-06-2026.',
        isConfirmed: true,
      ),
      Transaction(
        id: '5',
        merchant: 'The Daily Grind Coffee',
        amount: 6.75,
        category: 'Dining',
        date: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
        strategy: ClassificationStrategy.hybrid,
        confidence: 0.725,
        rawSms: 'Spent \$6.75 at The Daily Grind.',
        isConfirmed: false,
      ),
      Transaction(
        id: '6',
        merchant: 'Amazon Prime Order',
        amount: 45.90,
        category: 'Shopping',
        date: DateTime.now().subtract(const Duration(days: 4)),
        strategy: ClassificationStrategy.ml,
        confidence: 0.884,
        rawSms: 'Alert: Amazon order of \$45.90 shipped.',
        isConfirmed: true,
      ),
      Transaction(
        id: '7',
        merchant: 'CVS Pharmacy Store',
        amount: 22.15,
        category: 'Healthcare',
        date: DateTime.now().subtract(const Duration(days: 5)),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: 'Txn: \$22.15 at CVS Pharmacy.',
        isConfirmed: false,
      ),
    ];
  }

  // Simulate parsing an SMS and classifying it
  static Transaction classifySms(String smsText) {
    double amount = 0.0;
    final amountRegex = RegExp(r'\$?\s*(\d+(?:\.\d{2})?)');
    final match = amountRegex.firstMatch(smsText);
    if (match != null) {
      amount = double.tryParse(match.group(1) ?? '0.0') ?? 0.0;
    } else {
      amount = (Random().nextDouble() * 100 + 5).roundToDouble();
    }

    final text = smsText.toLowerCase();

    if (text.contains('walmart') || text.contains('whole foods') || text.contains('grocery') || text.contains('kroger')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Grocery Store'),
        amount: amount,
        category: 'Groceries',
        date: DateTime.now(),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: smsText,
      );
    }
    
    if (text.contains('cvs') || text.contains('walgreens') || text.contains('hospital') || text.contains('pharmacy') || text.contains('medical') || text.contains('doctor')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Medical Care'),
        amount: amount,
        category: 'Healthcare',
        date: DateTime.now(),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: smsText,
      );
    }

    if (text.contains('netflix') || text.contains('spotify') || text.contains('hulu') || text.contains('disney') || text.contains('steam') || text.contains('nintendo')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Entertainment Sub'),
        amount: amount,
        category: 'Entertainment',
        date: DateTime.now(),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: smsText,
      );
    }

    if (text.contains('electric') || text.contains('power') || text.contains('water') || text.contains('gas') || text.contains('wifi') || text.contains('comcast') || text.contains('verizon') || text.contains('at&t') || text.contains('utility')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Utility Provider'),
        amount: amount,
        category: 'Utilities',
        date: DateTime.now(),
        strategy: ClassificationStrategy.rule,
        confidence: 1.00,
        rawSms: smsText,
      );
    }

    if (text.contains('amazon') || text.contains('zara') || text.contains('nike') || text.contains('ebay') || text.contains('store') || text.contains('shop') || text.contains('retail')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Retail Shop'),
        amount: amount,
        category: 'Shopping',
        date: DateTime.now(),
        strategy: ClassificationStrategy.ml,
        confidence: 0.80 + Random().nextDouble() * 0.18,
        rawSms: smsText,
      );
    }

    if (text.contains('coffee') || text.contains('cafe') || text.contains('starbucks') || text.contains('pizza') || text.contains('mcdonald') || text.contains('burger') || text.contains('diner') || text.contains('eats') || text.contains('restaurant')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Diner / Restaurant'),
        amount: amount,
        category: 'Dining',
        date: DateTime.now(),
        strategy: ClassificationStrategy.ml,
        confidence: 0.82 + Random().nextDouble() * 0.16,
        rawSms: smsText,
      );
    }

    if (text.contains('eat') || text.contains('hungry') || text.contains('lunch') || text.contains('dinner') || text.contains('breakfast') || text.contains('food') || text.contains('meal')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Food Merchant'),
        amount: amount,
        category: 'Dining',
        date: DateTime.now(),
        strategy: ClassificationStrategy.hybrid,
        confidence: 0.60 + Random().nextDouble() * 0.18,
        rawSms: smsText,
      );
    }

    if (text.contains('buy') || text.contains('bought') || text.contains('get') || text.contains('got') || text.contains('purchase') || text.contains('item')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Unresolved Merchant'),
        amount: amount,
        category: 'Shopping',
        date: DateTime.now(),
        strategy: ClassificationStrategy.hybrid,
        confidence: 0.58 + Random().nextDouble() * 0.18,
        rawSms: smsText,
      );
    }

    if (text.contains('pills') || text.contains('medicine') || text.contains('sick') || text.contains('pain') || text.contains('checkup')) {
      return Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        merchant: _extractMerchant(smsText, 'Health Clinic'),
        amount: amount,
        category: 'Healthcare',
        date: DateTime.now(),
        strategy: ClassificationStrategy.hybrid,
        confidence: 0.65 + Random().nextDouble() * 0.14,
        rawSms: smsText,
      );
    }

    return Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      merchant: _extractMerchant(smsText, 'Unknown Merchant'),
      amount: amount,
      category: 'Other',
      date: DateTime.now(),
      strategy: ClassificationStrategy.hybrid,
      confidence: 0.50 + Random().nextDouble() * 0.15,
      rawSms: smsText,
    );
  }

  static String _extractMerchant(String text, String fallback) {
    final atRegex = RegExp(r'(?:at|to|from|spent\s+at)\s+([A-Za-z0-9\s\.\&]+?)(?=\s+on|\s+for|\s+Ref:|\s+debited|\s+spent|\$|\d{2}/|\d{4}|\.|$)');
    final match = atRegex.firstMatch(text);
    if (match != null) {
      final name = match.group(1)?.trim();
      if (name != null && name.length > 2 && name.length < 30) {
        return _capitalizeWords(name);
      }
    }
    return fallback;
  }

  static String _capitalizeWords(String input) {
    if (input.isEmpty) return input;
    return input.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}

class SmsAlert {
  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool isClassified;
  final String? linkedTransactionId;

  SmsAlert({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
    this.isClassified = false,
    this.linkedTransactionId,
  });

  SmsAlert copyWith({
    bool? isClassified,
    String? linkedTransactionId,
  }) {
    return SmsAlert(
      id: id,
      sender: sender,
      body: body,
      timestamp: timestamp,
      isClassified: isClassified ?? this.isClassified,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
    );
  }
}

extension SmsAlertMock on TransactionMock {
  static List<SmsAlert> get mockSmsAlerts {
    return [
      SmsAlert(
        id: 'sms-1',
        sender: 'CHASE-ALERT',
        body: 'Txn: \$84.50 spent at Whole Foods on card ending 4209.',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        isClassified: true,
        linkedTransactionId: '1',
      ),
      SmsAlert(
        id: 'sms-2',
        sender: 'CITI-NOTIFY',
        body: 'Debited \$120.00 at City Medical Group. Ref: CMD8421.',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        isClassified: false,
      ),
      SmsAlert(
        id: 'sms-3',
        sender: 'BOA-ALERTS',
        body: 'Auto-pay: \$72.35 to Power Grid Co successful.',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        isClassified: true,
        linkedTransactionId: '3',
      ),
      SmsAlert(
        id: 'sms-4',
        sender: 'CHASE-ALERT',
        body: 'Netflix Inc. debited \$15.49 on 20-06-2026.',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        isClassified: true,
        linkedTransactionId: '4',
      ),
      SmsAlert(
        id: 'sms-5',
        sender: 'AMEX-NOTICE',
        body: 'Spent \$12.50 at Starbucks Coffee. Ref: SBX9904.',
        timestamp: DateTime.now().subtract(const Duration(days: 3, hours: 2)),
        isClassified: false,
      ),
      SmsAlert(
        id: 'sms-6',
        sender: 'DISCOVER-MSG',
        body: 'Spent \$45.00 on gas at Chevron station.',
        timestamp: DateTime.now().subtract(const Duration(days: 4)),
        isClassified: false,
      ),
      SmsAlert(
        id: 'sms-7',
        sender: 'CITI-NOTIFY',
        body: 'Debited \$14.20 at Kroger Grocery.',
        timestamp: DateTime.now().subtract(const Duration(days: 5)),
        isClassified: false,
      ),
    ];
  }
}

