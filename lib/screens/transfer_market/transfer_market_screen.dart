import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/player.dart';
import '../../core/services/financial_service.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

/// Transfer Hub — everything about moving players in one place.
///
/// Four tabs mirror the four questions a manager asks: what can I buy
/// (Market), what am I watching (Shortlist), what have I already bid for
/// (Offers) and what can I move out of my own squad (My Players).
///
/// Honesty about scope: this build has no AI club negotiation loop. Bids are
/// recorded verbatim and stay "submitted" until the manager withdraws them —
/// the Offers tab says so rather than simulating a decision that never
/// happens. Buys and sells are immediate and are checked against the real
/// budget and squad-size rules in the career provider.
class TransferMarketScreen extends ConsumerStatefulWidget {
  const TransferMarketScreen({super.key});

  @override
  ConsumerState<TransferMarketScreen> createState() =>
      _TransferMarketScreenState();
}

class _TransferMarketScreenState extends ConsumerState<TransferMarketScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(_onTabChanged);

  final _search = TextEditingController();
  final _positionFilter = TextEditingController();
  String _query = '';
  String _position = '';
  bool _onlyAffordable = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text));
    _positionFilter
        .addListener(() => setState(() => _position = _positionFilter.text));
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _search.dispose();
    _positionFilter.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transfer Hub')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No active career',
          message: 'Start a career to use the transfer market.',
        ),
      );
    }

    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final shortlist = ref.watch(shortlistProvider);
    final offers = ref.watch(transferOffersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Hub'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Squad',
          onPressed: () => context.go('/squad'),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Market'),
              Tab(
                  text:
                      'Shortlist${shortlist.isEmpty ? '' : ' (${shortlist.length})'}'),
              Tab(text: 'Offers${offers.isEmpty ? '' : ' (${offers.length})'}'),
              const Tab(text: 'My Players'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined, size: 16),
                const SizedBox(width: 8),
                Text('Transfer budget',
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Text(
                  '€${_money(session.team.transferBudget)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: AppTheme.pitchGreen),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MarketTab(
                  db: db,
                  squad: session.team.squad,
                  clubName: session.team.name,
                  budget: session.team.transferBudget,
                  shortlist: shortlist,
                  query: _query,
                  position: _position,
                  onlyAffordable: _onlyAffordable,
                  searchController: _search,
                  positionController: _positionFilter,
                  onToggleAffordable: (v) =>
                      setState(() => _onlyAffordable = v),
                  onBuy: (p) => _confirmBuy(p),
                  onShortlist: (p) => toggleShortlist(ref, p.id),
                  onOpen: (p) => showPlayerDetailSheet(context, p),
                ),
                _ShortlistTab(
                  db: db,
                  shortlist: shortlist,
                  squad: session.team.squad,
                  budget: session.team.transferBudget,
                  onBuy: (p) => _confirmBuy(p),
                  onOffer: (p) => _makeOffer(p),
                  onRemove: (p) => toggleShortlist(ref, p.id),
                  onOpen: (p) => showPlayerDetailSheet(context, p),
                ),
                _OffersTab(
                  offers: offers,
                  onWithdraw: (offer) => _withdrawOffer(offer),
                ),
                _MyPlayersTab(
                  squad: session.team.squad,
                  onSell: (p) => _confirmSell(p),
                  onOpen: (p) => showPlayerDetailSheet(context, p),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBuy(Player player) async {
    final session = ref.read(careerSessionProvider);
    if (session == null) return;
    final fee = FinancialService().calculateTransferValue(player);
    if (fee > session.team.transferBudget) {
      _snack('Cannot afford ${player.name} — '
          '€${_money(fee.toDouble())} exceeds the budget.');
      return;
    }
    final ok = await _ask(
      title: 'Sign ${player.name}?',
      body: 'Fee €${_money(fee.toDouble())}\n'
          'OVR ${player.ovr} · ${player.primaryPosition} · ${player.age} yrs',
      confirm: 'Sign',
    );
    if (ok != true || !mounted) return;
    final bought = buyPlayer(ref, player, fee);
    _snack(bought
        ? '${player.name} signed for €${_money(fee.toDouble())}'
        : 'Transfer blocked — squad or budget constraints.');
  }

  Future<void> _confirmSell(Player player) async {
    final session = ref.read(careerSessionProvider);
    if (session == null) return;
    final fee = FinancialService().calculateTransferValue(player);
    final ok = await _ask(
      title: 'Sell ${player.name}?',
      body: 'Expected fee €${_money(fee.toDouble())}\n'
          'Your squad must keep at least 16 players.',
      confirm: 'Sell',
    );
    if (ok != true || !mounted) return;
    final sold = sellPlayer(ref, player, fee);
    _snack(sold
        ? '${player.name} sold for €${_money(fee.toDouble())}'
        : 'Cannot sell — your squad would drop below 16 players.');
  }

  /// Records a formal bid. The bid is stored verbatim; nothing in this build
  /// negotiates a reply, so the Offers tab labels it as awaiting a response.
  Future<void> _makeOffer(Player player) async {
    final fee = FinancialService().calculateTransferValue(player);
    final controller = TextEditingController(
      text: (fee * 1.1).round().toString(),
    );
    final wage = TextEditingController(
      text: (player.ovr * 1200).round().toString(),
    );
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bid for ${player.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _moneyField(
                controller, 'Fee (€)', 'Estimated €${_money(fee.toDouble())}'),
            const SizedBox(height: 12),
            _moneyField(wage, 'Weekly wage (€)', null),
            const SizedBox(height: 12),
            Text(
              'Bids are recorded and shown under Offers. No club will respond '
              'in this build.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit bid'),
          ),
        ],
      ),
    );

    final offeredFee = int.tryParse(controller.text.trim()) ?? 0;
    final offeredWage = double.tryParse(wage.text.trim()) ?? 0;
    controller.dispose();
    wage.dispose();
    if (submitted != true || !mounted) return;

    recordTransferOffer(ref, {
      'playerId': player.id,
      'playerName': player.name,
      'club': player.currentTeam,
      'position': player.primaryPosition,
      'ovr': player.ovr,
      'fee': offeredFee,
      'wage': offeredWage,
      'askingFee': fee,
      'status': 'submitted',
      'date': DateTime.now().toIso8601String(),
    });
    _snack('Bid submitted for ${player.name}.');
  }

  Future<void> _withdrawOffer(Map<String, dynamic> offer) async {
    final offers = [...ref.read(transferOffersProvider)]
      ..removeWhere((o) => o['playerId'] == offer['playerId']);
    ref.read(transferOffersProvider.notifier).state = offers;
    _snack('Bid for ${offer['playerName']} withdrawn.');
    unawaitedSave(ref);
  }

  /// Re-persists career-only state after a pure provider mutation.
  void unawaitedSave(WidgetRef ref) {
    // saveCareerNow is fire-and-forget here: the Offers list is already the
    // source of truth in memory, and the failure path is logged by the saver.
    saveCareerNow(ref);
  }

  Future<bool?> _ask({
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

  Widget _moneyField(
      TextEditingController controller, String label, String? hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration:
          InputDecoration(labelText: label, hintText: hint, isDense: true),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MarketTab extends StatelessWidget {
  const _MarketTab({
    required this.db,
    required this.squad,
    required this.clubName,
    required this.budget,
    required this.shortlist,
    required this.query,
    required this.position,
    required this.onlyAffordable,
    required this.searchController,
    required this.positionController,
    required this.onToggleAffordable,
    required this.onBuy,
    required this.onShortlist,
    required this.onOpen,
  });

  final PlayerDatabase? db;
  final List<Player> squad;
  final String clubName;
  final double budget;
  final Set<int> shortlist;
  final String query;
  final String position;
  final bool onlyAffordable;
  final TextEditingController searchController;
  final TextEditingController positionController;
  final ValueChanged<bool> onToggleAffordable;
  final ValueChanged<Player> onBuy;
  final ValueChanged<Player> onShortlist;
  final ValueChanged<Player> onOpen;

  static const List<String> _positions = [
    'GK',
    'CB',
    'LB',
    'RB',
    'CDM',
    'CM',
    'CAM',
    'LW',
    'RW',
    'ST',
  ];

  @override
  Widget build(BuildContext context) {
    if (db == null) {
      return const LoadingState(message: 'Loading player database…');
    }
    if (db!.players.isEmpty) {
      return const EmptyState(
        icon: Icons.storage_outlined,
        title: 'Player database unavailable',
        message: 'The bundled dataset did not load.',
      );
    }

    final q = query.trim().toLowerCase();
    final pos = position.trim().toUpperCase();
    final owned = {for (final p in squad) p.id};
    final financial = FinancialService();

    final market = (db!.players)
        .where((p) => !owned.contains(p.id) && p.currentTeam != clubName)
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .where((p) => pos.isEmpty || p.primaryPosition == pos)
        .where((p) =>
            !onlyAffordable || financial.calculateTransferValue(p) <= budget)
        .toList()
      ..sort((a, b) {
        final c = b.ovr.compareTo(a.ovr);
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search players',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _positions.contains(pos) ? pos : '',
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    for (final p in _positions)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => positionController.text = v ?? '',
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Only show what I can afford',
              style: Theme.of(context).textTheme.bodySmall),
          value: onlyAffordable,
          onChanged: onToggleAffordable,
        ),
        Expanded(
          child: market.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'No players match',
                  message: 'Loosen the filters or clear the search.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: market.length,
                  itemBuilder: (context, index) {
                    final player = market[index];
                    final fee = financial.calculateTransferValue(player);
                    return _PlayerRow(
                      player: player,
                      fee: fee,
                      affordable: fee <= budget,
                      shortlisted: shortlist.contains(player.id),
                      onTap: () => onOpen(player),
                      actions: [
                        _RowAction(
                          icon: shortlist.contains(player.id)
                              ? Icons.star
                              : Icons.star_border,
                          tooltip: shortlist.contains(player.id)
                              ? 'Remove from shortlist'
                              : 'Shortlist',
                          active: shortlist.contains(player.id),
                          onPressed: () => onShortlist(player),
                        ),
                        _RowAction(
                          icon: Icons.shopping_cart_checkout,
                          tooltip: 'Buy now',
                          active: fee <= budget,
                          onPressed: fee <= budget ? () => onBuy(player) : null,
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ShortlistTab extends StatelessWidget {
  const _ShortlistTab({
    required this.db,
    required this.shortlist,
    required this.squad,
    required this.budget,
    required this.onBuy,
    required this.onOffer,
    required this.onRemove,
    required this.onOpen,
  });

  final PlayerDatabase? db;
  final Set<int> shortlist;
  final List<Player> squad;
  final double budget;
  final ValueChanged<Player> onBuy;
  final ValueChanged<Player> onOffer;
  final ValueChanged<Player> onRemove;
  final ValueChanged<Player> onOpen;

  @override
  Widget build(BuildContext context) {
    if (shortlist.isEmpty) {
      return const EmptyState(
        icon: Icons.star_border,
        title: 'Shortlist is empty',
        message: 'Star a player in the Market tab to track them here.',
      );
    }

    final ids = shortlist.toList();
    final owned = {for (final p in squad) p.id};
    final players = <Player>[
      for (final id in ids)
        ...?owned.contains(id)
            ? squad.where((p) => p.id == id)
            : db?.players.where((p) => p.id == id),
    ]..sort((a, b) => b.ovr.compareTo(a.ovr));

    final financial = FinancialService();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final fee = financial.calculateTransferValue(player);
        return _PlayerRow(
          player: player,
          fee: fee,
          affordable: fee <= budget,
          shortlisted: true,
          onTap: () => onOpen(player),
          actions: [
            _RowAction(
              icon: Icons.gavel,
              tooltip: 'Make an offer',
              active: fee <= budget,
              onPressed: () => onOffer(player),
            ),
            _RowAction(
              icon: Icons.shopping_cart_checkout,
              tooltip: 'Buy now',
              active: fee <= budget,
              onPressed: fee <= budget ? () => onBuy(player) : null,
            ),
            _RowAction(
              icon: Icons.close,
              tooltip: 'Remove',
              onPressed: () => onRemove(player),
            ),
          ],
        );
      },
    );
  }
}

class _OffersTab extends StatelessWidget {
  const _OffersTab({required this.offers, required this.onWithdraw});

  final List<Map<String, dynamic>> offers;
  final ValueChanged<Map<String, dynamic>> onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (offers.isEmpty) {
      return const EmptyState(
        icon: Icons.gavel_outlined,
        title: 'No bids submitted',
        message: 'Shortlist a player and make an offer to start a negotiation.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: offers.length + 1,
      itemBuilder: (context, index) {
        if (index == offers.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This build has no club negotiation engine: a bid stays '
              '"submitted" until you withdraw it.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        final offer = offers[index];
        final fee = (offer['fee'] as num?)?.toDouble() ?? 0;
        final wage = (offer['wage'] as num?)?.toDouble() ?? 0;
        final asking = (offer['askingFee'] as num?)?.toDouble() ?? 0;
        final overpay = asking > 0 && fee >= asking * 1.2;
        final lowball = asking > 0 && fee < asking * 0.7;

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${offer['playerName']}',
                        style:
                            theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${offer['club']} · ${offer['position']} · OVR ${offer['ovr']}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Chip(
                            label: Text('Fee €${_money(fee)}'),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text('Wage €${_money(wage)}/wk'),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (overpay)
                            const Chip(
                              label: Text('Overpay'),
                              visualDensity: VisualDensity.compact,
                            )
                          else if (lowball)
                            const Chip(
                              label: Text('Lowball'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Withdraw bid',
                  icon: const Icon(Icons.undo),
                  onPressed: () => onWithdraw(offer),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MyPlayersTab extends StatelessWidget {
  const _MyPlayersTab({
    required this.squad,
    required this.onSell,
    required this.onOpen,
  });

  final List<Player> squad;
  final ValueChanged<Player> onSell;
  final ValueChanged<Player> onOpen;

  @override
  Widget build(BuildContext context) {
    if (squad.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'No squad',
      );
    }
    final sorted = [...squad]..sort((a, b) => b.ovr.compareTo(a.ovr));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final player = sorted[index];
        final (listed, asking) = transferListingOf(player);
        return _PlayerRow(
          player: player,
          fee: FinancialService().calculateTransferValue(player),
          affordable: true,
          shortlisted: listed,
          footnote: listed && asking != null
              ? 'Listed · asking €${_money(asking)}'
              : loanListingOf(player)
                  ? 'On loan list'
                  : null,
          onTap: () => onOpen(player),
          actions: [
            _RowAction(
              icon: Icons.sell_outlined,
              tooltip: 'Sell',
              onPressed: () => onSell(player),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.fee,
    required this.affordable,
    required this.shortlisted,
    required this.onTap,
    required this.actions,
    this.footnote,
  });

  final Player player;
  final int fee;
  final bool affordable;
  final bool shortlisted;
  final String? footnote;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              PlayerAvatar(player: player, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style:
                          theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${player.primaryPosition} · ${player.age} yrs · ${player.currentTeam}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (footnote != null)
                      Text(
                        footnote!,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppTheme.pitchGreen),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OvrBadge(ovr: player.ovr, size: 26),
                  const SizedBox(height: 4),
                  Text(
                    '€${_money(fee.toDouble())}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: affordable
                          ? AppTheme.pitchGreen
                          : theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: Icon(
        icon,
        color: onPressed == null
            ? Theme.of(context).disabledColor
            : active
                ? AppTheme.pitchGreen
                : null,
      ),
      onPressed: onPressed,
    );
  }
}

String _money(num amount) {
  if (amount >= 1000000000) {
    return '${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
  if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
  return amount.toStringAsFixed(0);
}
