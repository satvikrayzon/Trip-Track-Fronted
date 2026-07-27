import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Custom shadow styles for the Rayzon Solar app
class AppShadows {
  // Light Shadows
  static const BoxShadow light = BoxShadow(
    color: AppColors.shadowLight,
    offset: Offset(0, 1),
    blurRadius: 3,
    spreadRadius: 0,
  );

  static const BoxShadow lightUp = BoxShadow(
    color: AppColors.shadowLight,
    offset: Offset(0, -1),
    blurRadius: 3,
    spreadRadius: 0,
  );

  // Medium Shadows
  static const BoxShadow medium = BoxShadow(
    color: AppColors.shadowMedium,
    offset: Offset(0, 2),
    blurRadius: 6,
    spreadRadius: 0,
  );

  static const BoxShadow mediumUp = BoxShadow(
    color: AppColors.shadowMedium,
    offset: Offset(0, -2),
    blurRadius: 6,
    spreadRadius: 0,
  );

  // Large Shadows
  static const BoxShadow large = BoxShadow(
    color: AppColors.shadowMedium,
    offset: Offset(0, 4),
    blurRadius: 12,
    spreadRadius: 0,
  );

  static const BoxShadow largeUp = BoxShadow(
    color: AppColors.shadowMedium,
    offset: Offset(0, -4),
    blurRadius: 12,
    spreadRadius: 0,
  );

  // Card Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> cardShadowHover = [
    BoxShadow(
      color: AppColors.shadowMedium,
      offset: Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  // Button Shadows
  static const List<BoxShadow> buttonShadow = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> buttonShadowPressed = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  // Floating Action Button Shadow
  static const List<BoxShadow> fabShadow = [
    BoxShadow(
      color: AppColors.shadowMedium,
      offset: Offset(0, 4),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  // App Bar Shadow
  static const List<BoxShadow> appBarShadow = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 1),
      blurRadius: 3,
      spreadRadius: 0,
    ),
  ];

  // Bottom Sheet Shadow
  static const List<BoxShadow> bottomSheetShadow = [
    BoxShadow(
      color: AppColors.shadowMedium,
      offset: Offset(0, -2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  // Dialog Shadow
  static const List<BoxShadow> dialogShadow = [
    BoxShadow(
      color: AppColors.shadowDark,
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: 0,
    ),
  ];

  // Image Overlay Shadow
  static const List<BoxShadow> imageOverlayShadow = [
    BoxShadow(
      color: AppColors.imageOverlay,
      offset: Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  // Custom elevation-based shadows
  static List<BoxShadow> elevation(int elevation) {
    switch (elevation) {
      case 1:
        return [light];
      case 2:
        return [medium];
      case 4:
        return [large];
      case 8:
        return [
          const BoxShadow(
            color: AppColors.shadowDark,
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ];
      case 16:
        return [
          const BoxShadow(
            color: AppColors.shadowDark,
            offset: Offset(0, 16),
            blurRadius: 32,
            spreadRadius: 0,
          ),
        ];
      default:
        return [medium];
    }
  }

  // Glass effect shadow
  static const List<BoxShadow> glassShadow = [
    BoxShadow(
      color: AppColors.glassBorder,
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  // Status badge shadows
  static const List<BoxShadow> statusBadgeShadow = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  // Input field shadow
  static const List<BoxShadow> inputShadow = [
    BoxShadow(
      color: AppColors.shadowLight,
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> inputShadowFocused = [
    BoxShadow(
      color: AppColors.primaryLight,
      offset: Offset(0, 0),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];
}
