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
    // One OVR rank pass per build; each row used to copy + sort the whole
    // squad inside the list builder.
    final rankIndex = squadRankIndex(allPlayers);
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
    session.tactic = next;
    // Re-emit a shallow copy: StateProvider only notifies listeners when the
    // value is a different instance, so assigning `session` was a no-op.
    notifySessionChanged(ref);
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
              height: _pitchHeight(context),
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

  /// The pitch grows with the screen but stays short enough on a 640 dp phone
  /// that the instruction tabs underneath still get usable height.
  double _pitchHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.40).clamp(260.0, 340.0);

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
    required this.squad,
    required this.formation,
    this.height = 300,
  });

  final List<Player> squad;
  final Formation formation;

  /// Fixed height rather than an aspect ratio: on a 360 dp phone an
  /// aspect-driven box was ~420 dp tall and pushed the tabs off-screen.
  final double height;

  /// Width of the marker + name column.
  static const double _tokenWidth = 70;

  /// Diameter of the shirt-number circle.
  static const double _marker = 34;

  /// Vertical space the player's name occupies under the circle.
  static const double _labelHeight = 16;

  @override
  Widget build(BuildContext context) {
    final layout = kFormationLayouts[formation] ?? const <PitchPosition>[];
    final slots = formationPreview(squad, formation);

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
                      child: _PitchToken(
                        slot: slots[i],
                        layout: layout[i],
                        size: _marker,
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
              color: empty ? Colors.white38 : Colors.white70,
              width: 1.4,
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
              color: Colors.white,
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
  });

  final Player player;
  final VoidCallback onTap;
  final String? status;

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
            if (player.isInjured) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'INJ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFFEF5350),
                  ),
                ),
              ),
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
