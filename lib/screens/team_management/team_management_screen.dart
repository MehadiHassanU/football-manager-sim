import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/tactic_definitions.dart';
import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import '../../core/models/youth_player.dart';
import '../../providers/career_session_provider.dart';
import '../../ui/ui.dart';

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
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
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
            _squadTab(context, squad, team.squad),
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
    List<Player> squad,
    List<Player> allPlayers,
  ) {
    final totalCount = allPlayers.length;
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
                      status: squadStatusOf(player, allPlayers),
                      onTap: () => showPlayerDetailSheet(context, player),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _transfersTab(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.swap_horiz, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('Transfer Hub'),
          const SizedBox(height: 6),
          Text(
            'Market, shortlist, bids and your own squad.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Open Transfer Hub',
            icon: Icons.storefront_outlined,
            onPressed: () => context.go('/transfers'),
          ),
        ],
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scouting reports: 3 new prospects')),
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
    session.tactic = next;
    // Re-assign so Riverpod listeners (and the save) see the new object.
    ref.read(careerSessionProvider.notifier).state = session;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider)!;
    final tactic = session.tactic;
    final saved = ref.watch(savedTacticsProvider);

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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PitchPreview(
              squad: session.team.squad,
              formation: tactic.formation,
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
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

/// Pitch diagram showing the eleven [formation] actually selects.
///
/// Laid out with a [LayoutBuilder] so the markers track the real box width
/// instead of a hard-coded 220 px that pushed tokens off-screen on a phone.
class PitchPreview extends StatelessWidget {
  const PitchPreview({
    super.key,
    required this.squad,
    required this.formation,
    this.height = 240,
  });

  final List<Player> squad;
  final Formation formation;

  /// Fixed height rather than an aspect ratio: on a 360 dp phone an
  /// aspect-driven box was ~420 dp tall and pushed the tabs off-screen.
  final double height;

  @override
  Widget build(BuildContext context) {
    final layout = kFormationLayouts[formation] ?? const <PitchPosition>[];
    final slots = formationPreview(squad, formation);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const marker = 30.0;
            return ColoredBox(
              color: const Color(0xFF1B5E20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PitchLines()),
                  ),
                  for (var i = 0; i < layout.length; i++)
                    Positioned(
                      left: (layout[i].x * width - marker / 2)
                          .clamp(0.0, width - marker),
                      top: (layout[i].y * constraints.maxHeight - marker * 1.1)
                          .clamp(0.0, constraints.maxHeight - marker * 2.1),
                      child: _PitchToken(
                        slot: slots[i],
                        layout: layout[i],
                        size: marker,
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

  @override
  Widget build(BuildContext context) {
    final player = slot.player;
    final empty = player == null;
    return SizedBox(
      width: size * 2.2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: empty ? 0.3 : 0.6),
              shape: BoxShape.circle,
              border: Border.all(
                color: empty ? Colors.white38 : Colors.white70,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              empty ? layout.position : '${player.ovr}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            empty ? '—' : _shortName(player.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static String _shortName(String name) {
    final parts = name.split(' ').where((w) => w.isNotEmpty).toList();
    return parts.length < 2 ? name : parts.last;
  }
}

class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
      paint,
    );
    canvas.drawLine(
      Offset(8, size.height / 2),
      Offset(size.width - 8, size.height / 2),
      paint,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 36, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.onTap,
    this.status,
  });

  final Player player;
  final VoidCallback onTap;
  final String? status;

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
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status == null ? '${player.age} yrs' : status!,
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
                  valueColor:
                      AlwaysStoppedAnimation(AppTheme.ovrColor(player.fitness)),
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
