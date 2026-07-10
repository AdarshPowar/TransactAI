import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/constants.dart';
import '../services/pin_service.dart';
import 'pin_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int activeAvatarIndex;
  final Function(int) onAvatarChanged;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.activeAvatarIndex,
    required this.onAvatarChanged,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

bool _biometricEnabled = false;

class _ProfileScreenState extends State<ProfileScreen> {
  static final List<IconData> avatarIcons = [
    Icons.person_outline,
    Icons.face_retouching_natural_outlined,
    Icons.psychology_outlined,
    Icons.admin_panel_settings_outlined,
  ];

  static final List<String> avatarLabels = [
    'User Profile',
    'Face Scan',
    'Neural Core',
    'Secured Admin',
  ];

  bool _hasPin = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
  }

  Future<void> _loadSecurityState() async {
  final hasPin = await PinService.hasPin();
  final bioEnabled = await PinService.isBiometricEnabled();
  final localAuth = LocalAuthentication();
  final canCheck = await localAuth.canCheckBiometrics;
  final isSupported = await localAuth.isDeviceSupported();
  if (mounted) {
    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = bioEnabled;
      _biometricAvailable = canCheck && isSupported;
    });
  }
}

  void _setupPin() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PinScreen(
        mode: PinScreenMode.setup,
        onSuccess: () async {
          Navigator.pop(context);
          setState(() => _hasPin = true);
          // Ask about biometric if available
          if (_biometricAvailable) {
            await _askBiometricPermission();
          } else {
            _showSnack('PIN set successfully ✓');
          }
        },
      ),
    ),
  );
}

  Future<void> _askBiometricPermission() async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Row(
        children: [
          Icon(Icons.fingerprint, color: Colors.white, size: 22),
          SizedBox(width: 10),
          Text(
            'Enable Biometrics?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: const Text(
        'Would you like to use fingerprint or Face ID instead of entering your PIN every time?',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Not Now',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Enable',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  if (result == true) {
    await PinService.setBiometricEnabled(true);
    setState(() => _biometricEnabled = true);
    _showSnack('PIN + Fingerprint enabled ✓');
  } else {
    _showSnack('PIN set successfully ✓');
  }
}

  void _changePin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          mode: PinScreenMode.verify,
          onSuccess: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PinScreen(
                  mode: PinScreenMode.setup,
                  onSuccess: () {
                    Navigator.pop(context);
                    _showSnack('PIN changed successfully ✓');
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _removePin() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Remove PIN',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure? You will no longer be asked for PIN when opening the app.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await PinService.clearPin();
              if (mounted) {
                setState(() => _hasPin = false);
                _showSnack('PIN removed');
              }
            },
            child: const Text('Remove',
                style: TextStyle(color: AppColors.categoryHealthcare)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.surfaceElevated,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final activeIcon = avatarIcons[widget.activeAvatarIndex];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar ────────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Icon(activeIcon, color: AppColors.textPrimary, size: 44),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => _showAvatarPicker(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.black, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    avatarLabels[widget.activeAvatarIndex],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // ── Security Section ─────────────────────────────────────────
            const Text(
              'SECURITY',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  // PIN status row
                  _SecurityTile(
                    icon: Icons.lock_outline,
                    title: _hasPin ? 'PIN Lock' : 'Set App PIN',
                    subtitle: _hasPin
                        ? 'PIN is active — app locks on close'
                        : 'Add a 4-digit PIN to secure the app',
                    trailing: _hasPin
                        ? _Badge('ON', AppColors.categoryGroceries)
                        : const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                    onTap: _hasPin ? null : _setupPin,
                  ),

                  if (_hasPin) ...[
                    _divider(),
                    _SecurityTile(
                      icon: Icons.edit_outlined,
                      title: 'Change PIN',
                      subtitle: 'Update your 4-digit PIN',
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                      onTap: _changePin,
                    ),
                    _divider(),
                    _SecurityTile(
                      icon: Icons.lock_open_outlined,
                      title: 'Remove PIN',
                      subtitle: 'Disable PIN lock for this app',
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                      onTap: _removePin,
                      titleColor: AppColors.categoryHealthcare,
                    ),
                  ],

                  if (_biometricAvailable) ...[
                    _divider(),
                    _SecurityTile(
                      icon: Icons.fingerprint,
                      title: 'Fingerprint / Face ID',
                      subtitle: _hasPin
                          ? 'Available on PIN screen as alternative'
                          : 'Set a PIN first to enable biometric login',
                      trailing: _hasPin
                          ? _Badge('ON', AppColors.categoryGroceries)
                          : _Badge('OFF', AppColors.textMuted),
                      onTap: null,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Account Section ──────────────────────────────────────────
            const Text(
              'ACCOUNT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _SecurityTile(
                icon: Icons.logout,
                title: 'Sign Out',
                subtitle: 'Sign out of your TransactAI account',
                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  widget.onLogout();
                },
                titleColor: AppColors.categoryHealthcare,
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: AppColors.border.withOpacity(0.5),
        indent: 52,
      );

  void _showAvatarPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderBright,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'CHOOSE AVATAR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: avatarIcons.length,
              itemBuilder: (context, index) {
                final isSelected = widget.activeAvatarIndex == index;
                return GestureDetector(
                  onTap: () {
                    widget.onAvatarChanged(index);
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : AppColors.surfaceElevated,
                      border: Border.all(
                        color: isSelected ? Colors.white : AppColors.border,
                        width: 1.0,
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      avatarIcons[index],
                      color: isSelected ? Colors.black : Colors.white,
                      size: 24,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  const _SecurityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}