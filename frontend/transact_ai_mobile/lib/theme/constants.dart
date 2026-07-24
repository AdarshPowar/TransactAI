import 'package:flutter/material.dart';

class AppColors {
  // Monochrome Core
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF2C2C2E);
  static const Color borderBright = Color(0xFF48484A);
  
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF98989F);
  static const Color textMuted = Color(0xFF545459);
  
  // Strategy Tags
  static const Color strategyRule = Color(0xFF00E676);
  static const Color strategyML = Color(0xFF2979FF);
  static const Color strategyHybrid = Color(0xFFFF9100);

  // Category Accents
  static const Color categoryGroceries = Color(0xFF10B981); // Emerald
  static const Color categoryHealthcare = Color(0xFFEE5A24); // Terracotta
  static const Color categoryUtilities = Color(0xFF0EA5E9); // Cyan
  static const Color categoryEntertainment = Color(0xFF8B5CF6); // Purple
  static const Color categoryDining = Color(0xFFF43F5E); // Rose
  static const Color categoryShopping = Color(0xFFF59E0B); // Amber
  static const Color categoryOther = Color(0xFF71717A); // Slate

  // category other
  static const Color categoryFuel = Color(0xFFEF4444);       // Red
  static const Color categoryTransport = Color(0xFF3B82F6);  // Blue  
  static const Color categoryMedical = Color(0xFFEC4899);    // Pink
  static const Color categoryBills = Color(0xFF14B8A6);      // Teal
  static const Color categorySalary = Color(0xFF22C55E);     // Green
  static const Color categorySubscription = Color(0xFFA855F7); // Violet
  static const Color categoryUpiTransfer = Color(0xFFF97316); // Orange
  static const Color categoryRefund = Color(0xFF06B6D4);     // Cyan

  // Retrieve category color dynamically
  static Color getCategoryColor(String category) {
  switch (category.toLowerCase().trim()) {
    case 'food':
    case 'dining':
    case 'dining/food':
      return categoryDining;
    case 'grocery':
    case 'groceries':
      return categoryGroceries;
    case 'fuel':
      return const Color.fromARGB(255, 208, 242, 54);
    case 'shopping':
      return categoryShopping;
    case 'medical':
    case 'healthcare':
      return const Color.fromARGB(255, 35, 45, 224);
    case 'bills':
    case 'utilities':
      return const Color.fromARGB(255, 129, 136, 135);
    case 'transport':
    case 'transportation':
      return const Color.fromARGB(255, 0, 0, 0);
    case 'refund':
      return const Color.fromARGB(255, 102, 6, 212);
    case 'salary':
      return const Color.fromARGB(255, 198, 201, 203);
    case 'subscription':
    case 'entertainment':
      return const Color.fromARGB(255, 159, 31, 155);
    case 'upi_transfer':
    case 'upi transfer':
    case 'fund transfer':
      return categoryUpiTransfer;
    default:
      return const Color.fromARGB(255, 255, 255, 255);
  }
}
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.textPrimary,
        secondary: AppColors.textSecondary,
        surface: AppColors.surface,
        onPrimary: AppColors.background,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.normal,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.normal,
          color: AppColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

