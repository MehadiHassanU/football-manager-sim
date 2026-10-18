import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/player.dart';
import '../../core/services/development_service.dart';
import '../../core/services/financial_service.dart';
import '../../providers/career_session_provider.dart';
import 'common.dart';
import 'player_badges.dart';

/// Squad-role labels a manager can assign, in the order they are offered.
const List<String> kSquadRoles = [
  'Key Player',
  'First Team',
  'Squad Player',
  'Rotation',
  'Prospect',
];

/// Individual training focuses, in the order they are offered.
const List<String> kTrainingFocuses = [
  'Finishing',
  'Passing',
  'Pace',
  'Defending',
  'Physical',
  'Goalkeeping',
];

/// Opens the full player profile.
///
/// The sheet is a management surface, not a stat dump: the Overview tab answers
/// "how good is he", Attributes gives the full technical read, Development
/// shows what he can still become and what training he is on, and Role &
/// Contract carries the actions a manager actually takes (squad role, transfer
/// and loan listing). Every action writes to the live career session through
/// the sheet's own [ConsumerState.ref], so changes show up on the squad screen
/// behind the sheet immediately.
void showPlayerDetailSheet(BuildContext context, Player player) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _PlayerProfileSheet(player: player, controller: scrollController),
    ),
  );
}

class _PlayerProfileSheet extends ConsumerStatefulWidget {
  const _PlayerProfileSheet({
    required this.player,
    required this.controller,
  });

  final Player player;
  final ScrollController controller;

  @override
  ConsumerState<_PlayerProfileSheet> createState() =>
      _PlayerProfileSheetState();
}

class _PlayerProfileSheetState extends ConsumerState<_PlayerProfileSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Player get _player => widget.player;

  /// True when the player belongs to the manager's own club — only then do the
  /// role/listing actions apply.
  bool get _isOwnPlayer =>
      ref
          .read(careerSessionProvider)
          ?.team
          .squad
          .any((p) => p.id == _player.id) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final squad = ref.watch(careerSessionProvider)?.team.squad ?? const [];
    return Column(
      children: [
        _header(theme),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Attributes'),
            Tab(text: 'Development'),
            Tab(text: 'Role & Contract'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(player: _player),
              _AttributesTab(player: _player),
              _DevelopmentTab(
                player: _player,
                enabled: _isOwnPlayer,
                onFocusChanged: (f) => setTrainingFocus(ref, _player, f),
              ),
              _RoleTab(
                player: _player,
                squad: squad,
                enabled: _isOwnPlayer,
                ref: ref,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(ThemeData theme) {
    final potential = _player.hiddenAttributes['potential'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          PlayerAvatar(player: _player, radius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _player.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    PositionChip(position: _player.primaryPosition),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${_player.age} yrs · ${_player.nationality}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              OvrBadge(ovr: _player.ovr, size: 44),
              if (potential is int)
                Text(
                  'POT $potential',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final personality = player.hiddenAttributes['personality'];
    final leadership = player.hiddenAttributes['leadership'];
    final fitness = player.isInjured
        ? 'Injured${player.injuryType != null ? ' · ${player.injuryType}' : ''}'
        : 'Fit';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            for (final (label, stat) in [
              ('PAC', player.pac),
              ('SHO', player.sho),
              ('PAS', player.pas),
              ('DRI', player.dri),
              ('DEF', player.def),
              ('PHY', player.phy),
            ]) ...[
              Expanded(child: _StatCell(label: label, value: stat)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Condition', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                MeterBar(
                  label: 'Fitness',
                  value: player.fitness.toDouble(),
                  color: player.isInjured ? const Color(0xFFEF5350) : null,
                ),
                const SizedBox(height: 10),
                MeterBar(label: 'Morale', value: player.morale.toDouble()),
                const SizedBox(height: 10),
                MeterBar(label: 'Form', value: player.form.toDouble() * 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _kv(context, 'Club', player.currentTeam),
                _kv(
                    context,
                    'Preferred foot',
                    player.weakFootQuality >= 4
                        ? 'Weak foot'
                        : '${player.preferredFoot} foot'),
                _kv(context, 'Fitness', fitness),
                if (personality is String)
                  _kv(context, 'Personality', personality),
                if (leadership is int)
                  _kv(context, 'Leadership', '$leadership'),
                if (player.playTraits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in player.playTraits) Chip(label: Text(t)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );
}

class _AttributesTab extends StatelessWidget {
  const _AttributesTab({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Group(title: 'Attacking', stats: [
          ('Finishing', player.finishing),
          ('Shot Power', player.shotPower),
          ('Long Shots', player.longShots),
          ('Volleys', player.volleys),
          ('Penalties', player.penalties),
          ('Positioning', player.positioning),
        ]),
        _Group(title: 'Passing & Vision', stats: [
          ('Vision', player.vision),
          ('Crossing', player.crossing),
          ('Short Passing', player.shortPassing),
          ('Long Passing', player.longPassing),
          ('Curve', player.curve),
          ('Free Kicks', player.freeKickAccuracy),
        ]),
        _Group(title: 'Defending', stats: [
          ('Interceptions', player.interceptions),
          ('Heading', player.headingAccuracy),
          ('Def Awareness', player.defAwareness),
          ('Standing Tackle', player.standingTackle),
          ('Sliding Tackle', player.slidingTackle),
          ('Aggression', player.aggression),
        ]),
        _Group(title: 'Physical', stats: [
          ('Acceleration', player.acceleration),
          ('Sprint Speed', player.sprintSpeed),
          ('Agility', player.agility),
          ('Balance', player.balance),
          ('Jumping', player.jumping),
          ('Stamina', player.staminaStat),
          ('Strength', player.strength),
          ('Reactions', player.reactions),
          ('Ball Control', player.ballControl),
          ('Composure', player.composure),
        ]),
        if (player.gkDiving != null)
          _Group(title: 'Goalkeeping', stats: [
            ('Diving', player.gkDiving!),
            ('Handling', player.gkHandling!),
            ('Kicking', player.gkKicking!),
            ('Positioning', player.gkPositioning!),
            ('Reflexes', player.gkReflexes!),
          ]),
      ],
    );
  }
}

class _DevelopmentTab extends StatelessWidget {
  const _DevelopmentTab({
    required this.player,
    required this.enabled,
    required this.onFocusChanged,
  });

  final Player player;
  final bool enabled;
  final ValueChanged<String> onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final potential = player.hiddenAttributes['potential'];
    final adaptability = player.hiddenAttributes['adaptability'];
    final focus = trainingFocusOf(player);
    final growth = (potential is int) ? potential - player.ovr : null;
    final progress = ((player.hiddenAttributes[DevelopmentService.progressKey]
                    as num?)
                ?.toDouble() ??
            0.0)
        .clamp(0.0, 1.0);
    final atCeiling = potential is int && player.ovr >= potential;
    final showing = enabled &&
        !player.isInjured &&
        !atCeiling &&
        player.age < 31;
    final status = player.isInjured
        ? 'In the treatment room: no development until he is fit again.'
        : player.age >= 31
            ? 'In the decline years: game time no longer adds points.'
            : atCeiling
                ? 'At his ceiling: there is nothing left to grow into.'
                : 'Minutes on the pitch decide how much of the week counts.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Outlook', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                MeterBar(
                  label: 'Current ability',
                  value: player.ovr.toDouble(),
                ),
                if (potential is int) ...[
                  const SizedBox(height: 10),
                  MeterBar(
                    label: 'Potential',
                    value: potential.toDouble(),
                    color: const Color(0xFF40C4FF),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Room to grow', style: theme.textTheme.bodySmall),
                      Text(
                        growth == null
                            ? '—'
                            : growth <= 0
                                ? 'No room left'
                                : '+$growth potential',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
                if (adaptability is int) ...[
                  const SizedBox(height: 10),
                  MeterBar(
                    label: 'Adaptability',
                    value: adaptability.toDouble(),
                  ),
                ],
                const SizedBox(height: 10),
                if (showing) ...[
                  MeterBar(
                    label: 'Towards next point',
                    value: progress * 100,
                    color: const Color(0xFF69F0AE),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(status, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usage this season', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(
                  '${player.gamesPlayed} apps · ${player.minutesPlayed} min · '
                  'match rating ${player.matchRating.toStringAsFixed(1)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Training focus', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  enabled
                      ? 'Applied to his weekly development.'
                      : 'Only available for your own squad.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in kTrainingFocuses)
                      ChoiceChip(
                        label: Text(f),
                        selected: focus == f,
                        onSelected: enabled ? (_) => onFocusChanged(f) : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleTab extends ConsumerWidget {
  const _RoleTab({
    required this.player,
    required this.squad,
    required this.enabled,
    required this.ref,
  });

  final Player player;
  final List<Player> squad;
  final bool enabled;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, _) {
    final theme = Theme.of(context);
    final status = squadStatusOf(player, squad);
    final (listed, asking) = transferListingOf(player);
    final loaned = loanListingOf(player);
    final value = player.transferValue > 0
        ? player.transferValue
        : FinancialService().calculateTransferValue(player);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: theme.colorScheme.secondary.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You can only manage players at ${player.currentTeam}.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Squad status', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Currently: $status', style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in kSquadRoles)
                      ChoiceChip(
                        label: Text(r),
                        selected: status == r,
                        onSelected: enabled
                            ? (_) => setSquadRole(ref, player, r)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transfer market', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Transfer listed'),
                  subtitle: Text(
                    listed && asking != null
                        ? 'Asking ${_money(asking)}'
                        : 'Available for offers from other clubs',
                  ),
                  value: listed,
                  onChanged: enabled
                      ? (v) => setTransferListing(
                            ref,
                            player,
                            listed: v,
                            askingPrice: asking,
                          )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Loan listed'),
                  subtitle: const Text('Available on a season-long loan'),
                  value: loaned,
                  onChanged: enabled
                      ? (v) => setLoanListing(ref, player, listed: v)
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contract', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _moneyRow(context, 'Weekly wage', player.weeklyWage),
                _moneyRow(context, 'Estimated value', value.toDouble()),
                _textRow(
                  context,
                  'Expires',
                  player.contractExpiry == null
                      ? '—'
                      : '${player.contractExpiry!.year}',
                ),
                _textRow(
                  context,
                  'Transfer request',
                  player.requestedTransfer ? 'Submitted' : 'None',
                ),
                _textRow(
                  context,
                  'Unsettled',
                  unsettledOf(player) ? 'Yes — wants minutes' : 'No',
                ),
              ],
            ),
          ),
        ),
        if (enabled && (unsettledOf(player) || player.requestedTransfer)) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Squad mood', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    player.requestedTransfer
                        ? '${player.name} has handed in a transfer request. '
                            'Clubs will come in for him, and the price is '
                            'softer than it was.'
                        : '${player.name} is unhappy with his playing time and '
                            'is close to asking to leave.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (player.hiddenAttributes['minutesPromise'] is int) ...[
                    const SizedBox(height: 6),
                    Text(
                      'You have already promised him minutes. Break that '
                      'promise and he will ask to leave.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () {
                      promisePlayingTime(ref, player);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'You told ${player.name} he is in your plans. Back '
                            'it up with minutes.',
                          ),
                        ),
                      );
                    },
                    child: const Text('Promise him game time'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _moneyRow(BuildContext context, String label, double value) =>
      _row(context, label, _money(value));

  Widget _textRow(BuildContext context, String label, String value) =>
      _row(context, label, value);

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.stats});

  final String title;
  final List<(String, int)> stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final (label, value) in stats) ...[
                MeterBar(label: label, value: value.toDouble()),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _money(num amount) {
  if (amount >= 1000000000) {
    return '€${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) return '€${(amount / 1000000).toStringAsFixed(1)}M';
  if (amount >= 1000) return '€${(amount / 1000).toStringAsFixed(0)}K';
  return '€${amount.toStringAsFixed(0)}';
}
