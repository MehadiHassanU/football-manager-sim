import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/services/match_simulator_service.dart';
import '../../providers/match_providers.dart';
import '../../providers/team_providers.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});
  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  final _sim = MatchSimulatorService();
  bool _playing = false;

  void _play() {
    final squad = ref.read(squadProvider);
    final home = squad.isNotEmpty
        ? squad.take(10).toList()
        : List.generate(10, (i) => _mkPlayer('H$i', 75 + i));
    final away = squad.isNotEmpty
        ? List.generate(10, (i) => _mkPlayer('A$i', 75 + i + (i % 3)))
        : List.generate(10, (i) => _mkPlayer('A$i', 75 + i));
    final homeGk = squad.isNotEmpty && home.length < squad.length
        ? squad[10]
        : _mkGk();
    final awayGk = _mkGk();

    setState(() {
      _playing = true;
    });
    final r = _sim.simulateMatch(
      homeGoalkeeper: homeGk, homeSquad: home,
      awayGoalkeeper: awayGk, awaySquad: away,
    );
    ref.read(currentMatchProvider.notifier).state = r;
    if (mounted) setState(() {});
  }

  Player _mkGk() => Player(
    name: 'GK', id: -1, nationality: 'Unknown', age: 28, ovr: 80, pac: 40, sho: 50, pas: 60, dri: 40,
    def: 50, phy: 60, acceleration: 40, sprintSpeed: 50, positioning: 60,
    finishing: 30, shotPower: 30, longShots: 20, volleys: 25, penalties: 20,
    vision: 40, crossing: 30, freeKickAccuracy: 25, shortPassing: 50,
    longPassing: 40, curve: 20, agility: 40, balance: 35, reactions: 45,
    ballControl: 45, composure: 40, interceptions: 30, headingAccuracy: 50,
    defAwareness: 50, standingTackle: 30, slidingTackle: 25, jumping: 50,
    staminaStat: 60, strength: 50, aggression: 30,
    primaryPosition: 'GK', alternativePositions: [],
    preferredFoot: 'Right', weakFootQuality: 2, skillMoves: 2,
    height: '185cm', weight: '80kg', playTraits: [],
    currentTeam: 'Home', currentLeague: 'league',
    gkDiving: 70, gkHandling: 75, gkKicking: 65, gkPositioning: 75, gkReflexes: 70,
  );

  Player _mkPlayer(String name, int ovr) => Player(
    name: name, id: name.hashCode, nationality: 'Unknown', age: 27, ovr: ovr, pac: ovr, sho: ovr,
    pas: ovr, dri: ovr, def: ovr, phy: ovr,
    acceleration: ovr, sprintSpeed: ovr, positioning: ovr, finishing: ovr,
    shotPower: ovr, longShots: ovr, volleys: ovr, penalties: ovr,
    vision: ovr, crossing: ovr, freeKickAccuracy: ovr, shortPassing: ovr,
    longPassing: ovr, curve: ovr, agility: ovr, balance: ovr, reactions: ovr,
    ballControl: ovr, composure: ovr, interceptions: ovr, headingAccuracy: ovr,
    defAwareness: ovr, standingTackle: ovr, slidingTackle: ovr, jumping: ovr,
    staminaStat: ovr, strength: ovr, aggression: ovr,
    primaryPosition: 'CM', alternativePositions: [],
    preferredFoot: 'Right', weakFootQuality: 3, skillMoves: 3,
    height: '180cm', weight: '75kg', playTraits: [],
    currentTeam: 'Home', currentLeague: 'league',
  );

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(currentMatchProvider);
    return Scaffold(
      appBar: AppBar(title: Text(match != null ? '${match.homeTeam} vs ${match.awayTeam}' : 'Match')),
      body: Center(
        child: match == null || !_playing
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Ready to kick off?'),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _play, child: const Text('Start Match')),
              ])
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Score: ${match.resultText}', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    ...match.events.take(20).map((e) => ListTile(
                      title: Text('${e.minute}\' ${e.description}', style: const TextStyle(fontSize: 12)),
                    )),
                  ],
                ),
              ),
      ),
    );
  }
}
