import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import '../models/transaction.dart';

class SmsService {
  static Future<bool> requestSmsPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<List<SmsAlert>> fetchIncomingSms() async {
    if (kIsWeb || !Platform.isAndroid) return [];
    final hasPermission = await requestSmsPermission();
    if (!hasPermission) return [];
    try {
      final query = SmsQuery();
      final messages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 100,
      );
      final results = <SmsAlert>[];
      for (final msg in messages) {
        final body = msg.body ?? '';
        final sender = msg.address ?? 'UNKNOWN';
        if (_isFinancialSms(body, sender)) {
          results.add(SmsAlert(
            id: 'device-${msg.id ?? DateTime.now().millisecondsSinceEpoch}',
            sender: sender.toUpperCase(),
            body: body,
            timestamp: msg.date ?? DateTime.now(),
            isClassified: false,
          ));
        }
      }
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      debugPrint('SMS fetch error: $e');
      return [];
    }
  }

  // flutter_sms_inbox does not support real-time listening.
  // Real-time is handled by the 60-second polling timer in main.dart.
  static Future<void> listenToIncomingSms(
      Function(SmsAlert) onNewSms) async {
    return;
  }

  static bool _isFinancialSms(String body, String sender) {
    final lower = body.toLowerCase();
    const keywords = [
      'debited', 'credited', 'debit', 'credit',
      'upi', 'neft', 'imps', 'rtgs',
      'rs.', 'inr', 'a/c', 'acct',
      'txn', 'transaction', 'spent',
      'paid', 'payment', 'atm', 'withdrawn',
    ];
    return keywords.any((k) => lower.contains(k));
  }
}