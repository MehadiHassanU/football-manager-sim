import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Labelled 0-100 bar used on academy cards.
///
/// A thin variant of [MeterBar] with an optional right-hand annotation, so a
/// prospect card can say "First-team readiness · +12 to ceiling" in one line.
class YouthStatBar extends StatelessWidget {
  const YouthStatBar({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final double value;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flexible + ellipsis: a long label must never push the trailing
            // value off the card on a narrow screen.
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.08),
            valueColor:
                AlwaysStoppedAnimation(AppTheme.ovrColor(value.round())),
          ),
        ),
      ],
    );
  }
}
