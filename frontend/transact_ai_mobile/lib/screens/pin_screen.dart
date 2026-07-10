import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/pin_service.dart';
import '../theme/constants.dart';

/// Mode controls whether we're setting a new PIN or verifying an existing one.
enum PinScreenMode { setup, verify }

class PinScreen extends StatefulWidget {
  final PinScreenMode mode;
  final VoidCallback onSuccess;
  final VoidCallback? onLoginInstead; // shown in verify mode only

  const PinScreen({
    super.key,
    required this.mode,
    required this.onSuccess,
    this.onLoginInstead,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  String _pin = '';
  String _confirmPin = ''; // used in setup mode
  bool _isConfirming = false; // setup: first entry vs confirm entry
  String? _errorMessage;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    // Check biometrics first, then auto-trigger if in verify mode
    _checkBiometricsAndAutoTrigger();
  }

  Future<void> _checkBiometricsAndAutoTrigger() async {
    try {
      final available = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final bioEnabled = await PinService.isBiometricEnabled();

      debugPrint('🔐 Biometric debug:');
      debugPrint('  isDeviceSupported: $available');
      debugPrint('  canCheckBiometrics: $canCheck');
      debugPrint('  isBiometricEnabled (pref): $bioEnabled');

      // Get available biometric types
      final biometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('  Available biometrics: $biometrics');

      // isAvailable: device supports it AND user enabled it in app settings
      // If bioEnabled is false, biometric won't show — user needs to enable it in Profile
      final isAvailable = available && canCheck && bioEnabled;
      debugPrint('  Final _biometricAvailable: $isAvailable');

      if (mounted) {
        setState(() => _biometricAvailable = isAvailable);
      }

      if (isAvailable && widget.mode == PinScreenMode.verify && mounted) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) await _triggerBiometric();
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
      if (mounted) setState(() => _biometricAvailable = false);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }



  Future<void> _triggerBiometric() async {
    if (!_biometricAvailable) return;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Use fingerprint to access TransactAI',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (authenticated && mounted) {
        widget.onSuccess();
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
    }
  }

  void _onKeyTap(String key) {
    setState(() => _errorMessage = null);

    if (key == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
      return;
    }

    if (_pin.length >= 4) return;
    setState(() => _pin += key);

    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _handlePinComplete);
    }
  }

  Future<void> _handlePinComplete() async {
    if (widget.mode == PinScreenMode.setup) {
      if (!_isConfirming) {
        // First entry — move to confirm
        setState(() {
          _confirmPin = _pin;
          _pin = '';
          _isConfirming = true;
        });
      } else {
        // Confirm entry — check match
        if (_pin == _confirmPin) {
          await PinService.savePin(_pin);
          widget.onSuccess();
        } else {
          _shakeAndClear('PINs do not match. Try again.');
          setState(() => _isConfirming = false);
        }
      }
    } else {
      // Verify mode
      final isCorrect = await PinService.verifyPin(_pin);
      if (isCorrect) {
        widget.onSuccess();
      } else {
        _shakeAndClear('Incorrect PIN. Try again.');
      }
    }
  }

  void _shakeAndClear(String error) {
    _shakeController.forward(from: 0);
    setState(() {
      _pin = '';
      _errorMessage = error;
    });
  }

  String get _title {
    if (widget.mode == PinScreenMode.setup) {
      return _isConfirming ? 'Confirm PIN' : 'Set a PIN';
    }
    return 'Welcome Back';
  }

  String get _subtitle {
    if (widget.mode == PinScreenMode.setup) {
      return _isConfirming
          ? 'Enter your PIN again to confirm'
          : 'Choose a 4-digit PIN to secure your app';
    }
    return 'Enter your PIN to continue';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // App label
              const Text(
                'TRANSACT AI',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  color: Color(0xFF555555),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                ),
              ),

              const SizedBox(height: 48),

              // PIN dots with shake animation
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  final offset = _shakeController.isAnimating
                      ? 8 * (0.5 - (_shakeAnimation.value % 0.25) / 0.25).abs()
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? Colors.white : Colors.transparent,
                        border: Border.all(
                          color: filled
                              ? Colors.white
                              : const Color(0xFF444444),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Error message
              const SizedBox(height: 16),
              SizedBox(
                height: 20,
                child: _errorMessage != null
                    ? Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFEE5A24),
                        ),
                      )
                    : null,
              ),

              const Spacer(),

              // Number pad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    _buildRow(['1', '2', '3']),
                    const SizedBox(height: 16),
                    _buildRow(['4', '5', '6']),
                    const SizedBox(height: 16),
                    _buildRow(['7', '8', '9']),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Fingerprint button (only in verify mode)
                        widget.mode == PinScreenMode.verify && _biometricAvailable
                            ? _buildFingerprint()
                            : const SizedBox(width: 80, height: 80),
                        _buildKey('0'),
                        _buildKey('⌫'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Sign in with different account (verify mode only)
              if (widget.mode == PinScreenMode.verify &&
                  widget.onLoginInstead != null)
                TextButton(
                  onPressed: widget.onLoginInstead,
                  child: const Text(
                    'Sign in with a different account',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666666),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map(_buildKey).toList(),
    );
  }

  Widget _buildKey(String key) {
    final isDelete = key == '⌫';
    return GestureDetector(
      onTap: () => _onKeyTap(key),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDelete ? Colors.transparent : const Color(0xFF1A1A1A),
          border: isDelete
              ? null
              : Border.all(color: const Color(0xFF2C2C2E), width: 1),
        ),
        alignment: Alignment.center,
        child: isDelete
            ? const Icon(Icons.backspace_outlined,
                color: Color(0xFF888888), size: 22)
            : Text(
                key,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
  

  Widget _buildFingerprint() {
    return GestureDetector(
      onTap: _triggerBiometric,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: const Color(0xFF2C2C2E), width: 1),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.fingerprint,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}