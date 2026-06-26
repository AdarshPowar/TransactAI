import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/transaction.dart';

class SmsService {
  static final List<Map<String, String>> _mockSmsQueue = [
    {
      'sender': 'CHASE-ALERT',
      'body': 'Txn: \$18.45 spent at Trader Joes on card ending 4209.',
    },
    {
      'sender': 'AMEX-NOTICE',
      'body': 'Spent \$85.00 at CVS Pharmacy Store. Ref: CVS0481.',
    },
    {
      'sender': 'BOA-ALERTS',
      'body': 'Auto-pay: \$112.50 to Comcast Cable successful.',
    },
    {
      'sender': 'CITI-NOTIFY',
      'body': 'Debited \$64.12 at Dominos Pizza. Order #4801.',
    },
    {
      'sender': 'WELLS-FARGO',
      'body': 'Spent \$149.99 at Best Buy #9021. Ref: WFB0284.',
    },
    {
      'sender': 'VENMO-SMS',
      'body': 'You paid \$15.00 to John for coffee and brunch.',
    },
    {
      'sender': 'APPLE-PAY',
      'body': 'Charged \$2.99 for iCloud Storage on 23-06-2026.',
    },
  ];

  static int _mockQueueIndex = 0;

  /// Check and request SMS permission on Android.
  /// On other platforms, always returns true to simulate success.
  static Future<bool> requestSmsPermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.sms.status;
      if (status.isGranted) return true;
      final result = await Permission.sms.request();
      return result.isGranted;
    }
    return true; // Fallback for other platforms to run in simulation mode
  }

  /// Fetches SMS messages.
  /// If running on Android and permission is granted, scans the device inbox.
  /// Otherwise (Web/Windows/denied permissions), returns the next simulated SMS alert.
  static Future<List<SmsAlert>> fetchIncomingSms({bool forceSimulate = false}) async {
    if (!kIsWeb && Platform.isAndroid && !forceSimulate) {
      final hasPermission = await requestSmsPermission();
      if (hasPermission) {
        final SmsQuery query = SmsQuery();
        try {
          final List<SmsMessage> messages = await query.querySms(
            kinds: [SmsQueryKind.inbox],
          );
          
          final List<SmsAlert> results = [];
          for (final msg in messages) {
            final body = msg.body ?? '';
            final sender = msg.address ?? 'UNKNOWN';
            final timestamp = msg.date ?? DateTime.now();
            final id = msg.id?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString();

            // Simple keyword-based banking message filter
            if (_isFinancialSms(body, sender)) {
              results.add(SmsAlert(
                id: 'native-$id',
                sender: sender.toUpperCase(),
                body: body,
                timestamp: timestamp,
                isClassified: false,
              ));
            }
          }
          return results;
        } catch (e) {
          debugPrint('Error querying native SMS: $e. Falling back to simulation.');
        }
      }
    }

    // Web/Windows or Permission Denied: return simulated items from our queue
    return _generateSimulatedAlerts();
  }

  /// Simple check to filter financial notification SMS
  static bool _isFinancialSms(String body, String sender) {
    final lowerBody = body.toLowerCase();
    final lowerSender = sender.toLowerCase();
    
    // Financial keywords
    final keywords = ['spent', 'debited', 'credited', 'charged', 'txn', 'payment', 'paid', 'withdrawn', 'auto-pay', 'ref:'];
    final containsKeyword = keywords.any((keyword) => lowerBody.contains(keyword));
    
    // Currency symbol
    final containsCurrency = body.contains('\$') || body.contains('usd') || body.contains('inr') || body.contains('rs.');
    
    // Typical banking senders
    final bankingSenders = ['bank', 'card', 'chase', 'citi', 'boa', 'amex', 'discover', 'alert', 'notify', 'pay', 'wells'];
    final isBankSender = bankingSenders.any((s) => lowerSender.contains(s));

    return (containsKeyword && containsCurrency) || isBankSender;
  }

  /// Generates simulated alerts sequentially from the queue
  static List<SmsAlert> _generateSimulatedAlerts() {
    if (_mockQueueIndex >= _mockSmsQueue.length) {
      // Loop back if we run out of mock alerts
      _mockQueueIndex = 0;
    }
    
    final item = _mockSmsQueue[_mockQueueIndex];
    _mockQueueIndex++;

    return [
      SmsAlert(
        id: 'sim-${DateTime.now().millisecondsSinceEpoch}',
        sender: item['sender']!,
        body: item['body']!,
        timestamp: DateTime.now(),
        isClassified: false,
      )
    ];
  }
}
