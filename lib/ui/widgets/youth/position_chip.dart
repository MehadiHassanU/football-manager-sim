import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Green pill showing the position an academy prospect is developed as.
///
/// Deliberately distinct from the first-team [PositionChip]: prospects are
/// shown in academy green rather than the cyan used for squad players, so a
/// glance separates "in the academy" from "in the squad".
class YouthPositionChip extends StatelessWidget {
  const YouthPositionChip({super.key, required this.position, this.size = 34});

  final String position;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.pitchGreen.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: AppTheme.pitchGreen.withValues(alpha: 0.4)),
      ),
      child: Text(
        position,
        style: TextStyle(
          color: AppTheme.pitchGreen,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}
