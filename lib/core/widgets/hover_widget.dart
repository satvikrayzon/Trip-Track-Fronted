import 'package:flutter/material.dart';

/// Wraps a widget to add hover lift and scale animation (ideal for web/desktop interactions).
class HoverWidget extends StatefulWidget {
  final Widget child;
  final double scale;
  final double translateUp;
  final Duration duration;

  const HoverWidget({
    super.key,
    required this.child,
    this.scale = 1.015,
    this.translateUp = 3.0,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<HoverWidget> createState() => _HoverWidgetState();
}

class _HoverWidgetState extends State<HoverWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, _isHovered ? -widget.translateUp : 0.0)
          ..scale(_isHovered ? widget.scale : 1.0),
        child: widget.child,
      ),
    );
  }
}
