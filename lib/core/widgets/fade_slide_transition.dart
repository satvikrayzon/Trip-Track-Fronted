import 'package:flutter/material.dart';

/// Animation direction enum
enum AnimationDirection { up, down, left, right }

/// Fade and slide transition widget for smooth animations
class FadeSlideTransition extends StatefulWidget {
  final Widget child;
  final int? milliseconds;
  final AnimationDirection direction;
  final Curve curve;

  const FadeSlideTransition({
    super.key,
    required this.child,
    this.milliseconds,
    this.direction = AnimationDirection.up,
    this.curve = Curves.easeOut,
  });

  @override
  State<FadeSlideTransition> createState() => _FadeSlideTransitionState();
}

class _FadeSlideTransitionState extends State<FadeSlideTransition> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.milliseconds ?? 800),
    );

    final offset = _getBeginOffset(widget.direction);

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _slideAnim = Tween<Offset>(begin: offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _controller.forward();
  }

  Offset _getBeginOffset(AnimationDirection dir) {
    switch (dir) {
      case AnimationDirection.up:
        return const Offset(0, 0.3);
      case AnimationDirection.down:
        return const Offset(0, -0.3);
      case AnimationDirection.left:
        return const Offset(0.3, 0);
      case AnimationDirection.right:
        return const Offset(-0.3, 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: widget.child,
      ),
    );
  }
}
