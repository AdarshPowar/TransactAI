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

  Transaction copyWith({String? category, bool? isConfirmed}) {
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

// Empty stubs so existing imports don't break — no mock data
class TransactionMock {
  static List<Transaction> get mockTransactions => [];
}

class SmsAlertMock {
  static List<SmsAlert> get mockSmsAlerts => [];
}