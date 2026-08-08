import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Custom color palette for Rayzon Solar app
class AppColors {
  // Brand Primary Color
  static const Color primary = Color(AppConstants.primaryColorValue);
  static const Color primaryLight = Color(0xFF0A6B7A);
  static const Color primaryDark = Color(0xFF07454F);

  // Accent Colors
  static const Color accent = Color(0xFF00BCD4);
  static const Color accentLight = Color(0xFF4DD0E1);
  static const Color accentDark = Color(0xFF0097A7);

  /// Distinct trail colors per trip leg (leg 0 = primary brand).
  static const List<Color> legTrailColors = [
    primary,
    Color(0xFFE65100), // deep orange
    Color(0xFF6A1B9A), // purple
    Color(0xFF2E7D32), // green
    Color(0xFFC62828), // red
    Color(0xFF1565C0), // blue
    Color(0xFF00838F), // cyan
    Color(0xFF4E342E), // brown
  ];

  static Color legTrailColor(int legIndex) =>
      legTrailColors[legIndex % legTrailColors.length];

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFF5F5F5);
  static const Color greyMedium = Color(0xFF757575);
  static const Color greyDark = Color(0xFF424242);

  // Background Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF8F9FA);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFB74D);
  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFE57373);
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFF64B5F6);

  // Status Specific Colors
  static const Color statusStartMissing = warning;
  static const Color statusEndMissing = info;
  static const Color statusCompleted = success;

  // Shadow Colors
  static const Color shadowLight = Color(0x1A000000);
  static const Color shadowMedium = Color(0x33000000);
  static const Color shadowDark = Color(0x4D000000);

  // Gradient Colors
  static const LinearGradient primaryGradient =
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, primaryLight]);

  static const LinearGradient glassGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x40FFFFFF), Color(0x20FFFFFF)]);

  // Glass Effect Colors
  static const Color glassBackground = Color(0x20FFFFFF);
  static const Color glassBorder = Color(0x30FFFFFF);

  // Overlay Colors
  static const Color imageOverlay = Color(0x80000000);
  static const Color loadingOverlay = Color(0x80000000);
}
