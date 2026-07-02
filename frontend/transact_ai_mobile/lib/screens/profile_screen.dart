import 'package:flutter/material.dart';
import '../theme/constants.dart';

class ProfileScreen extends StatelessWidget {
  final int activeAvatarIndex;
  final Function(int) onAvatarChanged;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.activeAvatarIndex,
    required this.onAvatarChanged,
    required this.onLogout,
  });

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

  @override
  Widget build(BuildContext context) {
    final activeIcon = avatarIcons[activeAvatarIndex];

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
            // Avatar Selector Center Section
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
                        child: Icon(
                          activeIcon,
                          color: AppColors.textPrimary,
                          size: 44,
                        ),
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
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.black,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    avatarLabels[activeAvatarIndex],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'session: active_token_user',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // App UI Color Palette Section
            const Text(
              'APP UI COLORS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _buildColorsPalette(),

            const SizedBox(height: 32),

            // Privacy Policy Section
            const Text(
              'PRIVACY POLICY & DATA STORAGE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'On-Device Local Classification',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'TransactAI is built with a local-first security architecture. All banking transaction SMS alerts and text descriptions are processed strictly on-device. The classification engine utilizes offline deterministic rules, followed by a lightweight sequence model (DistilBERT), and falls back to SentenceTransformer semantic embeddings. No raw message texts, transaction logs, or personal financial details are uploaded to external cloud systems. User verification corrections are fed directly back into the local model for reinforcement learning. Your financial data is private and secure.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Sign Out CTA Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onLogout(); // Call logout callback
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.categoryHealthcare, width: 1.0),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Sign Out Session',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.categoryHealthcare,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildColorsPalette() {
    final List<Map<String, dynamic>> systemColors = [
      {'name': 'True Black', 'hex': '#000000', 'color': AppColors.background},
      {'name': 'Dark Surface', 'hex': '#121212', 'color': AppColors.surface},
      {'name': 'Muted Gray', 'hex': '#98989F', 'color': AppColors.textSecondary},
    ];

    final List<Map<String, dynamic>> accentColors = [
      {'name': 'Groceries', 'hex': '#10B981', 'color': AppColors.categoryGroceries},
      {'name': 'Healthcare', 'hex': '#EE5A24', 'color': AppColors.categoryHealthcare},
      {'name': 'Utilities', 'hex': '#0EA5E9', 'color': AppColors.categoryUtilities},
      {'name': 'Entertainment', 'hex': '#8B5CF6', 'color': AppColors.categoryEntertainment},
      {'name': 'Dining', 'hex': '#F43F5E', 'color': AppColors.categoryDining},
      {'name': 'Shopping', 'hex': '#F59E0B', 'color': AppColors.categoryShopping},
    ];

    return Column(
      children: [
        // System Core
        Row(
          children: systemColors.map((colorItem) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border, width: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colorItem['color'] as Color,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.borderBright, width: 0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      colorItem['name'] as String,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      colorItem['hex'] as String,
                      style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Accents Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 2.1,
          ),
          itemCount: accentColors.length,
          itemBuilder: (context, index) {
            final accentItem = accentColors[index];
            final color = accentItem['color'] as Color;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    accentItem['name'] as String,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accentItem['hex'] as String,
                    style: TextStyle(fontSize: 8, color: color.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showAvatarPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderBright,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'CHOOSE PROFILE PHOTO',
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
                  final isSelected = activeAvatarIndex == index;
                  return GestureDetector(
                    onTap: () {
                      onAvatarChanged(index);
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
        );
      },
    );
  }
}
