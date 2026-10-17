import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/player.dart';
import '../../core/models/season.dart';
import '../../core/models/team.dart';
import '../../core/models/transfer.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/transfer_market_service.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/transfer_market_actions.dart';
import '../../ui/ui.dart';

/// Transfer Hub — the market, the talks, the offers and the gossip.
///
/// Six tabs mirror the way a real window plays out: what can I buy (Market),
/// who am I haggling with (Talks), what am I watching (Shortlist), who wants my
/// players (Offers), what can I move out (My Players) and what are people
/// saying (News).
///
/// Nothing here completes a transfer at a formula price any more. A signing is
/// three separate problems: persuade the club (asking price, three rounds of
/// counter-offers, a rival who may pounce), persuade the player (wage, bonus,
/// role, prestige) and do it before the window shuts.
class TransferMarketScreen extends ConsumerStatefulWidget {
  const TransferMarketScreen({super.key});

  @override
  ConsumerState<TransferMarketScreen> createState() =>
      _TransferMarketScreenState();
}

class _TransferMarketScreenState extends ConsumerState<TransferMarketScreen>
    with SingleTickerProviderStateMixin {
  static const _marketTab = 0;

  late final TabController _tabs = TabController(length: 6, vsync: this)
    ..addListener(_onTabChanged);

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
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

    final season = session.season;
    final desk = session.transferDesk;
    final window = TransferWindow.of(season);
    final shortlist = ref.watch(shortlistProvider);
    final activeTalks = desk.negotiations.where((n) => n.isActive).length;
    final bids = desk.incomingBids.length;

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
              Tab(text: activeTalks == 0 ? 'Talks' : 'Talks ($activeTalks)'),
              Tab(
                  text: 'Shortlist'
                      '${shortlist.isEmpty ? '' : ' (${shortlist.length})'}'),
              Tab(text: bids == 0 ? 'Offers' : 'Offers ($bids)'),
              const Tab(text: 'My Players'),
              const Tab(text: 'News'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _BudgetStrip(
            budget: session.team.transferBudget,
            reputation: session.team.reputation,
            team: session.team,
          ),
          _WindowBanner(window: window, season: season),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const TransferMarketBody(showBudget: false),
                _TalksTab(onOpenMarket: () => _tabs.animateTo(_marketTab)),
                _ShortlistTab(
                  db: ref.watch(playerDatabaseProvider).valueOrNull,
                  shortlist: shortlist,
                  squad: session.team.squad,
                  budget: session.team.transferBudget,
                  onBid: (p) => openTransferBid(context, ref, p),
                  onRemove: (p) => toggleShortlist(ref, p.id),
                  onOpen: (p) => showPlayerDetailSheet(context, p),
                ),
                _OffersTab(
                  bids: desk.incomingBids,
                  onAccept: (bid) => _resolveIncoming(bid, accept: true),
                  onReject: (bid) => _resolveIncoming(bid, accept: false),
                  squadAtMinimum: session.team.squad.length <= 16,
                ),
                _MyPlayersTab(
                  squad: session.team.squad,
                  seasonYear: season.currentYear,
                  onSell: (p) => _confirmSell(p),
                  onList: (p) => _toggleListing(p, !transferListingOf(p).$1),
                  onOpen: (p) => showPlayerDetailSheet(context, p),
                ),
                _NewsTab(
                  news: desk.news,
                  squad: session.team.squad,
                  clubName: session.team.name,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _resolveIncoming(IncomingBid bid, {required bool accept}) {
    if (accept) {
      if (bid.isLoan) {
        final done = acceptLoanOffer(ref, bid);
        _snack(done
            ? '${bid.playerName} joins ${bid.club} on loan'
            : ref.read(transferBlockReasonProvider) ?? 'Cannot loan him out.');
        return;
      }
      final sold = acceptIncomingBid(ref, bid);
      _snack(sold
          ? '${bid.playerName} sold to ${bid.club} for ${_euro(bid.fee)}'
          : ref.read(transferBlockReasonProvider) ?? 'Cannot sell.');
    } else {
      rejectIncomingBid(ref, bid);
      _snack('Bid from ${bid.club} rejected.');
    }
  }

  void _toggleListing(Player player, bool listed) {
    setTransferListing(
      ref,
      player,
      listed: listed,
      askingPrice: TransferMarketService().askingPrice(
        player,
        null,
        seasonYear: ref.read(careerSessionProvider)!.season.currentYear,
      ),
    );
    _snack(listed
        ? '${player.name} listed. Clubs will start calling.'
        : '${player.name} taken off the transfer list.');
  }

  Future<void> _confirmSell(Player player) async {
    final session = ref.read(careerSessionProvider);
    if (session == null) return;
    final value = FinancialService()
        .calculateTransferValue(player, seasonYear: session.season.currentYear);
    // A quick sale is discounted. Listing him and letting clubs bid is how a
    // manager gets full value, which is what makes the market feel like a
    // negotiation rather than a shop.
    final fee = (value * 0.85 / 100000).round() * 100000;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sell ${player.name}?'),
        content: Text(
          'A club will take him today for ${_euro(fee)} '
          '(85% of his ${_euro(value)} value).\n'
          'Your squad must keep at least 16 players.\n\n'
          'List him instead and wait for bids to get closer to full value.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sell now'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // A quick sale still needs a destination, or the player would drop out of
    // the world entirely: pick the club that would have bid for him.
    final db = ref.read(playerDatabaseProvider).valueOrNull;
    final buyer = db == null
        ? null
        : TransferMarketService().incomingClubFor(
            player,
            db.teams,
            session.team,
            seasonYear: session.season.currentYear,
            matchday: session.season.currentMatchday,
          );
    final sold = sellPlayer(ref, player, fee, buyerClub: buyer);
    _snack(sold
        ? '${player.name} sold for ${_euro(fee)}'
        : ref.read(transferBlockReasonProvider) ?? 'Cannot sell.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BudgetStrip extends StatelessWidget {
  const _BudgetStrip({
    required this.budget,
    required this.reputation,
    required this.team,
  });

  final double budget;
  final int reputation;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bill = weeklyWageBill(team);
    final headroom = wageHeadroom(team);
    final overBudget = headroom != null && headroom < 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Transfer budget',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _euro(budget),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.pitchGreen,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Club reputation: how big a draw your club is',
                child: _Tag(text: 'REP $reputation'),
              ),
            ],
          ),
          if (headroom != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  overBudget
                      ? Icons.trending_up
                      : Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: overBudget ? theme.colorScheme.error : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: 'Wages are the board\'s ceiling: a signing that '
                        'would break it is refused however big the transfer '
                        'budget is.',
                    child: Text(
                      'Wage bill ${_euro(bill)}/wk of '
                      '${_euro(team.wageBudget)}/wk',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: overBudget ? theme.colorScheme.error : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  overBudget
                      ? '${_euro(-headroom)}/wk over'
                      : '${_euro(headroom)}/wk room',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overBudget ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowBanner extends StatelessWidget {
  const _WindowBanner({required this.window, required this.season});

  final TransferWindow window;
  final SeasonState season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = window.isOpen;
    final deadline = window.isDeadlineDay;
    final color = deadline
        ? Colors.orange
        : open
            ? AppTheme.pitchGreen
            : theme.colorScheme.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(
            deadline
                ? Icons.timer_outlined
                : open
                    ? Icons.lock_open
                    : Icons.lock_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              window.banner(season),
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The market surface itself: window banner, budget, filters and the list of
/// signable players.
///
/// Extracted so the full Transfer Hub and the squad screen's Transfers tab
/// render exactly the same live market.
class TransferMarketBody extends ConsumerStatefulWidget {
  const TransferMarketBody({super.key, this.showBudget = true});

  /// The hub prints the budget above its tab bar, so it hides the duplicate
  /// line here.
  final bool showBudget;

  @override
  ConsumerState<TransferMarketBody> createState() => _TransferMarketBodyState();
}

class _TransferMarketBodyState extends ConsumerState<TransferMarketBody> {
  final _search = TextEditingController();
  final _positionFilter = TextEditingController();
  String _query = '';
  String _position = '';
  bool _onlyAffordable = false;

  List<MarketListing>? _listings;
  int? _listingsKey;

  // Filter memo: re-filtering is cheap next to re-valuing the market, but it
  // still ran three passes over ~16k rows on every keystroke. The result is
  // reused whenever neither the source list nor the filter inputs changed.
  List<MarketListing>? _filteredSource;
  String? _filteredQuery;
  String? _filteredPosition;
  bool? _filteredAffordable;
  double? _filteredBudget;
  List<MarketListing>? _filteredMarket;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text));
    _positionFilter
        .addListener(() => setState(() => _position = _positionFilter.text));
  }

  @override
  void dispose() {
    _search.dispose();
    _positionFilter.dispose();
    super.dispose();
  }

  /// Prices the whole market once per *relevant* change instead of inside the
  /// list builder. Valuing 16,000 players per frame froze the old screen, and
  /// keying this cache on the session instance itself made every unrelated
  /// bump (a morale nudge, a board note) throw the whole listing away.
  ///
  /// The key is what `buildListings` + the owned-filter actually read: the
  /// database, the season year, the buyer's id/league/reputation and the set
  /// of players the user owns (order-insensitive) — plus how many moves the
  /// world has recorded, because a rival or hijack transfer changes where a
  /// player sits and what he earns without touching the session object.
  /// Everything else — morale, board pressure, matchday counters — keeps the
  /// cache.
  List<MarketListing> _marketFor(PlayerDatabase db, CareerSession session) {
    final squad = session.team.squad;
    var squadSeed = squad.length;
    for (final p in squad) {
      squadSeed = (squadSeed + p.id * 31) & 0x7FFFFFFF;
    }
    final key = Object.hash(
        db,
        session.season.currentYear,
        session.team.id,
        session.team.leagueId,
        session.team.reputation,
        squadSeed,
        session.transferDesk.ledger.length,
        session.transferDesk.loans.length);
    if (_listings == null || _listingsKey != key) {
      final owned = {for (final p in squad) p.id};
      _listings = TransferMarketService()
          .buildListings(
            players: db.players,
            teams: db.teams,
            seasonYear: session.season.currentYear,
            buyer: session.team,
          )
          .where((l) =>
              l.player.currentTeam != session.team.name &&
              !owned.contains(l.player.id))
          .toList()
        ..sort((a, b) {
          final c = b.player.ovr.compareTo(a.player.ovr);
          return c != 0 ? c : a.player.name.compareTo(b.player.name);
        });
      _listingsKey = key;
    }
    return _listings!;
  }

  /// One-pass filter over the market rows, memoized per source list + filter
  /// inputs, so typing in the search box filters once per edit instead of
  /// re-running the whole chain on every rebuild.
  List<MarketListing> _applyFilters(
    List<MarketListing> source,
    String query,
    String position,
    bool onlyAffordable,
    double transferBudget,
  ) {
    final q = query.trim().toLowerCase();
    final pos = position.trim().toUpperCase();
    if (!identical(_filteredSource, source) ||
        _filteredQuery != q ||
        _filteredPosition != pos ||
        _filteredAffordable != onlyAffordable ||
        _filteredBudget != transferBudget) {
      _filteredMarket = source
          .where((l) {
            if (q.isNotEmpty && !l.player.name.toLowerCase().contains(q)) {
              return false;
            }
            if (pos.isNotEmpty && l.player.primaryPosition != pos) {
              return false;
            }
            if (onlyAffordable && l.askingPrice > transferBudget) {
              return false;
            }
            return true;
          })
          .toList();
      _filteredSource = source;
      _filteredQuery = q;
      _filteredPosition = pos;
      _filteredAffordable = onlyAffordable;
      _filteredBudget = transferBudget;
    }
    return _filteredMarket!;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        title: 'No active career',
        message: 'Start a career to use the transfer market.',
      );
    }

    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final shortlist = ref.watch(shortlistProvider);

    return Column(
      children: [
        if (widget.showBudget) ...[
          _BudgetStrip(
            budget: session.team.transferBudget,
            reputation: session.team.reputation,
            team: session.team,
          ),
          // The standalone market (squad screen's Transfers tab) owns its own
          // window banner: without it a disabled bid button has no
          // explanation on that surface.
          _WindowBanner(
            window: TransferWindow.of(session.season),
            season: session.season,
          ),
          const SizedBox(height: 4),
          const Divider(height: 14),
        ],
        Expanded(
          child: _MarketList(
            db: db,
            session: session,
            shortlist: shortlist,
            query: _query,
            position: _position,
            onlyAffordable: _onlyAffordable,
            searchController: _search,
            positionController: _positionFilter,
            onToggleAffordable: (v) => setState(() => _onlyAffordable = v),
            listings: db == null
                ? const <MarketListing>[]
                : _applyFilters(
                    _marketFor(db, session),
                    _query,
                    _position,
                    _onlyAffordable,
                    session.team.transferBudget,
                  ),
          ),
        ),
      ],
    );
  }
}

class _MarketList extends ConsumerWidget {
  const _MarketList({
    required this.db,
    required this.session,
    required this.shortlist,
    required this.query,
    required this.position,
    required this.onlyAffordable,
    required this.searchController,
    required this.positionController,
    required this.onToggleAffordable,
    required this.listings,
  });

  final PlayerDatabase? db;
  final CareerSession session;
  final Set<int> shortlist;
  final String query;
  final String position;
  final bool onlyAffordable;
  final TextEditingController searchController;
  final TextEditingController positionController;
  final ValueChanged<bool> onToggleAffordable;
  final List<MarketListing> listings;

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
  Widget build(BuildContext context, WidgetRef ref) {
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

    final window = TransferWindow.of(session.season);
    // [listings] arrives pre-filtered by the owning state — it runs once per
    // source/filter change there, so the rows don't re-filter on every build.
    final market = listings;
    // Dropdown display remains position-aware even though filtering happens
    // upstream now.
    final pos = position.trim().toUpperCase();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: market.length,
                  itemBuilder: (context, index) {
                    final listing = market[index];
                    final player = listing.player;
                    final signable = listing.freeAgent || window.isOpen;
                    final affordable =
                        listing.askingPrice <= session.team.transferBudget;
                    return _PlayerRow(
                      player: player,
                      priceLabel: listing.freeAgent
                          ? 'FREE'
                          : _euro(listing.askingPrice),
                      priceColor: listing.freeAgent || affordable
                          ? AppTheme.pitchGreen
                          : Theme.of(context).colorScheme.error,
                      shortlisted: shortlist.contains(player.id),
                      footnote: '${_euro(listing.weeklyWage)}/wk · '
                          '${listing.freeAgent ? 'out of contract' : 'ask'}',
                      chips: [
                        if (listing.rivalClub != null)
                          _Tag(
                            text: 'Rival: ${listing.rivalClub}',
                            color: Colors.orange,
                          ),
                        if (listing.contractYear != null)
                          _Tag(
                            text: 'Contract ${listing.contractYear}',
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        if (signable && !affordable)
                          _Tag(
                            text: 'Over budget',
                            color: Theme.of(context).colorScheme.error,
                          ),
                      ],
                      onTap: () => showPlayerDetailSheet(context, player),
                      actions: [
                        _RowAction(
                          icon: shortlist.contains(player.id)
                              ? Icons.star
                              : Icons.star_border,
                          tooltip: shortlist.contains(player.id)
                              ? 'Remove from shortlist'
                              : 'Shortlist',
                          active: shortlist.contains(player.id),
                          onPressed: () => toggleShortlist(ref, player.id),
                        ),
                        if (signable &&
                            TransferMarketService()
                                .loanAvailable(player, listing.seller))
                          _RowAction(
                            icon: Icons.swap_horiz,
                            tooltip: 'Offer a loan',
                            active: true,
                            onPressed: () =>
                                openLoanDialog(context, ref, player),
                          ),
                        _RowAction(
                          icon: Icons.gavel,
                          tooltip: signable
                              ? 'Open talks'
                              : 'Window shut — only free agents can sign',
                          active: signable,
                          onPressed: signable
                              ? () => openTransferBid(context, ref, player)
                              : null,
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

class _ShortlistTab extends ConsumerWidget {
  const _ShortlistTab({
    required this.db,
    required this.shortlist,
    required this.squad,
    required this.budget,
    required this.onBid,
    required this.onRemove,
    required this.onOpen,
  });

  final PlayerDatabase? db;
  final Set<int> shortlist;
  final List<Player> squad;
  final double budget;
  final ValueChanged<Player> onBid;
  final ValueChanged<Player> onRemove;
  final ValueChanged<Player> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shortlist.isEmpty) {
      return const EmptyState(
        icon: Icons.star_border,
        title: 'Shortlist is empty',
        message: 'Star a player in the Market tab to track them here.',
      );
    }

    final session = ref.watch(careerSessionProvider);
    final seasonYear = session?.season.currentYear ?? DateTime.now().year;
    final owned = {for (final p in squad) p.id};
    // One bounded pass over the database replaces a per-shortlist-item
    // `.where` scan (~N x 16k per rebuild). Owned players resolve through the
    // squad instance first, preserving the previous precedence.
    final dbById = <int, Player>{
      for (final p in db?.players ?? const <Player>[])
        if (shortlist.contains(p.id)) p.id: p,
    };
    final players = <Player>[
      for (final id in shortlist)
        if (owned.contains(id))
          squad.firstWhere((p) => p.id == id)
        else if (dbById[id] != null)
          dbById[id]!,
    ]..sort((a, b) => b.ovr.compareTo(a.ovr));

    const service = TransferMarketService();
    final byName = {for (final t in db?.teams ?? const <Team>[]) t.name: t};

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final seller = byName[player.currentTeam];
        final free = service.isFreeAgent(player, seasonYear);
        final ask = free
            ? 0
            : service.askingPrice(player, seller, seasonYear: seasonYear);
        final affordable = ask <= budget;
        return _PlayerRow(
          player: player,
          priceLabel: free ? 'FREE' : _euro(ask),
          priceColor: affordable
              ? AppTheme.pitchGreen
              : Theme.of(context).colorScheme.error,
          shortlisted: true,
          footnote: free
              ? 'Out of contract'
              : '${player.currentTeam} want ${_euro(ask)}',
          onTap: () => onOpen(player),
          actions: [
            _RowAction(
              icon: Icons.gavel,
              tooltip: 'Open talks',
              active: affordable,
              onPressed: affordable ? () => onBid(player) : null,
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

class _TalksTab extends ConsumerWidget {
  const _TalksTab({required this.onOpenMarket});

  final VoidCallback onOpenMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final desk = session.transferDesk;

    final active = desk.negotiations.where((n) => n.isActive).toList()
      ..sort((a, b) => b.counterOffer.compareTo(a.counterOffer));
    final finished = desk.negotiations.where((n) => !n.isActive).toList()
      ..sort((a, b) => b.startedMatchday.compareTo(a.startedMatchday));

    if (desk.negotiations.isEmpty) {
      return EmptyState(
        icon: Icons.handshake_outlined,
        title: 'No talks open',
        message: 'Bid for a player and the selling club will answer.',
        action: TextButton(
          onPressed: onOpenMarket,
          child: const Text('Find a player'),
        ),
      );
    }

    // One id index per rebuild replaces a per-negotiation `.where` scan of
    // the whole 16k player database.
    final byId = {
      for (final p in db?.players ?? const <Player>[]) p.id: p,
    };

    Player? playerFor(int id) {
      final own = session.team.squad.where((p) => p.id == id).firstOrNull;
      if (own != null) return own;
      return byId[id];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        for (final n in active)
          _TalkCard(
            negotiation: n,
            player: playerFor(n.playerId),
            onAcceptCounter: () => _acceptCounter(context, ref, n),
            onBidAgain: () {
              final player = playerFor(n.playerId);
              if (player != null) openTransferBid(context, ref, player);
            },
            onTerms: () {
              final player = playerFor(n.playerId);
              if (player != null) openTermsDialog(context, ref, player);
            },
            onWalkAway: () {
              walkAwayFromTalks(ref, n.playerId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Walked away from ${n.playerName}.')),
              );
            },
          ),
        if (finished.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Recent outcomes',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final n in finished.take(8)) _ResolvedTalkCard(negotiation: n),
        ],
      ],
    );
  }

  Future<void> _acceptCounter(
      BuildContext context, WidgetRef ref, TransferNegotiation n) async {
    final session = ref.read(careerSessionProvider);
    final db = ref.read(playerDatabaseProvider).valueOrNull;
    final player = db?.players.where((p) => p.id == n.playerId).firstOrNull ??
        session?.team.squad.where((p) => p.id == n.playerId).firstOrNull;
    if (player == null) return;
    final result = acceptCounterOffer(ref, player);
    if (result == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
    if (result.outcome == BidOutcome.accepted && context.mounted) {
      await openTermsDialog(context, ref, player);
    }
  }
}

class _TalkCard extends StatelessWidget {
  const _TalkCard({
    required this.negotiation,
    required this.player,
    required this.onAcceptCounter,
    required this.onBidAgain,
    required this.onTerms,
    required this.onWalkAway,
  });

  final TransferNegotiation negotiation;
  final Player? player;
  final VoidCallback onAcceptCounter;
  final VoidCallback onBidAgain;
  final VoidCallback onTerms;
  final VoidCallback onWalkAway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = negotiation;
    final feeAgreed = n.stage == DealStage.feeAgreed;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (player != null)
                  PlayerAvatar(player: player!, radius: 16)
                else
                  const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.playerName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontSize: 15),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${n.sellerClub} · ask ${_euro(n.askingPrice)}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StageChip(stage: n.stage),
              ],
            ),
            const SizedBox(height: 8),
            Text(n.message, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!feeAgreed) _Tag(text: 'Round ${n.round}/3'),
                if (!feeAgreed) _Tag(text: 'Patience ${n.patience}/3'),
                _Tag(text: 'Wage ${_euro(n.wageDemand)}/wk'),
                if (n.rivalClub != null)
                  _Tag(
                    text: n.rivalDeadlineMatchday < 0
                        ? 'Rival: ${n.rivalClub}'
                        : 'Rival: ${n.rivalClub} · ${n.rivalDeadlineMatchday}',
                    color: Colors.orange,
                  ),
              ],
            ),
            if (n.rivalClub != null) ...[
              const SizedBox(height: 6),
              Text(
                'A rival is circling. If you stall, they will sign him.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 4),
            if (feeAgreed)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onTerms,
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: Text('Agree terms · ${_euro(n.agreedFee ?? 0)}'),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: onWalkAway,
                    child: const Text('Walk away'),
                  ),
                  if (n.counterOffer > 0)
                    OutlinedButton(
                      onPressed: onAcceptCounter,
                      child: Text('Accept ${_euro(n.counterOffer)}'),
                    ),
                  FilledButton(
                    onPressed: onBidAgain,
                    child: const Text('Bid again'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedTalkCard extends StatelessWidget {
  const _ResolvedTalkCard({required this.negotiation});

  final TransferNegotiation negotiation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: _StageChip(stage: negotiation.stage),
        title: Text(negotiation.playerName, overflow: TextOverflow.ellipsis),
        subtitle: Text(negotiation.message, maxLines: 2,
            overflow: TextOverflow.ellipsis),
        trailing: Text('MD ${negotiation.startedMatchday}',
            style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.stage});

  final DealStage stage;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (stage) {
      DealStage.bidding => ('Bidding', Colors.blue),
      DealStage.feeAgreed => ('Fee agreed', AppTheme.pitchGreen),
      DealStage.completed => ('Signed', AppTheme.pitchGreen),
      DealStage.collapsed => ('Collapsed', Colors.red),
      DealStage.hijacked => ('Hijacked', Colors.orange),
    };
    return _Tag(text: label, color: color);
  }
}

class _OffersTab extends StatelessWidget {
  const _OffersTab({
    required this.bids,
    required this.onAccept,
    required this.onReject,
    this.squadAtMinimum = false,
  });

  final List<IncomingBid> bids;
  final ValueChanged<IncomingBid> onAccept;
  final ValueChanged<IncomingBid> onReject;

  /// True when the squad sits at the 16-player floor, so every offer here is
  /// unanswerable until someone is signed or promoted.
  final bool squadAtMinimum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (bids.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No bids for your players',
        message: squadAtMinimum
            ? 'Your squad is at the 16-player minimum, so clubs will not bid '
                'for anyone until you add a player.'
            : 'List or loan-list a player from My Players and clubs will '
                'start calling after the next matchday.',
      );
    }
    final loans = bids.where((b) => b.isLoan).toList();
    final permanent = bids.where((b) => !b.isLoan).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (squadAtMinimum) ...[
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your squad is at the 16-player minimum: accepting any of '
                      'these would leave it short. Sign or promote a player '
                      'first, then come back.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (permanent.isNotEmpty) ...[
          Text('Permanent offers', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final bid in permanent)
            _OfferCard(
              bid: bid,
              onAccept: () => onAccept(bid),
              onReject: () => onReject(bid),
            ),
        ],
        if (loans.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Loan offers', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final bid in loans)
            _OfferCard(
              bid: bid,
              onAccept: () => onAccept(bid),
              onReject: () => onReject(bid),
            ),
        ],
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.bid,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingBid bid;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bid.playerName,
                      style:
                          theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  Text('${bid.club} · matchday ${bid.matchday}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  if (bid.isLoan)
                    _Tag(
                      text: 'Loan · they pay ${bid.wageSharePercent}% '
                          'of his wage',
                      color: Colors.orange,
                    )
                  else
                    Text(_euro(bid.fee),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: AppTheme.pitchGreen)),
                ],
              ),
            ),
            TextButton(
              onPressed: onReject,
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: onAccept,
              child: Text(bid.isLoan ? 'Loan him' : 'Accept'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyPlayersTab extends StatelessWidget {
  const _MyPlayersTab({
    required this.squad,
    required this.seasonYear,
    required this.onSell,
    required this.onList,
    required this.onOpen,
  });

  final List<Player> squad;
  final int seasonYear;
  final ValueChanged<Player> onSell;
  final ValueChanged<Player> onList;
  final ValueChanged<Player> onOpen;

  @override
  Widget build(BuildContext context) {
    if (squad.isEmpty) {
      return const EmptyState(icon: Icons.groups_outlined, title: 'No squad');
    }
    final sorted = [...squad]..sort((a, b) => b.ovr.compareTo(a.ovr));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final player = sorted[index];
        final (listed, asking) = transferListingOf(player);
        final expiry = player.contractExpiry?.year;
        final loanedIn = player.hiddenAttributes['onLoanFrom'] as String?;
        final loanListed = loanListingOf(player);
        return _PlayerRow(
          player: player,
          priceLabel: listed && asking != null
              ? _euro(asking)
              : _euro(FinancialService()
                  .calculateTransferValue(player, seasonYear: seasonYear)),
          priceColor: listed ? Colors.orange : null,
          shortlisted: listed,
          footnote: loanedIn != null
              ? 'On loan from $loanedIn until $seasonYear'
              : listed && asking != null
                  ? 'Listed · asking ${_euro(asking)}'
                  : loanListed
                      ? 'Loan listed'
                      : expiry != null
                          ? 'Contract to $expiry'
                          : 'No contract data',
          onTap: () => onOpen(player),
          actions: [
            _RowAction(
              icon: listed ? Icons.sell : Icons.sell_outlined,
              tooltip: listed ? 'Take off the transfer list' : 'Transfer list',
              active: listed,
              onPressed: () => onList(player),
            ),
            _RowAction(
              icon: Icons.payments_outlined,
              tooltip: 'Sell now',
              onPressed: () => onSell(player),
            ),
          ],
        );
      },
    );
  }
}

class _NewsTab extends StatelessWidget {
  const _NewsTab({
    required this.news,
    required this.squad,
    required this.clubName,
  });

  final List<TransferNewsItem> news;
  final List<Player> squad;
  final String clubName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (news.isEmpty) {
      return const EmptyState(
        icon: Icons.newspaper_outlined,
        title: 'No transfer news yet',
        message: 'Open talks or list a player and the feed will fill up.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: news.length,
      itemBuilder: (context, index) {
        final item = news[index];
        final icon = switch (item.type) {
          'signing' => Icons.check_circle_outline,
          'hijack' => Icons.warning_amber_rounded,
          'rival' => Icons.public,
          'collapse' => Icons.link_off,
          'deadline' => Icons.timer_outlined,
          'sale' => Icons.swap_horiz,
          'loan' => Icons.event_repeat,
          'unsettled' => Icons.sentiment_dissatisfied,
          'request' => Icons.outbox_outlined,
          'settled' => Icons.sentiment_satisfied_alt,
          'summary' => Icons.receipt_long_outlined,
          'minimum' => Icons.groups_2_outlined,
          _ => Icons.gavel_outlined,
        };
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(item.body, style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        transferReaction(
                          item: item,
                          squad: squad,
                          clubName: clubName,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text('MD ${item.matchday}', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.priceLabel,
    required this.shortlisted,
    required this.onTap,
    required this.actions,
    this.priceColor,
    this.footnote,
    this.chips = const [],
  });

  final Player player;
  final String priceLabel;
  final Color? priceColor;
  final bool shortlisted;
  final String? footnote;
  final List<Widget> chips;
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
                    Row(
                      children: [
                        if (shortlisted)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.star,
                                size: 12, color: Colors.amber),
                          ),
                        Expanded(
                          child: Text(
                            player.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${player.primaryPosition} · ${player.age} yrs · '
                      '${player.currentTeam}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (footnote != null)
                      Text(
                        footnote!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.pitchGreen,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 4, runSpacing: 4, children: chips),
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
                    priceLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: priceColor ?? AppTheme.pitchGreen,
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: tint),
      ),
    );
  }
}

// --- Transfer actions shared by every surface that lists players. ---

/// Opens the bidding dialog for [player] and walks the manager through the
/// whole deal: fee, then personal terms when the club agrees.
Future<void> openTransferBid(
  BuildContext context,
  WidgetRef ref,
  Player player,
) async {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  const service = TransferMarketService();
  final season = session.season;
  final desk = session.transferDesk;

  var negotiation = desk.forPlayer(player.id);
  final free = service.isFreeAgent(player, season.currentYear);
  final window = TransferWindow.of(season);
  if (!service.canSign(window, free)) {
    _snack(context, 'The window is shut. Only free agents can be signed.');
    return;
  }

  if (negotiation == null) {
    if (!startTransferTalk(ref, player)) {
      _snack(context,
          ref.read(transferBlockReasonProvider) ?? 'Cannot open talks.');
      return;
    }
    negotiation = desk.forPlayer(player.id);
    if (negotiation == null) return;
  }
  if (negotiation.stage == DealStage.feeAgreed) {
    await openTermsDialog(context, ref, player);
    return;
  }

  final submitted = await showDialog<int>(
    context: context,
    builder: (context) => _BidDialog(
      player: player,
      negotiation: negotiation!,
      budget: session.team.transferBudget,
    ),
  );
  if (submitted == null || !context.mounted) return;

  final result = submitBid(ref, player, submitted);
  if (result == null) {
    _snack(context,
        ref.read(transferBlockReasonProvider) ?? 'That bid could not be sent.');
    return;
  }
  final accepted = result.outcome == BidOutcome.accepted;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(accepted
          ? 'Fee agreed'
          : result.outcome == BidOutcome.collapsed
              ? 'Talks over'
              : 'Bid rejected'),
      content: Text(result.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (accepted)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Discuss terms'),
          ),
      ],
    ),
  );
  if (accepted && context.mounted) {
    await openTermsDialog(context, ref, player);
  }
}

/// The fee dialog.
///
/// A [StatefulWidget] rather than a controller created by the caller, because
/// the caller disposes it as soon as the future completes — while the dialog
/// route is still animating out and rebuilding its text field.
class _BidDialog extends StatefulWidget {
  const _BidDialog({
    required this.player,
    required this.negotiation,
    required this.budget,
  });

  final Player player;
  final TransferNegotiation negotiation;
  final double budget;

  @override
  State<_BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<_BidDialog> {
  late final TextEditingController _fee = TextEditingController(
    text: widget.negotiation.counterOffer > 0
        ? widget.negotiation.counterOffer.toString()
        : widget.negotiation.askingPrice > 0
            ? widget.negotiation.askingPrice.toString()
            : '0',
  );

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.negotiation;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Bid for ${widget.player.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${n.sellerClub} want ${_euro(n.askingPrice)}.\n'
              'Your budget: ${_euro(widget.budget)}.\n'
              'His agent wants ${_euro(n.wageDemand)}/wk.',
              style: theme.textTheme.bodySmall,
            ),
            if (n.counterOffer > 0) ...[
              const SizedBox(height: 6),
              Text(
                'They countered at ${_euro(n.counterOffer)}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppTheme.pitchGreen),
              ),
            ],
            if (n.rivalClub != null) ...[
              const SizedBox(height: 6),
              Text(
                '${n.rivalClub} are interested. You have '
                '${n.rivalDeadlineMatchday} matchday(s) before they can '
                'close a deal.',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Fee (€)',
                hintText: n.askingPrice > 0
                    ? 'Ask ${_euro(n.askingPrice)}'
                    : 'Free agent',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_fee.text.trim()) ?? 0),
          child: const Text('Send bid'),
        ),
      ],
    );
  }
}

/// Loan offer dialog: what share of the player's wage the manager will pay.
Future<void> openLoanDialog(
  BuildContext context,
  WidgetRef ref,
  Player player,
) async {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  const service = TransferMarketService();
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final owner = db?.teams.where((t) => t.name == player.currentTeam).firstOrNull;
  final expected = service.loanWageShare(player, owner);
  // The dropdown must contain exactly one item matching its value, so every
  // share loanWageShare can return is offered, and the initial value is
  // snapped onto the nearest option for any other value.
  const shares = [30, 40, 50, 60, 70, 100];
  var share = shares.reduce(
      (a, b) => (a - expected).abs() <= (b - expected).abs() ? a : b);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text('Loan ${player.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No fee. A season-long loan from ${player.currentTeam}, and he '
              'goes back at the end of it.\n'
              'They want you to cover at least $expected% of his '
              '${_euro(player.weeklyWage)}/wk wage.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: share,
              decoration: const InputDecoration(labelText: 'Your wage share'),
              items: [
                for (final s in shares)
                  DropdownMenuItem(value: s, child: Text('$s%')),
              ],
              onChanged: (v) => setLocal(() => share = v ?? share),
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
            child: const Text('Make the offer'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final done = offerLoanDeal(ref, player, wageSharePercent: share);
  _snack(
    context,
    done
        ? '${player.name} joins on loan until the end of the season.'
        : ref.read(transferBlockReasonProvider) ?? 'That loan fell through.',
  );
}

/// What the manager put on the contract sheet.
class _TermOffer {
  const _TermOffer({
    required this.wage,
    required this.bonus,
    required this.years,
    required this.role,
  });

  final int wage;
  final int bonus;
  final int years;
  final String role;
}

/// Personal-terms sheet: wage, signing bonus, contract length and squad role.
Future<void> openTermsDialog(
  BuildContext context,
  WidgetRef ref,
  Player player,
) async {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  const service = TransferMarketService();
  final negotiation = session.transferDesk.forPlayer(player.id);
  final demand =
      negotiation?.wageDemand ?? service.wageDemand(player, session.team);

  final offer = await showDialog<_TermOffer>(
    context: context,
    builder: (context) => _TermsDialog(
      player: player,
      demand: demand,
      reputation: session.team.reputation,
    ),
  );
  if (offer == null || !context.mounted) return;

  final signed = offerPersonalTerms(
    ref,
    player,
    wage: offer.wage,
    bonus: offer.bonus,
    years: offer.years,
    role: offer.role,
  );
  _snack(
    context,
    signed
        ? '${player.name} signed!'
        : ref.read(transferBlockReasonProvider) ?? 'He turned you down.',
  );
}

class _TermsDialog extends StatefulWidget {
  const _TermsDialog({
    required this.player,
    required this.demand,
    required this.reputation,
  });

  final Player player;
  final int demand;
  final int reputation;

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  late final TextEditingController _wage =
      TextEditingController(text: widget.demand.toString());
  late final TextEditingController _bonus = TextEditingController(text: '0');
  int _years = 4;
  String _role = 'First Team';

  @override
  void dispose() {
    _wage.dispose();
    _bonus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Terms for ${widget.player.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'He expects a club of reputation '
              '${TransferMarketService().requiredReputation(widget.player)}+ '
              '(yours is ${widget.reputation}).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wage,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Weekly wage (€)',
                hintText: 'Demand ${_euro(widget.demand)}',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bonus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Signing bonus (€)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _years,
              decoration: const InputDecoration(labelText: 'Contract length'),
              items: [
                for (var y = 1; y <= 5; y++)
                  DropdownMenuItem(
                    value: y,
                    child: Text('$y year${y == 1 ? '' : 's'}'),
                  ),
              ],
              onChanged: (v) => setState(() => _years = v ?? _years),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration:
                  const InputDecoration(labelText: 'Promised squad role'),
              items: const [
                DropdownMenuItem(
                    value: 'Key Player', child: Text('Key Player')),
                DropdownMenuItem(
                    value: 'First Team', child: Text('First Team')),
                DropdownMenuItem(
                    value: 'Squad Player', child: Text('Squad Player')),
                DropdownMenuItem(value: 'Rotation', child: Text('Rotation')),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _TermOffer(
              wage: int.tryParse(_wage.text.trim()) ?? 0,
              bonus: int.tryParse(_bonus.text.trim()) ?? 0,
              years: _years,
              role: _role,
            ),
          ),
          child: const Text('Offer contract'),
        ),
      ],
    );
  }
}

String _euro(num amount) => TransferMarketService.money(amount);

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
