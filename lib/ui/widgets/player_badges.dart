import 'package:flutter/material.dart';

import '../../core/models/player.dart';
import '../theme/app_theme.dart';

/// Color-coded OVR badge (elite green → poor red).
class OvrBadge extends StatelessWidget {
  const OvrBadge({super.key, required this.ovr, this.size = 34});

  final int ovr;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.ovrColor(ovr);
    final isDarkBg = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        '$ovr',
        style: TextStyle(
          color: isDarkBg
              ? Color.lerp(color, Colors.white, 0.55)
              : Color.lerp(color, Colors.black, 0.45),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Small uppercase position chip.
class PositionChip extends StatelessWidget {
  const PositionChip({super.key, required this.position});

  final String position;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        position,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

/// Circular avatar with the player's initials.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.player, this.radius = 18});

  final Player player;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = player.name.isNotEmpty
        ? player.name
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0] : '')
            .join()
            .toUpperCase()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
