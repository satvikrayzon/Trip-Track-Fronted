import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PunchType {
  departure,
  arrival,
  meetingStart,
  meetingEnd,
}

extension PunchTypeX on PunchType {
  String get label => switch (this) {
        PunchType.departure => 'Punch Departure',
        PunchType.arrival => 'Punch Arrival',
        PunchType.meetingStart => 'Meeting Start',
        PunchType.meetingEnd => 'Meeting End',
      };

  IconData get icon => switch (this) {
        PunchType.departure => Icons.flight_takeoff_rounded,
        PunchType.arrival => Icons.flight_land_rounded,
        PunchType.meetingStart => Icons.groups_rounded,
        PunchType.meetingEnd => Icons.check_circle_rounded,
      };

  Color get color => switch (this) {
        PunchType.departure => const Color(0xFF2196F3),
        PunchType.arrival => const Color(0xFF4CAF50),
        PunchType.meetingStart => const Color(0xFFFF9800),
        PunchType.meetingEnd => const Color(0xFF095763),
      };
}

/// Large punch CTA with haptic feedback and success animation.
class PunchActionButton extends StatefulWidget {
  const PunchActionButton({
    super.key,
    required this.type,
    required this.onPressed,
    this.isLoading = false,
    this.enabled = true,
  });

  final PunchType type;
  final Future<bool> Function() onPressed;
  final bool isLoading;
  final bool enabled;

  @override
  State<PunchActionButton> createState() => _PunchActionButtonState();
}

class _PunchActionButtonState extends State<PunchActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.enabled || widget.isLoading) return;
    HapticFeedback.mediumImpact();
    final ok = await widget.onPressed();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      setState(() => _success = true);
      await _controller.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _success = false);
    } else {
      HapticFeedback.vibrate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.type.color;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _success ? 1.0 + (_controller.value * 0.04) : 1.0;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Material(
        color: widget.enabled ? color : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(18),
        elevation: widget.enabled ? 4 : 0,
        shadowColor: color.withValues(alpha: 0.35),
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                else if (_success)
                  const Icon(Icons.check_rounded, color: Colors.white, size: 26)
                else
                  Icon(widget.type.icon, color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Text(
                  _success ? 'Confirmed!' : widget.type.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
