import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/tactic_definitions.dart';
import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import '../../core/models/youth_player.dart';
import '../../providers/career_session_provider.dart';
import '../../ui/ui.dart';
import '../transfer_market/transfer_market_screen.dart';

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  String _sortKey = 'ovr';
  String _filterPosition = 'All';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Squad')),
        body: const EmptyState(
          icon: Icons.groups_outlined,
          title: 'No active career',
          message: 'Start a career first to manage a squad.',
        ),
      );
    }

    final team = session.team;
    final squad = _filteredSquad(team.squad);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(team.name),
          // Non-scrollable (the default fill alignment) so the four tabs share
          // the width evenly instead of hugging the left edge.
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.groups_outlined), text: 'Squad'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Transfers'),
              Tab(icon: Icon(Icons.flag_outlined), text: 'Tactics'),
              Tab(icon: Icon(Icons.sports_soccer_outlined), text: 'Youth'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _squadTab(context, session, squad, team.squad),
            _transfersTab(context),
            _TacticsTab(session: session),
            _youthTab(context, session),
          ],
        ),
      ),
    );
  }

  List<Player> _filteredSquad(List<Player> squad) {
    var result = squad.where((p) {
      if (_filterPosition == 'All') return true;
      if (_filterPosition == 'GK') return p.primaryPosition == 'GK';
      return p.primaryPosition != 'GK';
    }).toList();
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result =
          result.where((p) => p.name.toLowerCase().contains(query)).toList();
    }
    int compare(Player a, Player b) => switch (_sortKey) {
          'name' => a.name.compareTo(b.name),
          'age' => a.age.compareTo(b.age),
          'fitness' => b.fitness.compareTo(a.fitness),
          _ => b.ovr.compareTo(a.ovr),
        };
    result.sort(compare);
    return result;
  }

  Widget _squadTab(
    BuildContext context,
    CareerSession session,
    List<Player> squad,
    List<Player> allPlayers,
  ) {
    final totalCount = allPlayers.length;
    // One OVR rank pass per build; each row used to copy + sort the whole
    // squad inside the list builder.
    final rankIndex = squadRankIndex(allPlayers);
    // Who would walk out for kick-off right now: the squad list flags the XI
    // and the substitutes so the matchday plans are visible without opening
    // the tactics tab.
    final xiIds = {
      for (final p in resolveStartingEleven(
        allPlayers,
        session.tactic.formation,
        session.startXI,
        reservedIds: _benchReserved(session.benchIds),
      ))
        p.id,
    };
    final subIds = {
      for (final p in resolveBenchPlayers(allPlayers, xiIds, session.benchIds))
        p.id,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search players…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                initialValue: _sortKey,
                icon: const Icon(Icons.sort),
                onSelected: (v) => setState(() => _sortKey = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'ovr', child: Text('Sort: OVR')),
                  PopupMenuItem(value: 'name', child: Text('Sort: Name')),
                  PopupMenuItem(value: 'age', child: Text('Sort: Age')),
                  PopupMenuItem(value: 'fitness', child: Text('Sort: Fitness')),
                ],
              ),
              PopupMenuButton<String>(
                initialValue: _filterPosition,
                icon: const Icon(Icons.filter_alt_outlined),
                onSelected: (v) => setState(() => _filterPosition = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'All', child: Text('All players')),
                  PopupMenuItem(value: 'GK', child: Text('Goalkeepers')),
                  PopupMenuItem(value: 'Outfield', child: Text('Outfield')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('${squad.length} of $totalCount players',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/transfers'),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Hub'),
              ),
            ],
          ),
        ),
        Expanded(
          child: squad.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search,
                  title: 'No players match',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: squad.length,
                  itemBuilder: (context, index) {
                    final player = squad[index];
                    return _PlayerCard(
                      player: player,
                      // The rank index is computed once per build; per-row
                      // squad copies + sorts used to run at scroll speed.
                      status: squadStatusOf(player, allPlayers,
                          rankIndex: rankIndex),
                      tag: xiIds.contains(player.id)
                          ? 'XI'
                          : subIds.contains(player.id)
                              ? 'SUB'
                              : null,
                      onTap: () => showPlayerDetailSheet(context, player),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _transfersTab(BuildContext context) {
    // The market is the destination: opening this tab shows the live market
    // instead of an empty state whose only job was to link to another screen
    // that shows exactly the same list.
    return const TransferMarketBody();
  }

  Widget _youthTab(BuildContext context, CareerSession session) {
    final youth = [...session.youthPlayers]
      ..sort((a, b) => b.potential.compareTo(a.potential));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${youth.length} prospect${youth.length == 1 ? '' : 's'} in the academy',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _runIntake(context),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Intake ×3'),
              ),
            ],
          ),
        ),
        Expanded(
          child: youth.isEmpty
              ? EmptyState(
                  icon: Icons.school_outlined,
                  title: 'No youth prospects yet',
                  message: 'Run an intake to scout three new prospects.',
                  action: PrimaryButton(
                    label: 'Run Youth Intake',
                    icon: Icons.auto_awesome,
                    onPressed: () => _runIntake(context),
                  ),
                )
              // One skeleton card while the list settles keeps the layout from
              // jumping when the first intake lands.
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: youth.length,
                  itemBuilder: (context, index) {
                    final prospect = youth[index];
                    return ProspectCard(
                      prospect: prospect,
                      onPromote: () => _promote(context, prospect),
                      onRelease: () => _release(context, prospect),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _runIntake(BuildContext context) {
    addYouthProspect(ref, count: 3);
    // The academy list repaints immediately, so this is only a confirmation.
    // Hiding the current one first stops repeated taps queueing a toast per
    // tap, which previously trailed the manager across every screen.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('3 new prospects joined the academy'),
        ),
      );
  }

  Future<void> _promote(BuildContext context, YouthPlayer prospect) async {
    final ok = await _confirm(
      context,
      title: 'Promote ${prospect.name}?',
      body: 'He joins the first-team squad at his current ability '
          '(${prospect.currentStats} OVR, ${prospect.position}).',
      confirm: 'Promote',
    );
    if (ok != true || !context.mounted) return;
    promoteYouthPlayer(ref, prospect);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${prospect.name} promoted to the first team')),
    );
  }

  Future<void> _release(BuildContext context, YouthPlayer prospect) async {
    final ok = await _confirm(
      context,
      title: 'Release ${prospect.name}?',
      body: 'He leaves the academy. This cannot be undone.',
      confirm: 'Release',
    );
    if (ok != true || !context.mounted) return;
    releaseYouthPlayer(ref, prospect);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${prospect.name} released')),
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
  }
}

/// Tactics command centre.
///
/// Two halves: the shape (formation + the eleven the shape actually picks)
/// and the instructions (four category tabs over the real [Tactic] fields).
/// Nothing here invents a role or duty system — every control writes to a
/// field the model already has, and the formation is the same value the match
/// screen selects the XI from.
class _TacticsTab extends ConsumerStatefulWidget {
  const _TacticsTab({required this.session});

  final CareerSession session;

  @override
  ConsumerState<_TacticsTab> createState() => _TacticsTabState();
}

class _TacticsTabState extends ConsumerState<_TacticsTab> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Tactic get _tactic => ref.read(careerSessionProvider)!.tactic;

  void _apply(Tactic next) {
    final session = ref.read(careerSessionProvider)!;
    if (next.formation != session.tactic.formation) {
      // Carry the manager's picks into the new shape: same slot when the
      // position still fits, first free compatible slot otherwise.
      session.startXI = reconcileXiPicks(
        session.startXI,
        session.tactic.formation,
        next.formation,
        session.team.squad,
      );
    }
    session.tactic = next;
    // Re-emit a shallow copy: StateProvider only notifies listeners when the
    // value is a different instance, so assigning `session` was a no-op.
    notifySessionChanged(ref);
    setState(() {});
  }

  /// Stores the manager's pick for one shape slot (or hands it back to the
  /// assistant when [playerId] is null), keeping the sparse list tidy.
  void _assignXiSlot(int index, int? playerId) {
    final session = ref.read(careerSessionProvider)!;
    final layout =
        kFormationLayouts[session.tactic.formation] ?? const <PitchPosition>[];
    if (index >= layout.length) return;
    final next = List<int>.generate(
      layout.length,
      (i) => _storedPick(session.startXI, i),
      growable: true,
    );
    if (playerId != null) {
      // A player can only stand in one place: clear any other slot holding
      // him, and pull him off the bench.
      for (var i = 0; i < next.length; i++) {
        if (i != index && next[i] == playerId) next[i] = 0;
      }
      session.benchIds.remove(playerId);
    }
    next[index] = playerId ?? 0;
    session.startXI = _withoutTrailingZeros(next);
    notifySessionChanged(ref);
    setState(() {});
  }

  /// Hands the whole XI back to the assistant.
  void _autoPickXi() {
    final session = ref.read(careerSessionProvider)!;
    session.startXI = [];
    notifySessionChanged(ref);
    setState(() {});
  }

  /// Stores the manager's pick for one bench spot.
  void _assignBenchSlot(int index, int? playerId) {
    final session = ref.read(careerSessionProvider)!;
    final slots = resolveBenchSlots(
      session.team.squad,
      _fieldedIds(session),
      session.benchIds,
    );
    if (index >= slots.length) return;
    final next = List<int>.generate(
      slots.length,
      (i) => _storedPick(session.benchIds, i),
      growable: true,
    );
    if (playerId != null) {
      for (var i = 0; i < next.length; i++) {
        if (i != index && next[i] == playerId) next[i] = 0;
      }
      // Naming a starter on the bench moves him out of the XI.
      final startXI = List<int>.generate(
        kFormationLayouts[session.tactic.formation]?.length ?? 0,
        (i) => _storedPick(session.startXI, i),
        growable: true,
      );
      var changed = false;
      for (var i = 0; i < startXI.length; i++) {
        if (startXI[i] == playerId) {
          startXI[i] = 0;
          changed = true;
        }
      }
      if (changed) {
        session.startXI = _withoutTrailingZeros(startXI);
      }
    }
    next[index] = playerId ?? 0;
    session.benchIds = _withoutTrailingZeros(next);
    notifySessionChanged(ref);
    setState(() {});
  }

  /// Hands the whole bench back to the assistant.
  void _autoPickBench() {
    final session = ref.read(careerSessionProvider)!;
    session.benchIds = [];
    notifySessionChanged(ref);
    setState(() {});
  }

  /// Who is in the resolved XI right now — the set the bench is built from.
  Set<int> _fieldedIds(CareerSession session) => {
        for (final p in resolveStartingEleven(
          session.team.squad,
          session.tactic.formation,
          session.startXI,
          reservedIds: _benchReserved(session.benchIds),
        ))
          p.id,
      };

  /// Where every squad member already stands in the matchday plans, for the
  /// picker sheet's tags.
  Map<int, String> _selectionLabels(CareerSession session) {
    final labels = <int, String>{};
    final layout =
        kFormationLayouts[session.tactic.formation] ?? const <PitchPosition>[];
    for (var i = 0; i < layout.length; i++) {
      final id = _storedPick(session.startXI, i);
      if (id > 0) labels[id] = 'XI · ${layout[i].position}';
    }
    for (var i = 0; i < session.benchIds.length; i++) {
      final id = _storedPick(session.benchIds, i);
      if (id > 0) labels[id] = 'SUB';
    }
    return labels;
  }

  Widget _benchChip(ThemeData theme, int index, BenchSlot slot) {
    final player = slot.player;
    return ActionChip(
      key: ValueKey('bench-slot-$index'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: slot.manual
          ? BorderSide(color: theme.colorScheme.primary, width: 1.4)
          : null,
      label: Text(
        player == null ? '—' : '${player.primaryPosition} ${_shortName(player.name)}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: (player?.isInjured ?? false) ? const Color(0xFFEF5350) : null,
          fontWeight: player == null ? null : FontWeight.w600,
        ),
      ),
      onPressed: () => _openBenchPicker(index),
    );
  }

  Future<void> _openXiPicker(int index) async {
    final session = ref.read(careerSessionProvider)!;
    final layout =
        kFormationLayouts[session.tactic.formation] ?? const <PitchPosition>[];
    if (index >= layout.length) return;

    final currentId = _storedPick(session.startXI, index);
    final picked = await showSelectionPickerSheet(
      context,
      title: 'Pick ${layout[index].position}',
      squad: session.team.squad,
      position: layout[index].position,
      currentPlayerId: currentId > 0 ? currentId : null,
      slotLabels: _selectionLabels(session),
    );
    if (picked == null || !mounted) return;
    _assignXiSlot(index, picked.playerId);
  }

  Future<void> _openBenchPicker(int index) async {
    final session = ref.read(careerSessionProvider)!;
    final currentId = _storedPick(session.benchIds, index);
    final picked = await showSelectionPickerSheet(
      context,
      title: 'Pick substitute',
      squad: session.team.squad,
      position: null,
      currentPlayerId: currentId > 0 ? currentId : null,
      slotLabels: _selectionLabels(session),
    );
    if (picked == null || !mounted) return;
    _assignBenchSlot(index, picked.playerId);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider)!;
    final tactic = session.tactic;
    final saved = ref.watch(savedTacticsProvider);
    final slots = resolveFormationSlots(
      session.team.squad,
      tactic.formation,
      session.startXI,
      reservedIds: _benchReserved(session.benchIds),
    );
    final manualPicks = session.startXI.where((id) => id > 0).length;
    final replaced = slots.where((s) => s.replaced).length;
    final theme = Theme.of(context);
    final bench = resolveBenchSlots(
      session.team.squad,
      {
        for (final s in slots)
          if (s.player != null) s.player!.id,
      },
      session.benchIds,
    );
    final benchManual = session.benchIds.where((id) => id > 0).length;
    // A spare keeper who is neither starting nor named: worth a quiet nudge.
    final missingKeeperCover = bench.isNotEmpty &&
        session.team.squad.any((p) =>
            p.primaryPosition == 'GK' &&
            !slots.any((s) => s.player?.id == p.id) &&
            !bench.any((b) => b.player?.id == p.id));

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in Formation.values) ...[
                    ChoiceChip(
                      label: Text(_formationLabel(f)),
                      selected: tactic.formation == f,
                      onSelected: (_) => _apply(tactic.copyWith(formation: f)),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    switch ((manualPicks, replaced)) {
                      (0, _) =>
                        'Picked by your assistant — tap a player to change',
                      (_, 0) => 'Manual XI · $manualPicks of ${slots.length} picked',
                      _ => 'Manual XI · $replaced of $manualPicks picks out of action',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: replaced > 0 ? theme.colorScheme.error : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (manualPicks > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _autoPickXi,
                    child: const Text('Auto-pick'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: PitchPreview(
              slots: slots,
              formation: tactic.formation,
              height: _pitchHeight(context),
              onSlotTap: _openXiPicker,
            ),
          ),
          if (bench.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'SUBS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    if (missingKeeperCover) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'No goalkeeper on the bench',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    for (var i = 0; i < bench.length; i++) ...[
                      _benchChip(theme, i, bench[i]),
                      const SizedBox(width: 6),
                    ],
                    if (benchManual > 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _autoPickBench,
                        child: const Text('Auto'),
                      ),
                  ],
                ),
              ),
            ),
          const TabBar(
            tabs: [
              Tab(text: 'Approach'),
              Tab(text: 'Pressing'),
              Tab(text: 'Build-up'),
              Tab(text: 'Transitions'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _category(
                  children: [
                    _enumDropdown<PlayingStyle>(
                      'Playing style',
                      PlayingStyle.values,
                      tactic.playingStyle,
                      (v) => _apply(tactic.copyWith(playingStyle: v)),
                    ),
                    _enumDropdown<Tempo>(
                      'Tempo',
                      Tempo.values,
                      tactic.tempo,
                      (v) => _apply(tactic.copyWith(tempo: v)),
                      hint: 'Tempo changes how quickly match events arrive.',
                    ),
                    _enumDropdown<PossessionFocus>(
                      'Possession focus',
                      PossessionFocus.values,
                      tactic.possessionFocus,
                      (v) => _apply(tactic.copyWith(possessionFocus: v)),
                    ),
                  ],
                ),
                _category(
                  children: [
                    _enumDropdown<PressingIntensity>(
                      'Pressing',
                      PressingIntensity.values,
                      tactic.pressing,
                      (v) => _apply(tactic.copyWith(pressing: v)),
                    ),
                    _enumDropdown<DefensiveLine>(
                      'Defensive line',
                      DefensiveLine.values,
                      tactic.defensiveLine,
                      (v) => _apply(tactic.copyWith(defensiveLine: v)),
                    ),
                    SwitchListTile(
                      title: const Text('Counter press'),
                      value: tactic.counterPress,
                      onChanged: (v) =>
                          _apply(tactic.copyWith(counterPress: v)),
                    ),
                  ],
                ),
                _category(
                  children: [
                    _enumDropdown<Width>(
                      'Width',
                      Width.values,
                      tactic.width,
                      (v) => _apply(tactic.copyWith(width: v)),
                    ),
                    _enumDropdown<PossessionFocus>(
                      'Build-up',
                      PossessionFocus.values,
                      tactic.possessionFocus,
                      (v) => _apply(tactic.copyWith(possessionFocus: v)),
                    ),
                  ],
                ),
                _category(
                  children: [
                    SwitchListTile(
                      title: const Text('Offside trap'),
                      value: tactic.offsideTrap,
                      onChanged: (v) => _apply(tactic.copyWith(offsideTrap: v)),
                    ),
                    SwitchListTile(
                      title: const Text('Aggressive set pieces'),
                      value: tactic.setPieceAggressive,
                      onChanged: (v) =>
                          _apply(tactic.copyWith(setPieceAggressive: v)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saved tactics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saveCurrent,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('Save current tactic'),
                    ),
                    if (saved.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Nothing saved yet. Saving keeps a named copy in your '
                        'career so you can come back to it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    for (final entry in saved)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.bookmark, size: 18),
                        title: Text('${entry['name']}'),
                        subtitle: Text(
                          Tactic.fromJson(Map<String, dynamic>.from(
                                  entry['tactic'] as Map))
                              .displayName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => _apply(
                          Tactic.fromJson(Map<String, dynamic>.from(
                              entry['tactic'] as Map)),
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              deleteNamedTactic(ref, '${entry['name']}'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // The hint is dropped on short screens: the instruction tabs below
          // need the pixels more than the sentence does.
          if (MediaQuery.sizeOf(context).height >= 720)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Text(
                'Playing style and tempo are read by the match engine; the rest '
                'are stored with your career and carried into every match.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// The pitch grows with the screen but stays short enough on a 640 dp phone
  /// that the selection rows and the instruction tabs underneath still get
  /// usable height.
  double _pitchHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.30).clamp(168.0, 320.0);

  Widget _category({required List<Widget> children}) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: children,
      );

  Widget _enumDropdown<T extends Object>(
    String label,
    List<T> values,
    T current,
    void Function(T) onSelected, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T>(
        initialValue: current,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          helperText: hint,
          helperStyle: Theme.of(context).textTheme.bodySmall,
        ),
        items: [
          for (final v in values)
            DropdownMenuItem(value: v, child: Text(_enumLabel(v))),
        ],
        onChanged: (v) {
          if (v != null) onSelected(v);
        },
      ),
    );
  }

  Future<void> _saveCurrent() async {
    final name = _nameController.text.trim();
    final label = name.isEmpty ? _formationLabel(_tactic.formation) : name;
    saveNamedTactic(ref, label, _tactic);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$label"')),
    );
  }

  String _enumLabel(Object value) {
    final name = value.toString().split('.').last;
    return name.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}').trim();
  }

  String _formationLabel(Formation f) => switch (f) {
        Formation.fourFourTwo => '4-4-2',
        Formation.fourThreeThree => '4-3-3',
        Formation.threeFiveTwo => '3-5-2',
        Formation.fourTwoThreeOne => '4-2-3-1',
      };
}

/// The stored pick at [index], or 0 ("let the assistant pick").
int _storedPick(List<int> ids, int index) =>
    index < ids.length && ids[index] > 0 ? ids[index] : 0;

/// The stored bench picks as a set: they are reserved for the bench and can
/// never be selected into the XI.
Set<int> _benchReserved(List<int> benchIds) => {
      for (final id in benchIds)
        if (id > 0) id,
    };

/// "Jamie Vardy" -> "Vardy": the last word is all a chip has room for.
String _shortName(String name) {
  final parts = name.split(' ').where((w) => w.isNotEmpty).toList();
  return parts.length < 2 ? name : parts.last;
}

/// Sparse selections keep no trailing zeros, so an all-automatic plan is
/// simply an empty list.
List<int> _withoutTrailingZeros(List<int> ids) {
  var end = ids.length;
  while (end > 0 && ids[end - 1] == 0) {
    end--;
  }
  return end == ids.length ? ids : ids.sublist(0, end);
}

/// Pitch diagram showing the resolved eleven.
///
/// The previous layout positioned a 2.2-marker-wide token with
/// `x * width - marker / 2`, which put every marker's centre roughly 18 dp to
/// the right of its slot, and clamped the goalkeeper (y = 0.93) against the
/// bottom edge so he sat on the goal line with his name clipped.
///
/// This version maps the marker *centres* into an inset rectangle: half a
/// token is reserved either side and the marker plus the name block top and
/// bottom, so `x = 0.5` is exactly the middle of the pitch and every token —
/// keeper included — stays fully inside the field.
class PitchPreview extends StatelessWidget {
  const PitchPreview({
    super.key,
    required this.slots,
    required this.formation,
    this.height = 300,
    this.onSlotTap,
  });

  /// The resolved eleven, slot by slot, in [kFormationLayouts] order.
  final List<FormationSlot> slots;
  final Formation formation;

  /// Fixed height rather than an aspect ratio: on a 360 dp phone an
  /// aspect-driven box was ~420 dp tall and pushed the tabs off-screen.
  final double height;

  /// Called with the slot index when a token is tapped; the tactics screen
  /// opens the picker for that slot.
  final void Function(int index)? onSlotTap;

  /// Width of the marker + name column.
  static const double _tokenWidth = 70;

  /// Diameter of the shirt-number circle.
  static const double _marker = 34;

  /// Vertical space the player's name occupies under the circle.
  static const double _labelHeight = 16;

  @override
  Widget build(BuildContext context) {
    final layout = kFormationLayouts[formation] ?? const <PitchPosition>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final pitchHeight = constraints.maxHeight;
            const insetX = 6.0;
            final minX = _tokenWidth / 2 + insetX;
            final maxX = width - _tokenWidth / 2 - insetX;
            final minY = _marker / 2 + 6;
            final maxY = pitchHeight - _marker / 2 - _labelHeight - 8;
            final spanX = (maxX - minX).clamp(1.0, double.infinity);
            final spanY = (maxY - minY).clamp(1.0, double.infinity);

            return ColoredBox(
              color: const Color(0xFF155E27),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PitchLines()),
                  ),
                  for (var i = 0; i < layout.length; i++)
                    Positioned(
                      left: minX + layout[i].x * spanX - _tokenWidth / 2,
                      top: minY + layout[i].y * spanY - _marker / 2,
                      width: _tokenWidth,
                      child: GestureDetector(
                        key: ValueKey('pitch-slot-$i'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onSlotTap == null ? null : () => onSlotTap!(i),
                        child: _PitchToken(
                          slot: i < slots.length
                              ? slots[i]
                              : FormationSlot(position: layout[i].position),
                          layout: layout[i],
                          size: _marker,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PitchToken extends StatelessWidget {
  const _PitchToken({
    required this.slot,
    required this.layout,
    required this.size,
  });

  final FormationSlot slot;
  final PitchPosition layout;
  final double size;

  /// Amber for a pick who lost his place to a fit team-mate, a bold ring for
  /// a pick who is playing, and the quiet default for automatic picks.
  static const _amber = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    final player = slot.player;
    final empty = player == null;
    final replaced = slot.replaced;
    final borderColor = replaced
        ? _amber
        : slot.manual
            ? Colors.white
            : (empty ? Colors.white38 : Colors.white70);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: empty ? 0.28 : 0.62),
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: (slot.manual || replaced) ? 2.2 : 1.4,
            ),
            boxShadow: empty
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            empty ? layout.position : '${player.ovr}',
            style: TextStyle(
              color: replaced ? _amber : Colors.white,
              fontSize: empty ? 8.5 : 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          empty ? '—' : _shortName(player.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static String _shortName(String name) {
    final parts = name.split(' ').where((w) => w.isNotEmpty).toList();
    return parts.length < 2 ? name : parts.last;
  }
}

/// Regulation pitch markings drawn relative to the box, so the diagram reads
/// as a football pitch at any size.
class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Mown stripes.
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.035);
    const stripeCount = 8;
    final stripeHeight = size.height / stripeCount;
    for (var i = 0; i < stripeCount; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight),
        stripe,
      );
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final solid = Paint()..color = Colors.white.withValues(alpha: 0.55);

    const pad = 10.0;
    final field = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    canvas.drawRect(field, line);

    final midY = field.center.dy;
    canvas.drawLine(Offset(field.left, midY), Offset(field.right, midY), line);

    final circleRadius = (size.width * 0.13).clamp(26.0, 44.0);
    canvas.drawCircle(field.center, circleRadius, line);
    canvas.drawCircle(field.center, 2.0, solid);

    // Penalty areas, six-yard boxes, spots and arcs at both ends.
    final boxWidth = field.width * 0.58;
    final boxHeight = field.height * 0.15;
    final sixWidth = field.width * 0.30;
    final sixHeight = field.height * 0.055;
    for (final isTop in const [true, false]) {
      final edge = isTop ? field.top : field.bottom;
      final direction = isTop ? 1.0 : -1.0;
      final box = Rect.fromLTWH(
        field.center.dx - boxWidth / 2,
        isTop ? edge : edge - boxHeight,
        boxWidth,
        boxHeight,
      );
      canvas.drawRect(box, line);
      canvas.drawRect(
        Rect.fromLTWH(
          field.center.dx - sixWidth / 2,
          isTop ? edge : edge - sixHeight,
          sixWidth,
          sixHeight,
        ),
        line,
      );
      final spot = Offset(field.center.dx, edge + direction * boxHeight * 0.72);
      canvas.drawCircle(spot, 2.0, solid);

      // The arc bulges out of the box, so it is clipped to the area beyond it.
      canvas.save();
      canvas.clipRect(
        isTop
            ? Rect.fromLTRB(field.left, box.bottom, field.right, field.bottom)
            : Rect.fromLTRB(field.left, field.top, field.right, box.top),
      );
      canvas.drawCircle(spot, circleRadius * 0.92, line);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.onTap,
    this.status,
    this.tag,
  });

  final Player player;
  final VoidCallback onTap;
  final String? status;

  /// Where the player sits in the matchday plans ("XI", "SUB"), if anywhere.
  final String? tag;

  /// The one-line story of the player right now: an injury and its expected
  /// return beat the squad role, because it changes what the manager can do.
  String _subtitle() {
    if (player.isInjured) {
      final type = player.injuryType ?? 'Injured';
      final back = player.injuryReturnDate;
      return back == null ? type : '$type · back ${shortDate(back)}';
    }
    return status ?? '${player.age} yrs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: PlayerAvatar(player: player, radius: 20),
        title: Text(
          player.name,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            PositionChip(position: player.primaryPosition),
            if (tag != null) ...[
              const SizedBox(width: 6),
              SelectionTag(label: tag!),
            ],
            if (player.isInjured) ...[
              const SizedBox(width: 6),
              const InjuryChip(),
            ],
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _subtitle(),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: player.fitness / 100,
                  minHeight: 4,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(
                      AppTheme.ovrColorFor(theme.brightness, player.fitness)),
                ),
              ),
            ),
          ],
        ),
        trailing: OvrBadge(ovr: player.ovr),
      ),
    );
  }
}
