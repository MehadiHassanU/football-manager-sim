import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/manager.dart';
import '../../core/models/team.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

/// How many rows a picker section shows before the "Show all" toggle.
const int _collapsedRowCount = 5;

class NewCareerScreen extends ConsumerStatefulWidget {
  const NewCareerScreen({super.key});

  @override
  ConsumerState<NewCareerScreen> createState() => _NewCareerScreenState();
}

class _NewCareerScreenState extends ConsumerState<NewCareerScreen> {
  final _nameController = TextEditingController(text: 'Alex Ferreira');
  final _leagueSearch = TextEditingController();
  final _clubSearch = TextEditingController();

  int _age = 38;
  String _nationality = 'Spain';
  LeagueInfo? _league;
  Team? _team;
  bool _leaguesExpanded = false;
  bool _clubsExpanded = false;

  @override
  void dispose() {
    _nameController.dispose();
    _leagueSearch.dispose();
    _clubSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dbAsync = ref.watch(playerDatabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Career'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Main Menu',
          onPressed: () => context.go('/main-menu'),
        ),
      ),
      body: dbAsync.when(
        loading: () => const LoadingState(message: 'Loading player database…'),
        error: (e, _) => ErrorState(
          message: 'Failed to load the player database.',
          onRetry: () => ref.invalidate(playerDatabaseProvider),
        ),
        data: (db) {
          if (db.players.isEmpty) {
            return const ErrorState(message: 'The player database is empty.');
          }
          return _form(db);
        },
      ),
      bottomNavigationBar: dbAsync.maybeWhen(
        data: (db) => db.players.isEmpty ? null : _cta(db),
        orElse: () => null,
      ),
    );
  }

  /// One scrolling page instead of a horizontal `Stepper`: at 360 dp a
  /// three-step header squeezes its labels to nothing and forces three
  /// separate scroll gestures. Sections stay in the same order so the flow
  /// reads top-to-bottom.
  Widget _form(PlayerDatabase db) {
    final nationalities = _worldNationalities(db);
    if (!nationalities.contains(_nationality)) {
      _nationality = nationalities.first;
    }
    final leagues = _filteredLeagues(db);
    final clubs = _filteredClubs(db);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _managerSection(nationalities),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: _league == null
                ? 'League — pick one'
                : 'League · ${_league!.name}',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _leagueSearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search leagues or countries',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
        if (leagues.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No league matches that search.'),
            ),
          )
        else ...[
          SliverList.builder(
            itemCount: leagues.length,
            itemBuilder: (context, index) {
              final league = leagues[index];
              if (index == _collapsedRowCount && !_leaguesExpanded) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: TextButton(
                    onPressed: () => setState(() => _leaguesExpanded = true),
                    child: Text('Show all ${leagues.length} leagues'),
                  ),
                );
              }
              return _leagueTile(league);
            },
          ),
          if (!_leaguesExpanded && leagues.length > _collapsedRowCount)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '${leagues.length - _collapsedRowCount} more — search or expand above.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: SectionHeader(
            title: _team == null ? 'Club — pick one' : 'Club · ${_team!.name}',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _clubSearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search clubs',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
        if (clubs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _league == null
                    ? 'Choose a league first.'
                    : 'No club matches that search.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: clubs.length,
            itemBuilder: (context, index) {
              if (index == _collapsedRowCount && !_clubsExpanded) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: TextButton(
                    onPressed: () => setState(() => _clubsExpanded = true),
                    child: Text('Show all ${clubs.length} clubs'),
                  ),
                );
              }
              return _clubTile(clubs[index]);
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _managerSection(List<String> nationalities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Manager'),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_outline),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _nationality,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Nationality',
            prefixIcon: Icon(Icons.flag_outlined),
            isDense: true,
          ),
          items: [
            for (final n in nationalities)
              DropdownMenuItem(
                  value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _nationality = v ?? _nationality),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.cake_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('Age'),
            Expanded(
              child: Slider(
                value: _age.toDouble(),
                min: 25,
                max: 70,
                divisions: 45,
                label: '$_age',
                onChanged: (v) => setState(() => _age = v.round()),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text('$_age', textAlign: TextAlign.end),
            ),
          ],
        ),
      ],
    );
  }

  Widget _leagueTile(LeagueInfo league) {
    final selected = _league?.id == league.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Card(
        color: selected ? AppTheme.pitchGreen.withValues(alpha: 0.12) : null,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.emoji_events_outlined,
            color: selected ? AppTheme.pitchGreen : null,
          ),
          title: Text(league.name, overflow: TextOverflow.ellipsis),
          subtitle: Text('${league.country} · ${league.teamCount} clubs'),
          trailing: selected
              ? const Icon(Icons.check_circle, color: AppTheme.pitchGreen)
              : null,
          onTap: () => setState(() {
            _league = league;
            _team = null;
            _clubsExpanded = false;
            _clubSearch.clear();
          }),
        ),
      ),
    );
  }

  Widget _clubTile(Team team) {
    final selected = _team?.id == team.id;
    final avgOvr = team.squad.isEmpty
        ? 0
        : (team.squad.map((p) => p.ovr).reduce((a, b) => a + b) /
                team.squad.length)
            .round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Card(
        color: selected ? AppTheme.pitchGreen.withValues(alpha: 0.12) : null,
        child: ListTile(
          dense: true,
          leading: ClubCrest(team: team, size: 32),
          title: Text(team.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${team.country} · avg $avgOvr OVR · ${_formatMoney(team.budget)}',
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected
              ? const Icon(Icons.check_circle, color: AppTheme.pitchGreen)
              : null,
          onTap: () => setState(() => _team = team),
        ),
      ),
    );
  }

  /// Sticky action bar: the CTA is always reachable, and it stays disabled
  /// with an explicit reason until a club is chosen.
  Widget _cta(PlayerDatabase db) {
    final ready = _team != null;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _league == null
                    ? 'Pick a league and a club to continue'
                    : 'Pick a club to continue',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton.icon(
            onPressed: ready ? _startCareer : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(
                ready ? 'Start career at ${_team!.shortName}' : 'Start Career'),
          ),
        ],
      ),
    );
  }

  List<LeagueInfo> _filteredLeagues(PlayerDatabase db) {
    final q = _leagueSearch.text.trim().toLowerCase();
    final leagues = [...db.leagues]..sort((a, b) {
        final c = b.teamCount.compareTo(a.teamCount);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    if (q.isEmpty) return leagues;
    return leagues
        .where((l) =>
            l.name.toLowerCase().contains(q) ||
            l.country.toLowerCase().contains(q))
        .toList();
  }

  List<Team> _filteredClubs(PlayerDatabase db) {
    final q = _clubSearch.text.trim().toLowerCase();
    final clubs = db.teams
        .where((t) => _league == null || t.leagueId == _league!.id)
        .toList()
      ..sort((a, b) => b.budget.compareTo(a.budget));
    if (q.isEmpty) return clubs;
    return clubs
        .where((t) =>
            t.name.toLowerCase().contains(q) ||
            t.shortName.toLowerCase().contains(q) ||
            t.country.toLowerCase().contains(q))
        .toList();
  }

  /// Every nationality present in the loaded dataset, alphabetically.
  ///
  /// Deriving this from the world data means the manager can be from any of
  /// the ~100 nations the CSV actually covers instead of a hardcoded list of
  /// ten, and it can never offer a country with no players.
  List<String> _worldNationalities(PlayerDatabase db) {
    final seen = <String>{};
    for (final p in db.players) {
      final n = p.nationality.trim();
      if (n.isNotEmpty) seen.add(n);
    }
    final sorted = seen.toList()..sort();
    return sorted.isEmpty ? const ['Unknown'] : sorted;
  }

  void _startCareer() {
    final team = _team;
    if (team == null) return;
    final name = _nameController.text.trim();
    final manager = Manager(
      name: name.isEmpty ? 'The Manager' : name,
      age: _age,
      nationality: _nationality,
      teamId: team.id,
    );
    startNewCareer(ref, manager: manager, team: team);
    context.go('/home');
  }
}

String _formatMoney(num amount) {
  if (amount >= 1000000000) {
    return '€${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) {
    return '€${(amount / 1000000).toStringAsFixed(0)}M';
  }
  if (amount >= 1000) return '€${(amount / 1000).toStringAsFixed(0)}K';
  return '€${amount.toStringAsFixed(0)}';
}
