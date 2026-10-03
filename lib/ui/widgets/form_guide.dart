import 'package:flutter/material.dart';

import '../../core/models/team.dart';

/// Horizontal W/D/L form pills for a team's recent results.
///
/// [results] holds 1/3/0 values (win/draw/loss); renders at most the last 5.
class FormGuide extends StatelessWidget {
  const FormGuide({super.key, required this.results, this.team});

  final List<int> results;
  final Team? team;

  @override
  Widget build(BuildContext context) {
    final recent = results.length > 5 ? results.sublist(results.length - 5) : results;
    if (recent.isEmpty) {
      return Text('No matches yet',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final r in recent) _pill(context, r)],
    );
  }

  Widget _pill(BuildContext context, int result) {
    final (label, color) = switch (result) {
      3 => ('W', const Color(0xFF00C853)),
      1 => ('D', const Color(0xFFFFB74D)),
      _ => ('L', const Color(0xFFEF5350)),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}
