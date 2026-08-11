import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Call once from main() after Firebase.initializeApp()
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap if needed
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    // Request permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Show a notification after an SMS is classified.
  ///
  /// [category]  — e.g. "Food", "UPI_Transfer"
  /// [amount]    — e.g. "259.00"
  /// [merchant]  — e.g. "Swiggy", "Unknown"
  Future<void> showClassificationNotification({
    required String category,
    required String amount,
    required String merchant,
  }) async {
    if (!_initialized) await initialize();

    final String title = _titleFor(category);
    final String body = merchant != 'Unknown' && merchant.isNotEmpty
        ? '₹$amount spent at $merchant → $category'
        : '₹$amount classified as $category';

    const androidDetails = AndroidNotificationDetails(
      'transactai_classification', // channel ID
      'Transaction Alerts',         // channel name
      channelDescription: 'Notifications when a banking SMS is classified',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF10B981), // emerald green
      enableVibration: true,
      playSound: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique ID
      title,
      body,
      notificationDetails,
      payload: category,
    );
  }

  String _titleFor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return '🍔 Food transaction detected';
      case 'grocery':
        return '🛒 Grocery transaction detected';
      case 'fuel':
        return '⛽ Fuel transaction detected';
      case 'shopping':
        return '🛍️ Shopping transaction detected';
      case 'medical':
        return '💊 Medical transaction detected';
      case 'bills':
        return '📄 Bill payment detected';
      case 'transport':
        return '🚗 Transport transaction detected';
      case 'refund':
        return '💰 Refund received';
      case 'salary':
        return '💵 Salary credited';
      case 'subscription':
        return '📱 Subscription payment detected';
      case 'upi_transfer':
        return '↗️ UPI Transfer detected';
      default:
        return '💳 Transaction classified';
    }
  }
}