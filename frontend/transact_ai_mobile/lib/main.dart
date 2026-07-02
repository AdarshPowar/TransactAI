import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
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
import 'services/auth_service.dart';
import 'models/transaction.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TransactAIApp());
}

/// Global key so SnackBars can be shown from anywhere, even before a
/// Scaffold ancestor exists at the calling context's position in the tree.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

enum AppStatus { launch, login, signup, authenticated }

class TransactAIApp extends StatefulWidget {
  const TransactAIApp({super.key});

  @override
  State<TransactAIApp> createState() => _TransactAIAppState();
}

class _TransactAIAppState extends State<TransactAIApp> {
  AppStatus _status = AppStatus.launch;
  // Start completely empty — no mocks
  List<SmsAlert> _smsAlerts = [];
  int _avatarIndex = 0;

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
      if (newCount > 0 && mounted) {
        rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
          content: Text('Found $newCount new banking SMS.'),
          backgroundColor: AppColors.surfaceElevated,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Error fetching SMS: $e');
    }
  }

  void _handleLogout() async {
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
    setState(() {
      _status = AppStatus.login;
      // Clear alerts on logout so next user starts fresh
      _smsAlerts = [];
    });
    if (mounted) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(
        content: Text('Logged out successfully.'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransactAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
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
            try {
              // Firebase email/password sign-in
              await AuthService.instance.signInWithEmail(email, password);
            } catch (e) {
              debugPrint('Email login error: $e');
              if (mounted) {
                rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: AppColors.categoryHealthcare,
                ));
              }
              return; // don't proceed to authenticated state on failure
            }
            try {
              await ApiService.login(email, password);
            } catch (_) {}
            if (mounted) setState(() => _status = AppStatus.authenticated);
          },
          onPhoneLogin: (phone) {
            // Phone OTP already verified by the time this fires
            // (LoginScreen calls AuthService.verifyOtp internally — see below)
            setState(() => _status = AppStatus.authenticated);
          },
          onGoogleLogin: () async {
            try {
              final user = await AuthService.instance.signInWithGoogle();
              if (user == null) return; // user cancelled
              setState(() => _status = AppStatus.authenticated);
            } catch (e) {
              debugPrint('Google login error: $e');
              if (mounted) {
                rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text('Google sign-in failed: $e'),
                  backgroundColor: AppColors.categoryHealthcare,
                ));
              }
            }
          },
          onGoToSignup: () => setState(() => _status = AppStatus.signup),
        );
      case AppStatus.signup:
        return SignupScreen(
          key: const ValueKey('signup'),
          onSignup: (name, email, password) async {
  // Let FirebaseAuthException propagate to SignupScreen's error banner
              await AuthService.instance.signUpWithEmail(email, password);
               try {
               await ApiService.signup(name, email, password);
            } catch (_) {}
             if (mounted) setState(() => _status = AppStatus.authenticated);
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
          onNewSmsReceived: (alert) {
            setState(() {
              final exists = _smsAlerts.any((s) =>
                  s.id == alert.id || s.body.trim() == alert.body.trim());
              if (!exists) _smsAlerts.insert(0, alert);
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
  final Function(SmsAlert) onNewSmsReceived;

  const TransactAIShell({
    super.key,
    required this.smsAlerts,
    required this.activeAvatarIndex,
    required this.onAvatarChanged,
    required this.onLogout,
    required this.onFetchSms,
    required this.onSmsClassified,
    required this.onNewSmsReceived,
  });

  @override
  State<TransactAIShell> createState() => _TransactAIShellState();
}

class _TransactAIShellState extends State<TransactAIShell> {
  int _currentIndex = 0;
  String? _classifyInitialText;
  Timer? _smsTimer;
  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();

  @override
  void initState() {
    super.initState();
    // Fetch real SMS immediately on login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFetchSms();
    });
    // Then refresh every 60 seconds
    _smsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) widget.onFetchSms();
    });
    // Listen for real-time incoming SMS
    _initRealTimeSmsListener();
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    super.dispose();
  }

  void _initRealTimeSmsListener() {
    SmsService.listenToIncomingSms((SmsAlert alert) async {
      if (!mounted) return;

      // Add to feed immediately
      widget.onNewSmsReceived(alert);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('New SMS from ${alert.sender} — classifying...'),
        duration: const Duration(seconds: 2),
      ));

      try {
        final result = await ApiService.classify(alert.body);
        widget.onSmsClassified(alert.body);
        _dashboardKey.currentState?.refreshData();

        if (mounted) {
          final category = result['category'] ?? 'Unknown';
          final amount = result['amount'] != null
              ? '₹${result['amount']}'
              : '';
          final merchant =
              result['receiver'] ?? result['receiver_name'] ?? alert.sender;

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Classified: $merchant → $category $amount'),
            backgroundColor: const Color(0xFF1D9E75),
            duration: const Duration(seconds: 4),
          ));
        }
      } catch (e) {
        debugPrint('Auto-classify error: $e');
      }
    });
  }

  void _handleNewTransaction(Transaction txn) {
    // Dashboard fetches live from API — just trigger a refresh
    _dashboardKey.currentState?.refreshData();
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
      DashboardScreen(
        key: _dashboardKey,
        transactions: const [],        // always empty — dashboard loads from API
        onUpdateTransaction: (_) {},
        onSync: widget.onFetchSms,
        onLogout: widget.onLogout,
        activeAvatarIndex: widget.activeAvatarIndex,
        onAvatarChanged: widget.onAvatarChanged,
      ),
      InsightsScreen(
        transactions: const [],        // always empty — insights loads from API
      ),
      SmsFeedScreen(
        smsAlerts: widget.smsAlerts,   // real SMS only, no mocks
        onClassifySms: _classifySmsFromFeed,
        onFetchSms: widget.onFetchSms,
      ),
      ClassifyScreen(
        key: ValueKey(_classifyInitialText ?? 'classify-default'),
        onAddTransaction: _handleNewTransaction,
        initialText: _classifyInitialText,
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
          onTap: (index) => setState(() {
            _currentIndex = index;
            if (index != 3) _classifyInitialText = null;
          }),
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
              icon: Stack(children: [
                const Icon(Icons.mail_outline_outlined),
                if (pendingSmsCount > 0)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: const BoxDecoration(
                          color: Colors.amber, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 8, minHeight: 8),
                    ),
                  ),
              ]),
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