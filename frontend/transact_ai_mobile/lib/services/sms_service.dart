import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart' as telephony;
import '../models/transaction.dart';

class SmsService {
  static final telephony.Telephony _telephony = telephony.Telephony.instance;

  static Future<bool> requestSmsPermission() async {
    if (kIsWeb) return true;
    // Requesting SMS permissions
    final status = await Permission.sms.request();
    return status.isGranted;
  }
  static Future<List<SmsAlert>> fetchIncomingSms({bool forceSimulate = false}) async {
    // Add this implementation to your service file
    if (forceSimulate || kIsWeb || !Platform.isAndroid) {
      return _generateSimulatedAlerts();
    }
    
    final hasPermission = await requestSmsPermission();
    if (!hasPermission) return [];

    final messages = await _query.querySms(kinds: [SmsQueryKind.inbox], count: 20);
    return messages.map((m) => SmsAlert(
      id: m.id?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      sender: m.sender?.toUpperCase() ?? 'UNKNOWN',
      body: m.body ?? '',
      timestamp: m.date ?? DateTime.now(),
    )).toList();
  }
  static Future<void> listenToIncomingSms(Function(SmsAlert) onNewSms) async {
    if (kIsWeb || !Platform.isAndroid) return;
    
    final hasPermission = await requestSmsPermission();
    if (!hasPermission) return;
    
    // Using the aliased telephony package
    _telephony.listenIncomingSms(
      onNewMessage: (telephony.SmsMessage message) {
        onNewSms(SmsAlert(
          id: message.id.toString(),
          sender: message.address ?? 'UNKNOWN',
          body: message.body ?? '',
          timestamp: message.date != null 
              ? DateTime.fromMillisecondsSinceEpoch(message.date!) 
              : DateTime.now(),
        ));
      },
      listenInBackground: true, 
    );
  }
}