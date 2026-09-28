import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import '../../core/models/youth_player.dart';
import '../../providers/academy_providers.dart';
import '../../providers/tactics_providers.dart';
import '../../providers/team_providers.dart';

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: _selectedIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider);
    final squad = ref.watch(squadProvider);
    final tactics = ref.watch(currentTacticsProvider);
    final youth = ref.watch(youthAcademyProvider);

    final tabs = [
      const Tab(icon: Icon(Icons.people_outline), text: 'Squad'),
      const Tab(icon: Icon(Icons.monetization_on), text: 'Transfers'),
      const Tab(icon: Icon(Icons.flag), text: 'Tactics'),
      const Tab(icon: Icon(Icons.sports_soccer_outlined), text: 'Youth'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(team?.name ?? 'Team Management'),
        bottom: TabBar(
          controller: _tabController,
          onTap: (i) => setState(() => _selectedIndex = i),
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSquadTab(squad),
          _buildTransfersTab(),
          _buildTacticsTab(tactics),
          _buildYouthTab(youth),
        ],
      ),
    );
  }

  Widget _buildSquadTab(List<Player> squad) {
    return ListView.builder(
      itemCount: squad.length,
      itemBuilder: (context, index) {
        final player = squad[index];
        return ListTile(
          title: Text(player.name),
          subtitle: Text('${player.primaryPosition} | OVR: ${player.ovr} | Age: ${player.age}'),
          trailing: Text('${player.fitness}%'),
        );
      },
    );
  }

  Widget _buildTransfersTab() {
    return const Center(child: Text('Transfer Market'));
  }

  Widget _buildTacticsTab(Tactic tactics) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Playing Style'),
          subtitle: Text(tactics.playingStyle.name),
        ),
        ListTile(
          title: const Text('Pressing'),
          subtitle: Text(tactics.pressing.name),
        ),
        ListTile(
          title: const Text('Tempo'),
          subtitle: Text(tactics.tempo.name),
        ),
        ListTile(
          title: const Text('Width'),
          subtitle: Text(tactics.width.name),
        ),
        ListTile(
          title: const Text('Defensive Line'),
          subtitle: Text(tactics.defensiveLine.name),
        ),
        SwitchListTile(
          title: const Text('Offside Trap'),
          value: tactics.offsideTrap,
          onChanged: (v) {
            ref.read(currentTacticsProvider.notifier).state =
                tactics.copyWith(offsideTrap: v);
          },
        ),
        SwitchListTile(
          title: const Text('Counter Press'),
          value: tactics.counterPress,
          onChanged: (v) {
            ref.read(currentTacticsProvider.notifier).state =
                tactics.copyWith(counterPress: v);
          },
        ),
      ],
    );
  }

  Widget _buildYouthTab(List<YouthPlayer> youth) {
    if (youth.isEmpty) {
      return const Center(child: Text('No youth players yet'));
    }
    return ListView.builder(
      itemCount: youth.length,
      itemBuilder: (context, index) {
        final p = youth[index];
        return ListTile(
          title: Text(p.name),
          subtitle: Text('${p.position} | Age: ${p.age} | Potential: ${p.potential}'),
        );
      },
    );
  }
}
