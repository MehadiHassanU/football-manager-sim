import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/player.dart';
import '../core/models/team.dart';
import '../core/models/transfer.dart';
import '../core/services/transfer_market_service.dart';
import 'career_session_provider.dart';
import 'data_providers.dart';

/// The club currently holding [player], when the database knows it.
Team? _sellerOf(WidgetRef ref, Player player) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  if (db == null) return null;
  for (final team in db.teams) {
    if (team.name == player.currentTeam) return team;
  }
  return null;
}

int _transferSeed(Player player, int matchday) =>
    player.id * 7919 + matchday * 131;

/// Opens (or reopens) talks with the club that owns [player].
///
/// The asking price is public, the reservation price is not, and a rival club
/// may already be circling — the manager only finds out after bidding starts.
/// Returns false and sets [transferBlockReasonProvider] when the move is
/// impossible (window shut, already talking, no seller).
bool startTransferTalk(WidgetRef ref, Player player) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  const service = TransferMarketService();
  final season = session.season;
  final seller = _sellerOf(ref, player);
  final free = service.isFreeAgent(player, season.currentYear);
  final window = TransferWindow.of(season);

  if (!service.canSign(window, free)) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'The window is shut. Only free agents can be signed right now.';
    return false;
  }
  final open = session.transferDesk.forPlayer(player.id);
  if (open != null && open.isActive) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Talks for ${player.name} are already open.';
    return false;
  }
  // Walking away (or being hijacked) must cost something: the club will not
  // sit straight back down at the table, so a collapsed deal cannot be
  // rerolled until a couple of matchdays have passed.
  if (open != null &&
      (open.stage == DealStage.collapsed || open.stage == DealStage.hijacked) &&
      season.currentMatchday - open.startedMatchday < 2) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Talks over ${player.name} broke down. '
        '${open.sellerClub} will not reopen them yet.';
    return false;
  }

  final asking = free
      ? 0
      : service.askingPrice(
          player,
          seller,
          seasonYear: season.currentYear,
          buyer: session.team,
        );
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final rival = free
      ? null
      : service.rivalClubFor(
          player,
          db?.teams ?? const [],
          seasonYear: season.currentYear,
        );

  final negotiation = TransferNegotiation(
    playerId: player.id,
    playerName: player.name,
    sellerClub: player.currentTeam,
    askingPrice: asking,
    reservationPrice: service.reservationPrice(asking),
    stage: DealStage.bidding,
    round: 0,
    patience: 3,
    lastOffer: 0,
    counterOffer: 0,
    startedMatchday: season.currentMatchday,
    rivalDeadlineMatchday: rival == null ? -1 : season.currentMatchday + 2,
    wageDemand: service.wageDemand(player, session.team),
    requiredReputation: service.requiredReputation(player),
    message: free
        ? 'Free agent — he can sign for nothing.'
        : '${player.currentTeam} want ${TransferMarketService.money(asking)}.',
    rivalClub: rival,
  );
  session.transferDesk.replace(negotiation);
  session.transferDesk.addNews(TransferNewsItem(
    type: 'talk',
    title: 'Talks opened for ${player.name}',
    body: free
        ? 'Out of contract and free to move.'
        : '${player.currentTeam} are asking '
            '${TransferMarketService.money(asking)}.',
    matchday: season.currentMatchday,
  ));
  ref.read(transferBlockReasonProvider.notifier).state = null;
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return true;
}

/// Sends a bid for [player] and lets the selling club answer.
///
/// Three rounds maximum: the club counters once, twice, then walks away. A bid
/// at or above the public ask is accepted immediately. Returns the seller's
/// answer so the screen can react to a counter or a collapse.
BidResult? submitBid(WidgetRef ref, Player player, int fee) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return null;
  const service = TransferMarketService();

  var negotiation = session.transferDesk.forPlayer(player.id);
  if (negotiation == null || !negotiation.isActive) {
    if (!startTransferTalk(ref, player)) return null;
    negotiation = session.transferDesk.forPlayer(player.id);
    if (negotiation == null) return null;
  }
  if (fee > session.team.transferBudget) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'The fee is more than your transfer budget.';
    return null;
  }
  if (fee <= 0 && negotiation.askingPrice > 0) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Enter a fee above zero.';
    return null;
  }

  final season = session.season;
  final result = service.evaluateBid(
    asking: negotiation.askingPrice,
    reservation: negotiation.reservationPrice,
    offer: fee,
    round: negotiation.round,
    patience: negotiation.patience,
    seed: _transferSeed(player, season.currentMatchday),
  );

  ref.read(transferBlockReasonProvider.notifier).state = null;
  final desk = session.transferDesk;
  switch (result.outcome) {
    case BidOutcome.accepted:
      desk.replace(negotiation.copyWith(
        stage: DealStage.feeAgreed,
        round: result.round,
        lastOffer: fee,
        counterOffer: 0,
        clearCounter: true,
        agreedFee: fee,
        message: result.message,
      ));
      desk.addNews(TransferNewsItem(
        type: 'fee',
        title: '${negotiation.sellerClub} accept for ${player.name}',
        body: result.message,
        matchday: season.currentMatchday,
      ));
    case BidOutcome.countered:
      desk.replace(negotiation.copyWith(
        round: result.round,
        patience: result.patience,
        lastOffer: fee,
        counterOffer: result.counter,
        message: result.message,
      ));
      desk.addNews(TransferNewsItem(
        type: 'bid',
        title: 'Bid rejected for ${player.name}',
        body: result.message,
        matchday: season.currentMatchday,
      ));
    case BidOutcome.collapsed:
      desk.replace(negotiation.copyWith(
        stage: DealStage.collapsed,
        round: result.round,
        patience: 0,
        lastOffer: fee,
        counterOffer: 0,
        clearCounter: true,
        message: result.message,
      ));
      desk.addNews(TransferNewsItem(
        type: 'collapse',
        title: 'Talks collapse for ${player.name}',
        body: result.message,
        matchday: season.currentMatchday,
      ));
    case BidOutcome.rejected:
      desk.replace(negotiation.copyWith(message: result.message));
  }
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return result;
}

/// Accepts the seller's counter-offer as-is.
BidResult? acceptCounterOffer(WidgetRef ref, Player player) {
  final session = ref.read(careerSessionProvider);
  final negotiation = session?.transferDesk.forPlayer(player.id);
  if (negotiation == null || negotiation.counterOffer <= 0) return null;
  return submitBid(ref, player, negotiation.counterOffer);
}

/// Walks away, ending the negotiation without a fee.
void walkAwayFromTalks(WidgetRef ref, int playerId) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  final negotiation = session.transferDesk.forPlayer(playerId);
  if (negotiation == null || !negotiation.isActive) return;
  session.transferDesk.replace(negotiation.copyWith(
    stage: DealStage.collapsed,
    counterOffer: 0,
    clearCounter: true,
    message: 'You walked away from the table.',
  ));
  notifySessionChanged(ref);
  saveCareerNow(ref);
}

/// Offers personal terms once a fee has been agreed.
///
/// This is the second negotiation: the agent can refuse the wage, refuse the
/// squad role, or decide the club is not big enough. Returns false when the
/// deal did not complete, with the reason in [transferBlockReasonProvider].
bool offerPersonalTerms(
  WidgetRef ref,
  Player player, {
  required int wage,
  required int bonus,
  required int years,
  required String role,
}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  const service = TransferMarketService();
  final negotiation = session.transferDesk.forPlayer(player.id);
  if (negotiation == null || negotiation.stage != DealStage.feeAgreed) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Agree a fee with the club first.';
    return false;
  }
  final fee = negotiation.agreedFee ?? negotiation.askingPrice;
  if (fee + bonus > session.team.transferBudget) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'The fee plus signing bonus is more than your transfer budget.';
    return false;
  }

  final terms = service.evaluateTerms(
    player: player,
    buyer: session.team,
    wage: wage,
    bonus: bonus,
    years: years,
    role: role,
  );
  final desk = session.transferDesk;
  if (!terms.accepted) {
    desk.replace(negotiation.copyWith(
      wageDemand:
          terms.counterWage > 0 ? terms.counterWage : negotiation.wageDemand,
      message: terms.message,
    ));
    desk.addNews(TransferNewsItem(
      type: 'terms',
      title: '${player.name} rejects personal terms',
      body: terms.message,
      matchday: session.season.currentMatchday,
    ));
    ref.read(transferBlockReasonProvider.notifier).state = terms.message;
    notifySessionChanged(ref);
    saveCareerNow(ref);
    return false;
  }

  // The actual move goes through buyPlayer so the budget and FFP checks are
  // exactly the same ones a direct signing uses. The fee passed in includes
  // the signing bonus because both come out of the transfer budget.
  if (!buyPlayer(
    ref,
    player,
    fee + bonus,
    wage: wage,
    contractYears: years,
  )) {
    return false;
  }
  player.requestedTransfer = false;
  player.hiddenAttributes.remove('transferListed');
  desk.recordMove(TransferMove(
    playerId: player.id,
    playerName: player.name,
    fromClub: negotiation.sellerClub,
    toClub: session.team.name,
    kind: fee == 0 ? 'free' : 'permanent',
    fee: fee,
    wage: wage,
    year: session.season.currentYear,
    matchday: session.season.currentMatchday,
  ));

  desk.replace(negotiation.copyWith(
    stage: DealStage.completed,
    agreedFee: fee,
    agreedWage: wage,
    agreedBonus: bonus,
    agreedYears: years,
    agreedRole: role,
    message: terms.message,
  ));
  desk.addNews(TransferNewsItem(
    type: 'signing',
    title: '${player.name} signs for ${session.team.name}',
    body: 'Fee ${TransferMarketService.money(fee)}'
        '${bonus > 0 ? ' · bonus ${TransferMarketService.money(bonus)}' : ''}'
        ' · $years-year deal · ${TransferMarketService.money(wage)}/wk. '
        '${role == 'Key Player' ? 'He arrives as a key player.' : ''}',
    matchday: session.season.currentMatchday,
  ));
  ref.read(transferBlockReasonProvider.notifier).state = null;
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return true;
}

/// Accepts an offer from another club for one of the manager's players.
bool acceptIncomingBid(WidgetRef ref, IncomingBid bid) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  final player =
      session.team.squad.where((p) => p.id == bid.playerId).firstOrNull;
  if (player == null) return false;
  if (!sellPlayer(ref, player, bid.fee, buyerClub: bid.club)) return false;
  session.transferDesk.incomingBids
      .removeWhere((b) => b.playerId == bid.playerId);
  session.transferDesk.addNews(TransferNewsItem(
    type: 'sale',
    title: '${player.name} joins ${bid.club}',
    body: 'Sold for ${TransferMarketService.money(bid.fee)}. '
        'The fee has been added to your transfer budget.',
    matchday: session.season.currentMatchday,
  ));
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return true;
}

/// Accepts a loan offer for one of the manager's players.
///
/// He leaves the squad for the rest of the season, but the club keeps his
/// registration (and the part of his wage the borrower is not covering), so he
/// comes back at the rollover rather than being lost.
bool acceptLoanOffer(WidgetRef ref, IncomingBid bid) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  final player =
      session.team.squad.where((p) => p.id == bid.playerId).firstOrNull;
  if (player == null) return false;

  // A loan takes him out of the squad for the rest of the season, so it is
  // bound by the same 16-player floor as a sale. Checked here rather than
  // only when offers are generated, because an offer from a previous
  // matchday can still be sitting in the Offers tab.
  if (session.team.squad.length <= 16) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Your squad must keep at least 16 players. Sign someone first.';
    return false;
  }

  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final borrower = db?.teams.where((t) => t.name == bid.club).firstOrNull;
  final fullWage = player.weeklyWage;
  final share = bid.wageSharePercent.clamp(0, 100);

  session.team.squad.removeWhere((p) => p.id == player.id);
  session.team.loanedOutWages += fullWage * (100 - share) / 100;
  session.transferDesk.loans.add(LoanDeal(
    playerId: player.id,
    playerName: player.name,
    fromClub: session.team.name,
    toClub: bid.club,
    wageSharePercent: share,
    untilYear: session.season.currentYear,
    matchday: session.season.currentMatchday,
    wage: fullWage.round(),
  ));
  session.transferDesk.recordMove(TransferMove(
    playerId: player.id,
    playerName: player.name,
    fromClub: session.team.name,
    toClub: bid.club,
    kind: 'loan',
    fee: 0,
    wage: fullWage.round(),
    year: session.season.currentYear,
    matchday: session.season.currentMatchday,
  ));
  if (db != null && borrower != null) {
    for (final team in db.teams) {
      team.squad.removeWhere((p) => p.id == player.id);
    }
    player.currentTeam = borrower.name;
    borrower.squad.add(player);
  }
  session.transferDesk.incomingBids
      .removeWhere((b) => b.playerId == bid.playerId);
  session.transferDesk.addNews(TransferNewsItem(
    type: 'sale',
    title: '${player.name} joins ${bid.club} on loan',
    body: '${bid.club} pay $share% of his wage. He returns at the end of the '
        'season.',
    matchday: session.season.currentMatchday,
  ));
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return true;
}

/// Borrows a player for the rest of the season.
///
/// [wageSharePercent] is what the manager offers to pay; the owner has an
/// expectation and will refuse a lowball. No fee changes hands, and the player
/// goes home at the rollover.
bool offerLoanDeal(
  WidgetRef ref,
  Player player, {
  int wageSharePercent = 100,
}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  const service = TransferMarketService();
  final season = session.season;
  final window = TransferWindow.of(season);
  if (!window.isOpen) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Loans are only possible while the window is open.';
    return false;
  }
  if (session.team.squad.any((p) => p.id == player.id)) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'He is already at your club.';
    return false;
  }

  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final owner = db?.teams.where((t) => t.name == player.currentTeam).firstOrNull;
  if (!service.loanAvailable(player, owner)) {
    ref.read(transferBlockReasonProvider.notifier).state =
        '${player.currentTeam} are not willing to loan him out.';
    return false;
  }
  final expected = service.loanWageShare(player, owner);
  if (wageSharePercent < expected) {
    ref.read(transferBlockReasonProvider.notifier).state =
        '${player.currentTeam} want you to cover at least $expected% of his '
        'wage.';
    return false;
  }
  if (session.team.squad.length >= 25) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Your squad is full (25 players).';
    return false;
  }

  final share = wageSharePercent.clamp(0, 100);
  final loanCost = service.loanCost(player, share).toDouble();
  final refusal = wageCeilingRefusal(session.team, loanCost);
  if (refusal != null) {
    ref.read(transferBlockReasonProvider.notifier).state = refusal;
    return false;
  }

  final fullWage = player.weeklyWage;
  player
    ..weeklyWage = loanCost
    ..hiddenAttributes['onLoanFrom'] = player.currentTeam
    ..hiddenAttributes['loanUntilYear'] = season.currentYear;
  session.team.squad.add(player);
  session.transferDesk.loans.add(LoanDeal(
    playerId: player.id,
    playerName: player.name,
    fromClub: player.hiddenAttributes['onLoanFrom'] as String,
    toClub: session.team.name,
    wageSharePercent: share,
    untilYear: season.currentYear,
    matchday: season.currentMatchday,
    wage: fullWage.round(),
  ));
  session.transferDesk.recordMove(TransferMove(
    playerId: player.id,
    playerName: player.name,
    fromClub: player.hiddenAttributes['onLoanFrom'] as String,
    toClub: session.team.name,
    kind: 'loan',
    fee: 0,
    wage: fullWage.round(),
    year: season.currentYear,
    matchday: season.currentMatchday,
  ));
  if (db != null) {
    for (final team in db.teams) {
      team.squad.removeWhere((p) => p.id == player.id);
    }
    final mirror = db.teams.where((t) => t.name == session.team.name).firstOrNull;
    mirror?.squad.add(player);
    player.currentTeam = session.team.name;
  }
  session.transferDesk.addNews(TransferNewsItem(
    type: 'signing',
    title: '${player.name} arrives on loan',
    body: 'No fee. You pay $share% of his '
        '${TransferMarketService.money(fullWage)}/wk wage until the end of '
        'the season.',
    matchday: season.currentMatchday,
  ));
  ref.read(transferBlockReasonProvider.notifier).state = null;
  notifySessionChanged(ref);
  saveCareerNow(ref);
  return true;
}

/// Rejects an incoming offer.
void rejectIncomingBid(WidgetRef ref, IncomingBid bid) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  session.transferDesk.incomingBids
      .removeWhere((b) => b.playerId == bid.playerId);
  session.transferDesk.addNews(TransferNewsItem(
    type: 'sale',
    title: 'Bid for ${bid.playerName} rejected',
    body: '${bid.club} offered ${TransferMarketService.money(bid.fee)}.',
    matchday: session.season.currentMatchday,
  ));
  notifySessionChanged(ref);
  saveCareerNow(ref);
}

/// Numbers a fan or the board would put on a deal, used as the reaction line
/// under each news item.
String transferReaction({
  required TransferNewsItem item,
  required List<Player> squad,
  required String clubName,
}) {
  switch (item.type) {
    case 'signing':
      return 'Fans: "This is the statement signing we wanted."';
    case 'hijack':
      return 'Board: "We were too slow. That cannot happen again."';
    case 'rival':
      return 'Fans: "Look at them strengthen while we sit still."';
    case 'collapse':
      return 'Fans: "Amateur hour in the recruitment office."';
    case 'sale':
      return 'Board: "Good money for a player who wanted out."';
    case 'deadline':
      return 'Board: "Get it done before the window shuts."';
    case 'unsettled':
      return 'Fans: "Play him or lose him — it is that simple."';
    case 'request':
      return 'Board: "A transfer request means the price just dropped."';
    case 'settled':
      return 'Fans: "Good to see him smiling again."';
    case 'summary':
      return 'Board: "We will judge the window when the table settles."';
    case 'minimum':
      return 'Board: "A squad that thin is one injury from a crisis."';
    default:
      return 'Fans are watching this one closely.';
  }
}

/// Deterministic rival response text for a rejected bid, so a failure reads
/// like a real negotiation rather than a generic error.
String counterTone(int offer, int asking) {
  if (asking <= 0) return 'No fee is needed.';
  if (offer >= asking * 0.95) return 'Very close — they want it sweetened.';
  if (offer >= asking * 0.7) return 'They see the bid as a starting point.';
  return 'They took that bid as an insult.';
}

/// How many rounds are left before the seller walks away.
int roundsLeft(TransferNegotiation negotiation) =>
    max(0, 3 - negotiation.round);
