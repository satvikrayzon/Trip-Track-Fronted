import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// Custom input field widget with various styles and validation
enum AppInputType { text, email, password, phone, number, multiline }

class AppInputField extends StatefulWidget {
  final String label;
  final String? hint;
  final String? initialValue;
  final TextEditingController? controller;
  final AppInputType type;
  final bool isRequired;
  final bool isEnabled;
  final bool isReadOnly;
  final int? maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final EdgeInsets? contentPadding;

  const AppInputField({
    super.key,
    required this.label,
    this.hint,
    this.initialValue,
    this.controller,
    this.type = AppInputType.text,
    this.isRequired = false,
    this.isEnabled = true,
    this.isReadOnly = false,
    this.maxLines,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.inputFormatters,
    this.textInputAction,
    this.focusNode,
    this.contentPadding,
  });

  @override
  State<AppInputField> createState() => _AppInputFieldState();
}

class _AppInputFieldState extends State<AppInputField>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _focusAnimation;
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _isObscured = true;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppConstants.shortAnimationDuration,
      vsync: this,
    );

    _focusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TextEditingController();

    if (widget.initialValue != null && _controller.text.isEmpty) {
      _controller.text = widget.initialValue!;
    }

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });

    if (_isFocused) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _toggleObscure() {
    setState(() {
      _isObscured = !_isObscured;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _focusAnimation,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            if (widget.label.isNotEmpty) ...[
              Text(
                widget.label,
                style: AppTextStyles.inputLabel.copyWith(
                  color:
                      _isFocused ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
            ],

            // Input Container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              ),
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                obscureText:
                    widget.type == AppInputType.password ? _isObscured : false,
                enabled: widget.isEnabled && !widget.isReadOnly,
                readOnly: widget.isReadOnly,
                maxLines: widget.maxLines ??
                    (widget.type == AppInputType.multiline ? 4 : 1),
                maxLength: widget.maxLength,
                keyboardType: _getKeyboardType(),
                textInputAction:
                    widget.textInputAction ?? _getTextInputAction(),
                inputFormatters:
                    widget.inputFormatters ?? _getInputFormatters(),
                onChanged: widget.onChanged,
                onFieldSubmitted: widget.onSubmitted,
                onTap: widget.onTap,
                validator: widget.validator,
                style: AppTextStyles.inputText.copyWith(
                  color: widget.isEnabled
                      ? AppColors.textPrimary
                      : AppColors.textDisabled,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: AppTextStyles.secondaryMedium,
                  prefixIcon: widget.prefixIcon != null
                      ? Icon(
                          widget.prefixIcon,
                          color: _isFocused
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 20,
                        )
                      : null,
                  suffixIcon: _buildSuffixIcon(),
                  filled: true,
                  fillColor: widget.isEnabled
                      ? AppColors.surfaceVariant
                      : AppColors.greyLight,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 2,
                    ),
                  ),
                  contentPadding: widget.contentPadding ??
                      const EdgeInsets.symmetric(
                        horizontal: AppConstants.defaultPadding,
                        vertical: AppConstants.defaultPadding,
                      ),
                  counterText: '',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget? _buildSuffixIcon() {
    if (widget.type == AppInputType.password) {
      return IconButton(
        icon: Icon(
          _isObscured ? Icons.visibility_off : Icons.visibility,
          color: AppColors.textSecondary,
          size: 20,
        ),
        onPressed: _toggleObscure,
      );
    }

    return widget.suffixIcon;
  }

  TextInputType _getKeyboardType() {
    switch (widget.type) {
      case AppInputType.email:
        return TextInputType.emailAddress;
      case AppInputType.phone:
        return TextInputType.phone;
      case AppInputType.number:
        return TextInputType.number;
      case AppInputType.multiline:
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  TextInputAction _getTextInputAction() {
    switch (widget.type) {
      case AppInputType.multiline:
        return TextInputAction.newline;
      case AppInputType.password:
        return TextInputAction.done;
      default:
        return TextInputAction.next;
    }
  }

  List<TextInputFormatter> _getInputFormatters() {
    switch (widget.type) {
      case AppInputType.phone:
        return [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ];
      case AppInputType.number:
        return [FilteringTextInputFormatter.digitsOnly];
      case AppInputType.email:
        return [FilteringTextInputFormatter.deny(RegExp(r'[ ]'))];
      default:
        return [];
    }
  }
}

/// Specialized dropdown input field
class AppDropdownField<T> extends StatefulWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final bool isRequired;
  final bool isEnabled;
  final IconData? prefixIcon;
  final String? hint;

  const AppDropdownField({
    super.key,
    required this.label,
    this.value,
    required this.items,
    this.onChanged,
    this.validator,
    this.isRequired = false,
    this.isEnabled = true,
    this.prefixIcon,
    this.hint,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _focusAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppConstants.shortAnimationDuration,
      vsync: this,
    );

    _focusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
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

  void _onFocusChange(bool hasFocus) {
    setState(() {
      _isFocused = hasFocus;
    });

    if (_isFocused) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _focusAnimation,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            if (widget.label.isNotEmpty) ...[
              Text(
                widget.label,
                style: AppTextStyles.inputLabel.copyWith(
                  color:
                      _isFocused ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
            ],

            // Dropdown Container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                boxShadow: _isFocused
                    ? AppShadows.inputShadowFocused
                    : AppShadows.inputShadow,
              ),
              child: DropdownButtonFormField<T>(
                value: widget.value,
                items: widget.items,
                onChanged: widget.isEnabled ? widget.onChanged : null,
                validator: widget.validator,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: AppTextStyles.secondaryMedium,
                  prefixIcon: widget.prefixIcon != null
                      ? Icon(
                          widget.prefixIcon,
                          color: _isFocused
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 20,
                        )
                      : null,
                  filled: true,
                  fillColor: widget.isEnabled
                      ? AppColors.surfaceVariant
                      : AppColors.greyLight,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.defaultPadding,
                    vertical: AppConstants.defaultPadding,
                  ),
                ),
                style: AppTextStyles.inputText.copyWith(
                  color: widget.isEnabled
                      ? AppColors.textPrimary
                      : AppColors.textDisabled,
                ),
                onTap: () => _onFocusChange(true),
              ),
            ),
          ],
        );
      },
    );
  }
}
