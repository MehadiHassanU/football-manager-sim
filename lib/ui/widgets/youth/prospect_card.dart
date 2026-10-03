import 'package:flutter/material.dart';

import '../../../core/models/youth_player.dart';
import '../../theme/app_theme.dart';
import '../player_badges.dart';
import 'position_chip.dart';
import 'stat_bar.dart';

/// Card for a single academy prospect.
///
/// Shows what a manager actually decides on: who he is, the position he is
/// being developed as, how close he is to first-team football today and how
/// much ceiling is left. [YouthPlayer.scoutReport] supplies the summary so the
/// card never invents an opinion the model does not back.
class ProspectCard extends StatelessWidget {
  const ProspectCard({
    super.key,
    required this.prospect,
    required this.onPromote,
    required this.onRelease,
  });

  final YouthPlayer prospect;
  final VoidCallback onPromote;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = prospect.potential - prospect.currentStats;
    final attributes = prospect.keyAttributeNames;
    final values = prospect.keyAttributeValues();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YouthPositionChip(position: prospect.position),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prospect.name,
                        style:
                            theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${prospect.age} yrs · ${prospect.nationality}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    OvrBadge(ovr: prospect.currentStats, size: 30),
                    Text(
                      'POT ${prospect.potential}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            YouthStatBar(
              label: 'First-team readiness',
              value: prospect.currentStats.toDouble(),
              trailing: gap > 0 ? '+$gap to ceiling' : 'at ceiling',
            ),
            const SizedBox(height: 10),
            Text(prospect.scoutReport(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < attributes.length; i++)
                        _KeyAttribute(name: attributes[i], value: values[i]),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Promote to first team',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  color: AppTheme.pitchGreen,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: onPromote,
                ),
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    if (v == 'promote') onPromote();
                    if (v == 'release') onRelease();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'promote', child: Text('Promote')),
                    PopupMenuItem(value: 'release', child: Text('Release')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the prospect's three headline attributes, e.g. "84 Finishing".
class _KeyAttribute extends StatelessWidget {
  const _KeyAttribute({required this.name, required this.value});

  final String name;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 3),
        Text(name, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
