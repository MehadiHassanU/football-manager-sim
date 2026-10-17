import 'player.dart';
import 'season.dart';
import 'team.dart';

/// Which part of the calendar the market is in.
///
/// Windows are derived from the schedule rather than stored, so a save that is
/// restored on a different matchday can never disagree with the fixtures.
class TransferWindow {
  const TransferWindow({
    required this.label,
    required this.isOpen,
    required this.isDeadlineDay,
    required this.closesAtMatchday,
  });

  final String label;
  final bool isOpen;
  final bool isDeadlineDay;
  final int closesAtMatchday;

  static const TransferWindow _closed = TransferWindow(
    label: 'Window closed',
    isOpen: false,
    isDeadlineDay: false,
    closesAtMatchday: -1,
  );

  /// The summer window covers the opening matchdays; the winter window wraps
  /// the mid-season break. Everything else is closed except free agents.
  factory TransferWindow.of(SeasonState season) {
    if (season.isPostSeason) return _closed;
    final matchday = season.currentMatchday;

    final winterOpen = (season.winterBreakRound - 2).clamp(1, 99);
    final winterClose = (season.winterBreakRound + 3).clamp(winterOpen, 99);
    if (matchday >= winterOpen && matchday <= winterClose) {
      return TransferWindow(
        label: 'Winter window',
        isOpen: true,
        isDeadlineDay: matchday >= winterClose,
        closesAtMatchday: winterClose,
      );
    }

    const summerClose = 3;
    if (matchday <= summerClose) {
      return TransferWindow(
        label: 'Summer window',
        isOpen: true,
        isDeadlineDay: matchday >= summerClose,
        closesAtMatchday: summerClose,
      );
    }
    return _closed;
  }

  /// Matchdays until the window shuts (0 on deadline day).
  int daysLeft(SeasonState season) =>
      isOpen ? (closesAtMatchday - season.currentMatchday).clamp(0, 99) : 0;

  String banner(SeasonState season) {
    if (!isOpen) return 'Window closed · only free agents can sign';
    if (isDeadlineDay) return 'DEADLINE DAY · window shuts after this matchday';
    final left = daysLeft(season);
    return '$label · ${left == 1 ? '1 matchday' : '$left matchdays'} left';
  }
}

/// Where a deal currently stands.
enum DealStage {
  /// The two clubs are still haggling over the fee.
  bidding,

  /// A fee is agreed; personal terms are next.
  feeAgreed,

  /// A signing has been completed (kept briefly for the news feed).
  completed,

  /// The selling club ended talks, or the manager walked away.
  collapsed,

  /// A rival club signed the player while the manager stalled.
  hijacked,
}

enum BidOutcome { accepted, countered, rejected, collapsed }

/// One club-to-club negotiation over a single player.
///
/// `round` counts bids already made (0 before the first), `patience` is the
/// selling club's remaining tolerance, and [reservationPrice] is the lowest fee
/// they will take without collapsing — the ask is public, the reservation is
/// not.
class TransferNegotiation {
  const TransferNegotiation({
    required this.playerId,
    required this.playerName,
    required this.sellerClub,
    required this.askingPrice,
    required this.reservationPrice,
    required this.stage,
    required this.round,
    required this.patience,
    required this.lastOffer,
    required this.counterOffer,
    required this.startedMatchday,
    required this.rivalDeadlineMatchday,
    required this.wageDemand,
    required this.requiredReputation,
    required this.message,
    this.rivalClub,
    this.agreedFee,
    this.agreedWage,
    this.agreedBonus,
    this.agreedYears,
    this.agreedRole,
  });

  final int playerId;
  final String playerName;
  final String sellerClub;
  final int askingPrice;
  final int reservationPrice;
  final DealStage stage;
  final int round;
  final int patience;
  final int lastOffer;
  final int counterOffer;
  final int startedMatchday;
  final int rivalDeadlineMatchday;
  final int wageDemand;
  final int requiredReputation;
  final String message;
  final String? rivalClub;
  final int? agreedFee;
  final int? agreedWage;
  final int? agreedBonus;
  final int? agreedYears;
  final String? agreedRole;

  bool get isActive =>
      stage == DealStage.bidding || stage == DealStage.feeAgreed;

  /// True when the manager has to answer something.
  bool get needsAction =>
      isActive &&
      (counterOffer > 0 || (rivalClub != null && rivalDeadlineMatchday >= 0));

  TransferNegotiation copyWith({
    DealStage? stage,
    int? round,
    int? patience,
    int? lastOffer,
    int? counterOffer,
    int? rivalDeadlineMatchday,
    int? wageDemand,
    String? message,
    String? rivalClub,
    int? agreedFee,
    int? agreedWage,
    int? agreedBonus,
    int? agreedYears,
    String? agreedRole,
    bool clearCounter = false,
  }) {
    return TransferNegotiation(
      playerId: playerId,
      playerName: playerName,
      sellerClub: sellerClub,
      askingPrice: askingPrice,
      reservationPrice: reservationPrice,
      stage: stage ?? this.stage,
      round: round ?? this.round,
      patience: patience ?? this.patience,
      lastOffer: lastOffer ?? this.lastOffer,
      counterOffer: clearCounter ? 0 : (counterOffer ?? this.counterOffer),
      startedMatchday: startedMatchday,
      rivalDeadlineMatchday:
          rivalDeadlineMatchday ?? this.rivalDeadlineMatchday,
      wageDemand: wageDemand ?? this.wageDemand,
      requiredReputation: requiredReputation,
      message: message ?? this.message,
      rivalClub: rivalClub ?? this.rivalClub,
      agreedFee: agreedFee ?? this.agreedFee,
      agreedWage: agreedWage ?? this.agreedWage,
      agreedBonus: agreedBonus ?? this.agreedBonus,
      agreedYears: agreedYears ?? this.agreedYears,
      agreedRole: agreedRole ?? this.agreedRole,
    );
  }

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'sellerClub': sellerClub,
        'askingPrice': askingPrice,
        'reservationPrice': reservationPrice,
        'stage': stage.name,
        'round': round,
        'patience': patience,
        'lastOffer': lastOffer,
        'counterOffer': counterOffer,
        'startedMatchday': startedMatchday,
        'rivalDeadlineMatchday': rivalDeadlineMatchday,
        'wageDemand': wageDemand,
        'requiredReputation': requiredReputation,
        'message': message,
        'rivalClub': rivalClub,
        'agreedFee': agreedFee,
        'agreedWage': agreedWage,
        'agreedBonus': agreedBonus,
        'agreedYears': agreedYears,
        'agreedRole': agreedRole,
      };

  factory TransferNegotiation.fromJson(Map<String, dynamic> json) {
    final stageName = json['stage'] as String? ?? DealStage.bidding.name;
    final stage = DealStage.values.firstWhere(
      (s) => s.name == stageName,
      orElse: () => DealStage.bidding,
    );
    return TransferNegotiation(
      playerId: (json['playerId'] as num?)?.toInt() ?? 0,
      playerName: json['playerName'] as String? ?? 'Unknown',
      sellerClub: json['sellerClub'] as String? ?? '',
      askingPrice: (json['askingPrice'] as num?)?.toInt() ?? 0,
      reservationPrice: (json['reservationPrice'] as num?)?.toInt() ?? 0,
      stage: stage,
      round: (json['round'] as num?)?.toInt() ?? 0,
      patience: (json['patience'] as num?)?.toInt() ?? 3,
      lastOffer: (json['lastOffer'] as num?)?.toInt() ?? 0,
      counterOffer: (json['counterOffer'] as num?)?.toInt() ?? 0,
      startedMatchday: (json['startedMatchday'] as num?)?.toInt() ?? 0,
      rivalDeadlineMatchday:
          (json['rivalDeadlineMatchday'] as num?)?.toInt() ?? -1,
      wageDemand: (json['wageDemand'] as num?)?.toInt() ?? 0,
      requiredReputation:
          (json['requiredReputation'] as num?)?.toInt() ?? 50,
      message: json['message'] as String? ?? '',
      rivalClub: json['rivalClub'] as String?,
      agreedFee: (json['agreedFee'] as num?)?.toInt(),
      agreedWage: (json['agreedWage'] as num?)?.toInt(),
      agreedBonus: (json['agreedBonus'] as num?)?.toInt(),
      agreedYears: (json['agreedYears'] as num?)?.toInt(),
      agreedRole: json['agreedRole'] as String?,
    );
  }

  /// Rebuilds a live negotiation from the old "offers" list, so a save made
  /// before negotiations existed does not lose the manager's bid.
  factory TransferNegotiation.fromLegacyOffer(Map<String, dynamic> offer) {
    final fee = (offer['fee'] as num?)?.toInt() ?? 0;
    final asking = (offer['askingFee'] as num?)?.toInt() ?? (fee * 1.2).round();
    final price = asking <= 0 ? fee : asking;
    return TransferNegotiation(
      playerId: (offer['playerId'] as num?)?.toInt() ?? 0,
      playerName: offer['playerName'] as String? ?? 'Unknown',
      sellerClub: offer['club'] as String? ?? '',
      askingPrice: price,
      reservationPrice: (price * 0.82).round(),
      stage: DealStage.bidding,
      round: 1,
      patience: 2,
      lastOffer: fee,
      counterOffer: 0,
      startedMatchday: 0,
      rivalDeadlineMatchday: -1,
      wageDemand: 0,
      requiredReputation: 50,
      message: 'Resumed from an earlier bid of €$fee.',
    );
  }
}

/// An offer from another club for one of the manager's players.
class IncomingBid {
  const IncomingBid({
    required this.playerId,
    required this.playerName,
    required this.club,
    required this.fee,
    required this.matchday,
  });

  final int playerId;
  final String playerName;
  final String club;
  final int fee;
  final int matchday;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'club': club,
        'fee': fee,
        'matchday': matchday,
      };

  factory IncomingBid.fromJson(Map<String, dynamic> json) => IncomingBid(
        playerId: (json['playerId'] as num?)?.toInt() ?? 0,
        playerName: json['playerName'] as String? ?? 'Unknown',
        club: json['club'] as String? ?? '',
        fee: (json['fee'] as num?)?.toInt() ?? 0,
        matchday: (json['matchday'] as num?)?.toInt() ?? 0,
      );
}

/// One line in the transfer news feed.
class TransferNewsItem {
  const TransferNewsItem({
    required this.type,
    required this.title,
    required this.matchday,
    this.body = '',
  });

  final String type;
  final String title;
  final String body;
  final int matchday;

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'body': body,
        'matchday': matchday,
      };

  factory TransferNewsItem.fromJson(Map<String, dynamic> json) =>
      TransferNewsItem(
        type: json['type'] as String? ?? 'news',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        matchday: (json['matchday'] as num?)?.toInt() ?? 0,
      );
}

/// Everything the transfer desk owns, persisted inside the career blob.
class TransferDesk {
  TransferDesk({
    List<TransferNegotiation>? negotiations,
    List<IncomingBid>? incomingBids,
    List<TransferNewsItem>? news,
  })  : negotiations = negotiations ?? [],
        incomingBids = incomingBids ?? [],
        news = news ?? [];

  final List<TransferNegotiation> negotiations;
  final List<IncomingBid> incomingBids;
  final List<TransferNewsItem> news;

  /// Bumped by every mutation so the (expensive) market listing index can be
  /// cached without going stale after a signing or a rival move.
  int revision = 0;

  TransferNegotiation? forPlayer(int playerId) {
    for (final n in negotiations) {
      if (n.playerId == playerId) return n;
    }
    return null;
  }

  void replace(TransferNegotiation negotiation) {
    final index = negotiations.indexWhere(
      (n) => n.playerId == negotiation.playerId,
    );
    if (index < 0) {
      negotiations.add(negotiation);
    } else {
      negotiations[index] = negotiation;
    }
    touch();
  }

  void addNews(TransferNewsItem item) {
    news.insert(0, item);
    if (news.length > 40) news.removeRange(40, news.length);
    touch();
  }

  void touch() => revision++;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'negotiations': [for (final n in negotiations) n.toJson()],
        'incomingBids': [for (final b in incomingBids) b.toJson()],
        'news': [for (final item in news) item.toJson()],
      };

  factory TransferDesk.fromJson(Map<String, dynamic> json) {
    return TransferDesk(
      negotiations: [
        for (final n in (json['negotiations'] as List? ?? const []))
          if (n is Map)
            TransferNegotiation.fromJson(Map<String, dynamic>.from(n)),
      ],
      incomingBids: [
        for (final b in (json['incomingBids'] as List? ?? const []))
          if (b is Map) IncomingBid.fromJson(Map<String, dynamic>.from(b)),
      ],
      news: [
        for (final item in (json['news'] as List? ?? const []))
          if (item is Map)
            TransferNewsItem.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  factory TransferDesk.fromLegacyOffers(List<Map<String, dynamic>> offers) {
    return TransferDesk(
      negotiations: [
        for (final offer in offers) TransferNegotiation.fromLegacyOffer(offer),
      ],
    );
  }
}

/// One row of the precomputed market index.
class MarketListing {
  const MarketListing({
    required this.player,
    required this.value,
    required this.askingPrice,
    required this.weeklyWage,
    required this.freeAgent,
    this.seller,
    this.rivalClub,
  });

  final Player player;
  final Team? seller;
  final int value;
  final int askingPrice;
  final double weeklyWage;
  final bool freeAgent;
  final String? rivalClub;

  int? get contractYear => player.contractExpiry?.year;
}
