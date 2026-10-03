import 'package:flutter/material.dart';

/// Placeholder card shown while the academy list is being rebuilt.
///
/// Uses a deterministic sweep rather than a random pulse: every line shares
/// one controller and each line offsets the phase, so the placeholder reads as
/// a single wave travelling down the card and does not flicker on rebuild.
class YouthSkeletonCard extends StatefulWidget {
  const YouthSkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  State<YouthSkeletonCard> createState() => _YouthSkeletonCardState();
}

class _YouthSkeletonCardState extends State<YouthSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0..1 pulse offset for line [index], so the sweep moves down the card.
  double _wave(int index) {
    final t = (_controller.value + index * 0.18) % 1.0;
    return (t < 0.5 ? t : 1 - t) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _block(base, 34, 34, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(child: _block(base, 120, 12)),
                  const SizedBox(width: 10),
                  _block(base, 30, 30, radius: 9),
                ],
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < widget.lines; i++) ...[
                _block(base, double.infinity, 8,
                    opacity: 0.05 + 0.07 * _wave(i)),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(
    Color base,
    double width,
    double height, {
    double radius = 6,
    double opacity = 0.08,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
