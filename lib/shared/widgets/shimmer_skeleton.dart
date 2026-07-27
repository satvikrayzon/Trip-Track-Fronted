import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton placeholder with shimmer for loading states.
class ShimmerSkeleton extends StatelessWidget {
  const ShimmerSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade800
        : Colors.grey.shade300;
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade700
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1200),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerSkeleton(width: double.infinity, height: 140, borderRadius: 20),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: ShimmerSkeleton(width: double.infinity, height: 88)),
              const SizedBox(width: 12),
              Expanded(child: ShimmerSkeleton(width: double.infinity, height: 88)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ShimmerSkeleton(width: double.infinity, height: 88)),
              const SizedBox(width: 12),
              Expanded(child: ShimmerSkeleton(width: double.infinity, height: 88)),
            ],
          ),
          const SizedBox(height: 24),
          const ShimmerSkeleton(width: 120, height: 20),
          const SizedBox(height: 12),
          ...List.generate(
            3,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ShimmerSkeleton(width: double.infinity, height: 72),
            ),
          ),
        ],
      ),
    );
  }
}
