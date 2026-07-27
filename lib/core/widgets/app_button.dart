import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_shadows.dart';
import '../constants/app_constants.dart';

/// Custom button widget with multiple variants
enum AppButtonType { primary, secondary, outline, text, glass }

enum AppButtonSize { small, medium, large }

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonType type;
  final AppButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final IconData? icon;
  final Widget? trailingIcon;
  final Color? customColor;
  final double? width;
  final double? height;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = AppButtonType.primary,
    this.size = AppButtonSize.medium,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.trailingIcon,
    this.customColor,
    this.width,
    this.height,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppConstants.shortAnimationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading && !widget.isDisabled;

  void _onTapDown(TapDownDetails details) {
    if (_isEnabled) {
      _animationController.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (_isEnabled) {
      _animationController.reverse();
    }
  }

  void _onTapCancel() {
    if (_isEnabled) {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _isEnabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height ?? _getHeight(),
              decoration: _getDecoration(),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isEnabled ? widget.onPressed : null,
                  borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                  child: Container(
                    padding: _getPadding(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isLoading) ...[
                          SizedBox(
                            width: _getIconSize(),
                            height: _getIconSize(),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _getTextColor(),
                              ),
                            ),
                          ),
                          SizedBox(width: _getSpacing()),
                        ] else if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: _getIconSize(),
                            color: _getTextColor(),
                          ),
                          SizedBox(width: _getSpacing()),
                        ],
                        Flexible(
                          child: Text(
                            widget.text,
                            style: _getTextStyle(),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (widget.trailingIcon != null) ...[
                          SizedBox(width: _getSpacing()),
                          widget.trailingIcon!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _getDecoration() {
    final isEnabled = _isEnabled;

    switch (widget.type) {
      case AppButtonType.primary:
        return BoxDecoration(
          gradient: isEnabled ? AppColors.primaryGradient : null,
          color: isEnabled ? null : AppColors.greyLight,
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          boxShadow: isEnabled ? AppShadows.buttonShadow : null,
        );

      case AppButtonType.secondary:
        return BoxDecoration(
          color: isEnabled ? AppColors.accent : AppColors.greyLight,
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          boxShadow: isEnabled ? AppShadows.buttonShadow : null,
        );

      case AppButtonType.outline:
        return BoxDecoration(
          border: Border.all(
            color: isEnabled ? AppColors.primary : AppColors.greyLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          color: Colors.transparent,
        );

      case AppButtonType.text:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          color: Colors.transparent,
        );

      case AppButtonType.glass:
        return BoxDecoration(
          gradient: isEnabled ? AppColors.glassGradient : null,
          border: Border.all(
            color: AppColors.glassBorder,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          color: Colors.transparent,
        );
    }
  }

  Color _getTextColor() {
    if (!_isEnabled) return AppColors.textDisabled;

    switch (widget.type) {
      case AppButtonType.primary:
      case AppButtonType.secondary:
        return AppColors.white;
      case AppButtonType.outline:
      case AppButtonType.text:
      case AppButtonType.glass:
        return widget.customColor ?? AppColors.primary;
    }
  }

  TextStyle _getTextStyle() {
    final baseStyle = switch (widget.size) {
      AppButtonSize.small => AppTextStyles.buttonSmall,
      AppButtonSize.medium => AppTextStyles.buttonMedium,
      AppButtonSize.large => AppTextStyles.buttonLarge,
    };

    return baseStyle.copyWith(
      color: _getTextColor(),
    );
  }

  EdgeInsets _getPadding() {
    return switch (widget.size) {
      AppButtonSize.small => const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      AppButtonSize.medium => const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
      AppButtonSize.large => const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
    };
  }

  double _getHeight() {
    return switch (widget.size) {
      AppButtonSize.small => 38,
      AppButtonSize.medium => 44,
      AppButtonSize.large => 50,
    };
  }

  double _getIconSize() {
    return switch (widget.size) {
      AppButtonSize.small => 16,
      AppButtonSize.medium => 20,
      AppButtonSize.large => 24,
    };
  }

  double _getSpacing() {
    return switch (widget.size) {
      AppButtonSize.small => 6,
      AppButtonSize.medium => 8,
      AppButtonSize.large => 10,
    };
  }
}
