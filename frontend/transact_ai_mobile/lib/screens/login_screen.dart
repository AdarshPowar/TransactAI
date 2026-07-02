import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/constants.dart';
import '../services/auth_service.dart';

/// Login method the user has selected on the tab bar.
enum _LoginMethod { email, phone }

class LoginScreen extends StatefulWidget {
  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback onGoToSignup;

  /// Called when the user completes phone + OTP flow.
  /// [phone] is the full number (e.g. "+919876543210").
  final Function(String phone)? onPhoneLogin;

  /// Called when the user taps "Continue with Google".
  final VoidCallback? onGoogleLogin;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onGoToSignup,
    this.onPhoneLogin,
    this.onGoogleLogin,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ── Tab controller ────────────────────────────────────────────────────────
  late final TabController _tabController;
  _LoginMethod _activeMethod = _LoginMethod.email;

  // ── Email / password ──────────────────────────────────────────────────────
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // ── Phone ─────────────────────────────────────────────────────────────────
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _otpSent = false;
  int _resendCountdown = 0;
  String? _verificationId;

  // ── Shared state ──────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;
  bool _resetEmailSent = false;

  // ── Country code ──────────────────────────────────────────────────────────
  String _countryCode = '+91';
  final List<Map<String, String>> _countryCodes = const [
    {'code': '+91', 'flag': '🇮🇳', 'name': 'India'},
    {'code': '+1', 'flag': '🇺🇸', 'name': 'USA'},
    {'code': '+44', 'flag': '🇬🇧', 'name': 'UK'},
    {'code': '+61', 'flag': '🇦🇺', 'name': 'Australia'},
    {'code': '+65', 'flag': '🇸🇬', 'name': 'Singapore'},
    {'code': '+971', 'flag': '🇦🇪', 'name': 'UAE'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() {
        _activeMethod = _LoginMethod.values[_tabController.index];
        _errorMessage = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _clearError() => setState(() => _errorMessage = null);

  void _setLoading(bool v) => setState(() => _isLoading = v);

  void _setError(String msg) => setState(() => _errorMessage = msg);

  // ── Forgot password ───────────────────────────────────────────────────────

  void _handleForgotPassword() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _setError('Enter your email address above, then tap "Forgot Password?"');
      return;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _setError('Please enter a valid email address first.');
      return;
    }

    _setLoading(true);
    AuthService.instance
        .sendPasswordResetEmail(email)
        .then((_) {
      if (!mounted) return;
      _setLoading(false);
      setState(() => _resetEmailSent = true);
      _clearError();
    }).catchError((e) {
      if (!mounted) return;
      _setLoading(false);
      _setError(
        e.toString().contains('user-not-found')
            ? 'No account found with that email.'
            : 'Could not send reset email. Please try again.',
      );
    });
  }

  // ── Email login ───────────────────────────────────────────────────────────

  void _handleEmailLogin() async {
    _clearError();
    if (!_emailFormKey.currentState!.validate()) return;
    _setLoading(true);

    try {
      await widget.onLogin(
          _emailController.text.trim(), _passwordController.text);
    } finally {
      if (mounted) _setLoading(false);
    }
  }

  // ── Phone login ───────────────────────────────────────────────────────────

  void _handleSendOtp() {
    _clearError();
    if (!_phoneFormKey.currentState!.validate()) return;
    _setLoading(true);

    final fullPhone = '$_countryCode${_phoneController.text.trim()}';

    AuthService.instance.sendOtp(
      phoneNumber: fullPhone,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _resendCountdown = 30;
          _isLoading = false;
        });
        _startResendTimer();
        _otpFocusNodes[0].requestFocus();
      },
      onAutoVerified: (user) {
        // Android-only instant verification (rare with test numbers).
        if (!mounted) return;
        _setLoading(false);
        widget.onPhoneLogin?.call(fullPhone);
      },
      onFailed: (message) {
        if (!mounted) return;
        _setLoading(false);
        _setError(message);
      },
    );
  }

  void _startResendTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
        _startResendTimer();
      }
    });
  }

  void _handleVerifyOtp() {
    _clearError();
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      _setError('Please enter the complete 6-digit OTP.');
      return;
    }
    if (_verificationId == null) {
      _setError('Something went wrong. Please request a new OTP.');
      return;
    }
    _setLoading(true);

    AuthService.instance
        .verifyOtp(verificationId: _verificationId!, smsCode: otp)
        .then((user) {
      if (!mounted) return;
      _setLoading(false);
      final fullPhone = '$_countryCode${_phoneController.text.trim()}';
      widget.onPhoneLogin?.call(fullPhone);
    }).catchError((e) {
      if (!mounted) return;
      _setLoading(false);
      _setError(
        e is Exception
            ? 'Incorrect OTP. Please check and try again.'
            : 'Verification failed. Please try again.',
      );
    });
  }

  void _handleOtpInput(int index, String value) {
    if (value.length == 1 && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  // ── Biometrics ────────────────────────────────────────────────────────────

  void _triggerBiometrics() {
    // NOTE: Biometric unlock should only re-authenticate a user who already
    // has a valid Firebase session (e.g. stored securely after first login),
    // not create a new sign-in by itself. Wire this up to local_auth +
    // a cached Firebase session/token once that flow is implemented.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Biometric login: sign in once first, then enable '
            'Face/Touch ID from your profile settings.'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),

                      // ── Header ──────────────────────────────────────────
                      Text(
                        'WELCOME BACK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 2.0,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign In',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Method tabs ─────────────────────────────────────
                      _MethodTabBar(controller: _tabController),
                      const SizedBox(height: 28),

                      // ── Error banner ────────────────────────────────────
                      if (_errorMessage != null) ...[
                        _ErrorBanner(message: _errorMessage!),
                        const SizedBox(height: 20),
                      ],

                      // Reset email success banner
                      if (_resetEmailSent) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.categoryGroceries
                                .withValues(alpha: 0.08),
                            border: Border.all(
                              color: AppColors.categoryGroceries
                                  .withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset email sent ✓',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.categoryGroceries,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Check your inbox at ${_emailController.text.trim()} and follow the link to reset your password.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.categoryGroceries,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Form body ───────────────────────────────────────
                      if (_activeMethod == _LoginMethod.email)
                        _EmailForm(
                          formKey: _emailFormKey,
                          emailController: _emailController,
                          passwordController: _passwordController,
                          obscurePassword: _obscurePassword,
                          isLoading: _isLoading,
                          onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          onSubmit: _handleEmailLogin,
                          onForgotPassword: _handleForgotPassword,
                        )
                      else
                        _PhoneForm(
                          formKey: _phoneFormKey,
                          phoneController: _phoneController,
                          otpControllers: _otpControllers,
                          otpFocusNodes: _otpFocusNodes,
                          otpSent: _otpSent,
                          isLoading: _isLoading,
                          resendCountdown: _resendCountdown,
                          countryCode: _countryCode,
                          countryCodes: _countryCodes,
                          onCountryCodeChanged: (v) =>
                              setState(() => _countryCode = v),
                          onSendOtp: _handleSendOtp,
                          onVerifyOtp: _handleVerifyOtp,
                          onOtpInput: _handleOtpInput,
                          onResend: () {
                            for (final c in _otpControllers) {
                              c.clear();
                            }
                            _handleSendOtp();
                          },
                          onChangeNumber: () {
                            setState(() {
                              _otpSent = false;
                              _verificationId = null;
                              _resendCountdown = 0;
                              for (final c in _otpControllers) {
                                c.clear();
                              }
                            });
                          },
                        ),

                      const SizedBox(height: 24),

                      // ── Divider ─────────────────────────────────────────
                      _OrDivider(),

                      const SizedBox(height: 20),

                      // ── Social / biometrics row ─────────────────────────
                      Row(
                        children: [
                          // Google button
                          Expanded(
                            child: _SocialButton(
                              label: 'Google',
                              icon: _GoogleIcon(),
                              onTap: _isLoading ? null : widget.onGoogleLogin,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Biometrics button
                          _BiometricButton(
                            onTap: _isLoading ? null : _triggerBiometrics,
                          ),
                        ],
                      ),

                      const Spacer(),

                      // ── Sign up anchor ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account?",
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: widget.onGoToSignup,
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Pill-style tab bar for Email / Phone.
class _MethodTabBar extends StatelessWidget {
  final TabController controller;
  const _MethodTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.black,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: const [
          Tab(text: 'Email'),
          Tab(text: 'Phone'),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.categoryHealthcare.withValues(alpha: 0.08),
        border: Border.all(
            color: AppColors.categoryHealthcare.withValues(alpha: 0.4),
            width: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.categoryHealthcare,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Email Form ────────────────────────────────────────────────────────────────

class _EmailForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  const _EmailForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  static InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.border, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(
            color: AppColors.categoryHealthcare, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(
            color: AppColors.categoryHealthcare, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email
          _FieldLabel('EMAIL ADDRESS'),
          const SizedBox(height: 8),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: Colors.white,
            decoration: _fieldDecoration(hint: 'name@company.com'),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your email address';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                  .hasMatch(val)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Password
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FieldLabel('PASSWORD'),
              GestureDetector(
                onTap: onForgotPassword,
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: Colors.white,
            decoration: _fieldDecoration(
              hint: 'Enter your password',
              suffix: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Please enter your password';
              }
              if (val.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 36),

          // CTA
          _PrimaryButton(
            label: 'Sign In',
            isLoading: isLoading,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

// ── Phone Form ────────────────────────────────────────────────────────────────

class _PhoneForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final List<TextEditingController> otpControllers;
  final List<FocusNode> otpFocusNodes;
  final bool otpSent;
  final bool isLoading;
  final int resendCountdown;
  final String countryCode;
  final List<Map<String, String>> countryCodes;
  final ValueChanged<String> onCountryCodeChanged;
  final VoidCallback onSendOtp;
  final VoidCallback onVerifyOtp;
  final Function(int index, String value) onOtpInput;
  final VoidCallback onResend;
  final VoidCallback onChangeNumber;

  const _PhoneForm({
    required this.formKey,
    required this.phoneController,
    required this.otpControllers,
    required this.otpFocusNodes,
    required this.otpSent,
    required this.isLoading,
    required this.resendCountdown,
    required this.countryCode,
    required this.countryCodes,
    required this.onCountryCodeChanged,
    required this.onSendOtp,
    required this.onVerifyOtp,
    required this.onOtpInput,
    required this.onResend,
    required this.onChangeNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('MOBILE NUMBER'),
          const SizedBox(height: 8),

          // Country code + phone number row
          Row(
            children: [
              // Country code picker
              GestureDetector(
                onTap: () => _showCountryPicker(context),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        countryCodes.firstWhere(
                                (c) => c['code'] == countryCode,
                                orElse: () => {'flag': '🌐'})['flag'] ??
                            '🌐',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        countryCode,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Phone input
              Expanded(
                child: TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !otpSent,
                  style: TextStyle(
                      color: otpSent ? AppColors.textSecondary : Colors.white,
                      fontSize: 14),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: '9876543210',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: AppColors.border, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.5),
                          width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: Colors.white, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(
                          color: AppColors.categoryHealthcare, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(
                          color: AppColors.categoryHealthcare, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Enter your phone number';
                    }
                    if (val.trim().length < 7) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),

          // OTP section (visible after Send OTP)
          if (otpSent) ...[
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _FieldLabel('ENTER OTP'),
                GestureDetector(
                  onTap: resendCountdown == 0 ? onResend : null,
                  child: Text(
                    resendCountdown > 0
                        ? 'Resend in ${resendCountdown}s'
                        : 'Resend OTP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: resendCountdown > 0
                          ? AppColors.textMuted
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) {
                return SizedBox(
                  width: 44,
                  height: 52,
                  child: TextFormField(
                    controller: otpControllers[i],
                    focusNode: otpFocusNodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: AppColors.border, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (v) => onOtpInput(i, v),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'OTP sent to $countryCode ${phoneController.text}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],

          const SizedBox(height: 32),

          // CTA: Send OTP or Verify
          _PrimaryButton(
            label: otpSent ? 'Verify & Sign In' : 'Send OTP',
            isLoading: isLoading,
            onPressed: otpSent ? onVerifyOtp : onSendOtp,
          ),

          // Change number link
          if (otpSent) ...[
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: onChangeNumber,
                // In real usage call setState to reset otpSent in parent
                child: const Text(
                  'Change number',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCountryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'SELECT COUNTRY CODE',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ...countryCodes.map((c) {
              final isSelected = c['code'] == countryCode;
              return ListTile(
                leading: Text(c['flag']!,
                    style: const TextStyle(fontSize: 22)),
                title: Text(
                  c['name']!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                trailing: Text(
                  c['code']!,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  onCountryCodeChanged(c['code']!);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        );
      },
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.0, color: Colors.black),
              )
            : Text(
                label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
            child: Divider(color: AppColors.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const Expanded(
            child: Divider(color: AppColors.border, thickness: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              'Continue with $label',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _BiometricButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: const Icon(Icons.fingerprint,
            color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}

/// Minimal hand-drawn Google "G" icon using Canvas — no asset needed.
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _GooglePainter(),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Draw circle ring segments (simplified Google G)
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;

    // Red top-right arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        -1.2, 1.6, false, paint);

    // Yellow bottom-right arc
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        0.4, 1.0, false, paint);

    // Green bottom-left arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        1.4, 1.1, false, paint);

    // Blue left arc
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        2.5, 1.05, false, paint);

    // Horizontal bar for the "G" cutout
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * 0.82, cy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}