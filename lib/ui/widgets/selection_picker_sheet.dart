import 'package:flutter/material.dart';

import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import 'player_badges.dart';

/// What the manager chose in [showSelectionPickerSheet]: a player id, or null
/// to hand the slot back to the assistant.
class SelectionPick {
  const SelectionPick(this.playerId);

  final int? playerId;
}

/// Bottom sheet for filling one selection slot — a formation position or a
/// bench spot. Returns null when dismissed without choosing anything.
///
/// [position] is the slot the pick is for, or null for the bench: candidates
/// who can fill it are listed first, and keepers are only offered for the
/// goal. [slotLabels] maps squad ids to a short tag of where they already sit
/// in the plans ("XI · LM", "SUB") so a player is never double-booked by
/// accident.
Future<SelectionPick?> showSelectionPickerSheet(
  BuildContext context, {
  required String title,
  required List<Player> squad,
  required String? position,
  required int? currentPlayerId,
  required Map<int, String> slotLabels,
}) {
  return showModalBottomSheet<SelectionPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SelectionPickerSheet(
      title: title,
      squad: squad,
      position: position,
      currentPlayerId: currentPlayerId,
      slotLabels: slotLabels,
    ),
  );
}

class _SelectionPickerSheet extends StatelessWidget {
  const _SelectionPickerSheet({
    required this.title,
    required this.squad,
    required this.position,
    required this.currentPlayerId,
    required this.slotLabels,
  });

  final String title;
  final List<Player> squad;
  final String? position;
  final int? currentPlayerId;
  final Map<int, String> slotLabels;

  /// Whether [player] is listed as a candidate at all: keepers only guard the
  /// goal, and out-field slots never list a keeper because the match engine
  /// fields the keeper separately. The bench takes everyone.
  bool _listed(Player player) {
    if (position == null) return true;
    if (position == 'GK') return player.primaryPosition == 'GK';
    return player.primaryPosition != 'GK';
  }

  /// Fit players first, then non-injured by OVR, with the name as a stable
  /// final tiebreaker so the sheet never shuffles between builds.
  int _peckingOrder(Player a, Player b) {
    if (position != null) {
      final aFits = canFillSlot(a, position!);
      final bFits = canFillSlot(b, position!);
      if (aFits != bFits) return aFits ? -1 : 1;
    }
    if (a.isInjured != b.isInjured) return a.isInjured ? 1 : -1;
    if (a.ovr != b.ovr) return b.ovr.compareTo(a.ovr);
    return a.name.compareTo(b.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = [for (final p in squad) if (_listed(p)) p]
      ..sort(_peckingOrder);
    final fits = position == null
        ? const <Player>[]
        : [
            for (final p in ranked)
              if (canFillSlot(p, position!)) p,
          ];
    final others = [
      for (final p in ranked)
        if (!fits.contains(p)) p,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (currentPlayerId != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_search_outlined),
                title: const Text('Let the assistant pick'),
                onTap: () =>
                    Navigator.of(context).pop(const SelectionPick(null)),
              ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  if (position != null && fits.isNotEmpty)
                    _section(theme, 'Fits the slot'),
                  ...fits.map((p) => _tile(context, p)),
                  if (position != null && others.isNotEmpty)
                    _section(theme, 'Out of position'),
                  ...others.map((p) => _tile(context, p)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );

  Widget _tile(BuildContext context, Player player) {
    final theme = Theme.of(context);
    final slotLabel = slotLabels[player.id];
    final isCurrent = player.id == currentPlayerId;
    return ListTile(
      dense: true,
      leading: PlayerAvatar(player: player, radius: 16),
      title: Text(
        player.name,
        style: theme.textTheme.bodyMedium,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          PositionChip(position: player.primaryPosition),
          if (player.isInjured) ...[
            const SizedBox(width: 6),
            const InjuryChip(),
          ],
          if (slotLabel != null) ...[
            const SizedBox(width: 6),
            SelectionTag(label: slotLabel),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent) ...[
            Icon(Icons.check_circle,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          OvrBadge(ovr: player.ovr, size: 28),
        ],
      ),
      onTap: () => Navigator.of(context).pop(SelectionPick(player.id)),
    );
  }
}
