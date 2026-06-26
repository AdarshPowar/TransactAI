import 'package:flutter/material.dart';
import 'theme/constants.dart';
import 'screens/dashboard_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/classify_screen.dart';
import 'screens/launch_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'dart:async';
import 'screens/sms_feed_screen.dart';
import 'services/sms_service.dart';
import 'services/api_service.dart';
import 'package:transact_ai_mobile/models/transaction.dart';

void main() {
  runApp(const TransactAIApp());
}

enum AppStatus { launch, login, signup, authenticated }

class TransactAIApp extends StatefulWidget {
  const TransactAIApp({super.key});

  @override
  State<TransactAIApp> createState() => _TransactAIAppState();
}

class _TransactAIAppState extends State<TransactAIApp> {
  AppStatus _status = AppStatus.launch;
  List<SmsAlert> _smsAlerts = [];
  int _avatarIndex = 0;

  @override
  void initState() {
    super.initState();
    _smsAlerts = SmsAlertMock.mockSmsAlerts;
  }

  Future<void> _fetchSms() async {
    try {
      final fetchedAlerts = await SmsService.fetchIncomingSms();
      if (!mounted) return;

      int newCount = 0;
      setState(() {
        for (final alert in fetchedAlerts) {
          final exists = _smsAlerts.any(
              (s) => s.id == alert.id || s.body.trim() == alert.body.trim());
          if (!exists) {
            _smsAlerts.insert(0, alert);
            newCount++;
          }
        }
      });

      if (newCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetched $newCount new banking SMS alert(s).'),
            backgroundColor: AppColors.surfaceElevated,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching SMS in UI: $e');
    }
  }

  void _handleLogout() {
    setState(() => _status = AppStatus.login);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out successfully.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransactAI Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildCurrentScreen(),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_status) {
      case AppStatus.launch:
        return LaunchScreen(
          key: const ValueKey('launch'),
          onGetStarted: () => setState(() => _status = AppStatus.login),
        );
      case AppStatus.login:
        return LoginScreen(
          key: const ValueKey('login'),
          onLogin: (email, password) async {
            // Try real backend login, fall through on failure
            try {
              await ApiService.login(email, password);
            } catch (_) {}
            setState(() => _status = AppStatus.authenticated);
          },
          onGoToSignup: () => setState(() => _status = AppStatus.signup),
        );
      case AppStatus.signup:
        return SignupScreen(
          key: const ValueKey('signup'),
          onSignup: (name, email, password) async {
            try {
              await ApiService.signup(name, email, password);
            } catch (_) {}
            setState(() => _status = AppStatus.authenticated);
          },
          onGoToLogin: () => setState(() => _status = AppStatus.login),
        );
      case AppStatus.authenticated:
        return TransactAIShell(
          key: const ValueKey('shell'),
          smsAlerts: _smsAlerts,
          activeAvatarIndex: _avatarIndex,
          onAvatarChanged: (index) => setState(() => _avatarIndex = index),
          onLogout: _handleLogout,
          onFetchSms: _fetchSms,
          onSmsClassified: (alertBody) {
            setState(() {
              final idx = _smsAlerts
                  .indexWhere((s) => s.body.trim() == alertBody.trim());
              if (idx != -1) {
                _smsAlerts[idx] =
                    _smsAlerts[idx].copyWith(isClassified: true);
              }
            });
          },
        );
    }
  }
}

class TransactAIShell extends StatefulWidget {
  final List<SmsAlert> smsAlerts;
  final int activeAvatarIndex;
  final Function(int) onAvatarChanged;
  final VoidCallback onLogout;
  final Future<void> Function() onFetchSms;
  final Function(String alertBody) onSmsClassified;

  const TransactAIShell({
    super.key,
    required this.smsAlerts,
    required this.activeAvatarIndex,
    required this.onAvatarChanged,
    required this.onLogout,
    required this.onFetchSms,
    required this.onSmsClassified,
  });

  @override
  State<TransactAIShell> createState() => _TransactAIShellState();
}

class _TransactAIShellState extends State<TransactAIShell> {
  int _currentIndex = 0;
  String? _classifyInitialText;
  Timer? _smsTimer;

  @override
  void initState() {
    super.initState();
    _smsTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) widget.onFetchSms();
    });
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    super.dispose();
  }

  void _classifySmsFromFeed(SmsAlert alert) {
    setState(() {
      _classifyInitialText = alert.body;
      _currentIndex = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      // Dashboard now loads data from backend directly — no props needed
      const DashboardScreen(),

      // Insights screen — still uses mock/local data, update separately if needed
      InsightsScreen(
        transactions: const [],
      ),

      SmsFeedScreen(
        smsAlerts: widget.smsAlerts,
        onClassifySms: _classifySmsFromFeed,
        onFetchSms: widget.onFetchSms,
      ),

      // Classify screen — calls backend, notifies parent when SMS classified
      ClassifyScreen(
        key: ValueKey(_classifyInitialText ?? 'classify-default'),
        initialText: _classifyInitialText,
        onTransactionSaved: (result) {
          if (_classifyInitialText != null) {
            widget.onSmsClassified(_classifyInitialText!);
          }
        },
      ),
    ];

    final pendingSmsCount =
        widget.smsAlerts.where((s) => !s.isClassified).length;

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1.0),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
              if (index != 3) _classifyInitialText = null;
            });
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Overview',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.pie_chart_outline),
              activeIcon: Icon(Icons.pie_chart),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.mail_outline_outlined),
                  if (pendingSmsCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 8, minHeight: 8),
                      ),
                    ),
                ],
              ),
              activeIcon: const Icon(Icons.mail),
              label: 'SMS Feed',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.psychology_outlined),
              activeIcon: Icon(Icons.psychology),
              label: 'Classify',
            ),
          ],
        ),
      ),
    );
  }
}