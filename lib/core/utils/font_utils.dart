import 'package:flutter/material.dart';

/// Font weight enumeration
enum FWT {
  /// FontWeight -> 900
  black,

  /// FontWeight -> 800
  extraBold,

  /// FontWeight -> 700
  bold,

  /// FontWeight -> 600
  semiBold,

  /// FontWeight -> 500
  medium,

  /// FontWeight -> 400
  regular,

  /// FontWeight -> 300
  light,

  /// FontWeight -> 200
  extraLight,

  /// FontWeight -> 100
  thin,
}

/// Font utilities for consistent text styling
class FontUtilities {
  static TextStyle style({
    required double fontSize,
    Color? fontColor,
    FWT fontWeight = FWT.regular,
    TextDecoration? decoration,
    double letterSpacing = 0.5,
    String? fontFamily,
  }) {
    return TextStyle(
      color: fontColor ?? const Color(0xFF494949),
      fontWeight: getFontWeight(fontWeight),
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      decoration: decoration,
      fontFamily: fontFamily ?? 'Outfit',
    );
  }
}

/// Convert FWT enum to FontWeight
FontWeight getFontWeight(FWT fwt) {
  switch (fwt) {
    case FWT.thin:
      return FontWeight.w100;
    case FWT.extraLight:
      return FontWeight.w200;
    case FWT.light:
      return FontWeight.w300;
    case FWT.regular:
      return FontWeight.w400;
    case FWT.medium:
      return FontWeight.w500;
    case FWT.semiBold:
      return FontWeight.w600;
    case FWT.bold:
      return FontWeight.w700;
    case FWT.extraBold:
      return FontWeight.w800;
    case FWT.black:
      return FontWeight.w900;
  }
}
