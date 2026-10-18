import 'package:flutter/material.dart';

import '../../core/models/player.dart';
import '../theme/app_theme.dart';

/// "12 Nov" — the year is implied by the season, so dates stay compact.
String shortDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

/// Color-coded OVR badge (elite green → poor red).
class OvrBadge extends StatelessWidget {
  const OvrBadge({super.key, required this.ovr, this.size = 34});

  final int ovr;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppTheme.ovrColorFor(brightness, ovr);
    final isDarkBg = brightness == Brightness.dark;
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

/// The red "INJ" flag that says a player is in the treatment room.
class InjuryChip extends StatelessWidget {
  const InjuryChip({super.key});

  static const _red = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'INJ',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: _red,
        ),
      ),
    );
  }
}

/// Tiny tag saying where a player currently sits in the matchday plans
/// ("XI · LM", "SUB"). [color] defaults to the theme's primary color.
class SelectionTag extends StatelessWidget {
  const SelectionTag({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: tint,
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
