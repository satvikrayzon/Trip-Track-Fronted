import 'dart:math';

import 'package:flutter/material.dart';

import '../utils/device_utils.dart';
import '../utils/font_utils.dart';

/// Custom animated action button with gradient effects
class CustomActionButton extends StatefulWidget {
  final String text;
  final double? height;
  final double? fontSize;
  final VoidCallback onTap;
  final bool isOutLined;
  final Color? textColor;
  final bool isLoading;

  const CustomActionButton({
    super.key,
    required this.text,
    required this.onTap,
    this.height,
    this.fontSize,
    this.isOutLined = false,
    this.textColor,
    this.isLoading = false,
  });

  @override
  State<CustomActionButton> createState() => _CustomActionButtonState();
}

class _CustomActionButtonState extends State<CustomActionButton> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = !widget.isOutLined ? Colors.black87 : Colors.white;

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final glow = 0.6 + 0.4 * sin(_controller.value * pi);

        // Default styles for each variant
        final gradientColors = !widget.isOutLined
            ? [
                Colors.tealAccent.withOpacity(glow),
                Colors.teal.withOpacity(glow),
              ]
            : [Colors.redAccent.withOpacity(glow), Colors.red.withOpacity(glow)];

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12.scp(context)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12.scp(context)),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.scp(context)),
            ),
            onTap: widget.isLoading ? null : widget.onTap,
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: 16.scp(context),
                vertical: 8.scp(context),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12.scp(context)),
              ),
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        height: 20.scp(context),
                        width: 20.scp(context),
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        widget.text,
                        style: FontUtilities.style(
                          fontColor: widget.textColor ?? textColor,
                          fontWeight: FWT.bold,
                          fontSize: widget.fontSize ?? 16.scp(context),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
