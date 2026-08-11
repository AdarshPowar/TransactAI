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
// ignore: unused_import
import 'screens/profile_screen.dart';
import 'services/notification_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'services/pin_service.dart';
import 'screens/pin_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.initialize();
  runApp(const TransactAIApp());
}

/// Global key so SnackBars can be shown from anywhere, even before a
/// Scaffold ancestor exists at the calling context's position in the tree.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

enum AppStatus { checking, launch, login, signup, locked, authenticated }

class TransactAIApp extends StatefulWidget {
  const TransactAIApp({super.key});

  @override
  State<TransactAIApp> createState() => _TransactAIAppState();
}

class _TransactAIAppState extends State<TransactAIApp> {
  AppStatus _status = AppStatus.checking;
  List<SmsAlert> _smsAlerts = [];
  int _avatarIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    User? user;
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    debugPrint('🔥 Auth check — user: ${user?.uid ?? "NULL"}');

    if (!mounted) return;

    // 1. Check our local SharedPreferences fallback
    bool isLocallyLoggedIn = await PinService.isLoggedIn();

    // 2. Proceed if Firebase has a user OR our local flag says they are logged in
    if (user != null || isLocallyLoggedIn) {
      final hasPin = await PinService.hasPin();
      debugPrint('🔐 hasPin: $hasPin');
      if (!mounted) return;
      if (hasPin) {
        setState(() => _status = AppStatus.locked);
      } else {
        setState(() => _status = AppStatus.authenticated);
      }
    } else {
      setState(() => _status = AppStatus.launch);
    }
  }

  Future<void> _fetchSms() async {
    try {
      final fetchedAlerts = await SmsService.fetchIncomingSms();
      if (!mounted) return;

      // Load already-classified IDs from persistent storage
      final classifiedIds = await PinService.getClassifiedIds();

      List<SmsAlert> newlyAddedAlerts = [];

      setState(() {
        for (final alert in fetchedAlerts) {
          final exists = _smsAlerts.any(
              (s) => s.id == alert.id || s.body.trim() == alert.body.trim());
          if (!exists) {
            // If previously classified, mark it immediately — don't reclassify
            final alreadyClassified = classifiedIds.contains(alert.id);
            _smsAlerts.add(alreadyClassified
                ? alert.copyWith(isClassified: true)
                : alert);
            if (!alreadyClassified) newlyAddedAlerts.add(alert);
          }
        }
        _smsAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });

      if (newlyAddedAlerts.isNotEmpty && mounted) {
        rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(
              'Found ${newlyAddedAlerts.length} new banking SMS. Classifying...'),
          backgroundColor: AppColors.surfaceElevated,
          duration: const Duration(seconds: 3),
        ));
        _processBackgroundClassifications(newlyAddedAlerts);
      }
    } catch (e) {
      debugPrint('Error fetching SMS: $e');
    }
  }

  Future<void> _processBackgroundClassifications(
      List<SmsAlert> newAlerts) async {
    for (final alert in newAlerts) {
      if (alert.isClassified) continue;

      try {
        final result = await ApiService.classify(alert.body);

        // Persist this ID so it won't be reclassified on next app open
        await PinService.markClassified(alert.id);

        // Show notification
        final category = result['category'] ?? 'Unknown';
        final amount = result['amount']?.toString() ?? '0';
        final merchant =
            result['receiver_name'] ?? result['receiver'] ?? 'Unknown';
        await NotificationService.instance.showClassificationNotification(
          category: category,
          amount: amount,
          merchant: merchant,
        );

        if (mounted) {
          setState(() {
            final idx =
                _smsAlerts.indexWhere((s) => s.id == alert.id);
            if (idx != -1) {
              _smsAlerts[idx] =
                  _smsAlerts[idx].copyWith(isClassified: true);
            }
          });
        }
      } catch (e) {
        debugPrint('Background auto-classify error for SMS ID ${alert.id}: $e');
      }
    }
  }

  void _handleLogout() async {
    try {
      await AuthService.instance.signOut();
      await PinService.clearPin();
      await PinService.setLoggedIn(false);
      await PinService.clearClassifiedIds();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
    setState(() {
      _status = AppStatus.login;
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
      case AppStatus.checking:
        return const Scaffold(
          key: ValueKey('checking'),
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );

      case AppStatus.launch:
        return LaunchScreen(
          key: const ValueKey('launch'),
          onGetStarted: () => setState(() => _status = AppStatus.login),
        );

      case AppStatus.locked:
        return PinScreen(
          key: const ValueKey('locked'),
          mode: PinScreenMode.verify,
          onSuccess: () => setState(() => _status = AppStatus.authenticated),
          onLoginInstead: () async {
            await PinService.clearPin();
            await AuthService.instance.signOut();
            await PinService.setLoggedIn(false);
            setState(() => _status = AppStatus.login);
          },
        );

      case AppStatus.login:
        return LoginScreen(
          key: const ValueKey('login'),
          onLogin: (email, password) async {
            try {
              await AuthService.instance.signInWithEmail(email, password);
            } catch (e) {
              debugPrint('Email login error: $e');
              if (mounted) {
                rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: AppColors.categoryHealthcare,
                ));
              }
              return;
            }
            try {
              await ApiService.login(email, password);
            } catch (_) {}
            
            await PinService.setLoggedIn(true);
            if (mounted) setState(() => _status = AppStatus.authenticated);
          },
          onPhoneLogin: (phone) async {
            await PinService.setLoggedIn(true);
            setState(() => _status = AppStatus.authenticated);
          },
          onGoogleLogin: () async {
            try {
              final user = await AuthService.instance.signInWithGoogle();
              if (user == null) return;
              
              await PinService.setLoggedIn(true);
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
            await AuthService.instance.signUpWithEmail(email, password);
            try {
              await ApiService.signup(name, email, password);
            } catch (_) {}
            
            await PinService.setLoggedIn(true);
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
              if (!exists) {
                _smsAlerts.add(alert);
                _smsAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
  String? _pendingClassifyAlertBody;
  Timer? _smsTimer;
  final GlobalKey<DashboardScreenState> _dashboardKey =
      GlobalKey<DashboardScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFetchSms();
    });
    _smsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) widget.onFetchSms();
    });
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

      widget.onNewSmsReceived(alert);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('New SMS from ${alert.sender} — classifying...'),
        duration: const Duration(seconds: 2),
      ));

      try {
        final result = await ApiService.classify(alert.body);
        widget.onSmsClassified(alert.body);
        _dashboardKey.currentState?.refreshData();

        // Show notification
        final category = result['category'] ?? 'Unknown';
        final amount = result['amount']?.toString() ?? '0';
        final merchant =
            result['receiver'] ?? result['receiver_name'] ?? alert.sender;

        await NotificationService.instance.showClassificationNotification(
          category: category,
          amount: amount,
          merchant: merchant,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Classified: $merchant → $category ₹$amount'),
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
    _dashboardKey.currentState?.refreshData();
    if (_pendingClassifyAlertBody != null) {
      widget.onSmsClassified(_pendingClassifyAlertBody!);
      _pendingClassifyAlertBody = null;
    }
  }

  void _classifySmsFromFeed(SmsAlert alert) {
    setState(() {
      _classifyInitialText = alert.body;
      _currentIndex = 3;
    });
    _pendingClassifyAlertBody = alert.body;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        key: _dashboardKey,
        transactions: const [],
        onUpdateTransaction: (_) {},
        onSync: widget.onFetchSms,
        onLogout: widget.onLogout,
        activeAvatarIndex: widget.activeAvatarIndex,
        onAvatarChanged: widget.onAvatarChanged,
      ),
      InsightsScreen(
        transactions: const [],
      ),
      SmsFeedScreen(
        smsAlerts: widget.smsAlerts,
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _classifyInitialText = null;
          });
        }
        // Already on home — do nothing, don't exit
      },
      child: Scaffold(
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
                    right: 0,
                    top: 0,
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
      ), // Scaffold
    ); // PopScope
  }
}