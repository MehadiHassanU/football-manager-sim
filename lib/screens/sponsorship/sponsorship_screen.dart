import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/game_constants.dart';
import '../../core/models/sponsorship.dart';
import '../../providers/ad_provider.dart';
import '../../providers/career_session_provider.dart';
import '../../ui/ui.dart';

/// The club's commercial desk: what the shirt is worth, who is paying, and who
/// is still bidding for the slots that are open.
///
/// This screen exists because the deals used to be invisible: they were signed
/// automatically at career start and only appeared as three lines inside the
/// Finances sheet. Here the manager sees the money, chooses the brand, and can
/// reroll the shortlist by watching a rewarded ad — the one place in the game
/// where an ad is offered.
class SponsorshipScreen extends ConsumerStatefulWidget {
  const SponsorshipScreen({super.key});

  @override
  ConsumerState<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends ConsumerState<SponsorshipScreen> {
  /// The slot whose ad is loading/showing, so its button can show progress and
  /// a second tap cannot start a second ad.
  SponsorSlot? _rerolling;

  Future<void> _watchAndReroll(SponsorSlot slot) async {
    if (_rerolling != null) return;
    setState(() => _rerolling = slot);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(adServiceProvider)
        .showRewarded(placement: 'sponsorship_reroll');
    if (!mounted) return;
    setState(() => _rerolling = null);
    switch (result) {
      case AdReward.earned:
        rerollSponsorshipOffers(ref, slot);
        messenger.showSnackBar(const SnackBar(
          content: Text('New offers on the table.'),
        ));
      case AdReward.dismissed:
        messenger.showSnackBar(const SnackBar(
          content: Text('Watch the video to the end to unlock fresh offers.'),
        ));
      case AdReward.unavailable:
        messenger.showSnackBar(const SnackBar(
          content: Text('No ad available right now — try again shortly.'),
        ));
    }
  }

  void _sign(SponsorshipOffer offer) {
    final signed = signSponsorshipOffer(ref, offer);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(signed
          ? '${offer.brand} signs on the ${offer.slot.label.toLowerCase()}.'
          : 'That slot has already been sold.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sponsorships')),
        body: const EmptyState(
          icon: Icons.handshake_outlined,
          title: 'No active career',
          message: 'Start a career to sell the club\'s kit.',
        ),
      );
    }

    final year = session.season.currentYear;
    final active = <SponsorSlot, Sponsorship>{
      for (final deal in session.sponsorships)
        if (deal.isActiveIn(year)) deal.slot: deal,
    };
    final total = active.values.fold<double>(0, (sum, d) => sum + d.annualValue);
    final offers = session.sponsorshipOffers;
    final openOffers = [
      for (final slot in SponsorSlot.values)
        if (!active.containsKey(slot))
          for (final offer in offers)
            if (offer.slot == slot) offer,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Sponsorships')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _IncomeSummary(
            total: total,
            sold: active.length,
            openOffers: openOffers.length,
          ),
          const SectionHeader(title: 'The shirt'),
          for (final slot in SponsorSlot.values) ...[
            if (active[slot] != null)
              _DealCard(deal: active[slot]!, year: year)
            else
              _OfferBoard(
                slot: slot,
                offers: [
                  for (final offer in offers)
                    if (offer.slot == slot) offer,
                ],
                rerolling: _rerolling == slot,
                // Keep every button dead while any ad is in flight: two ads
                // at once is never what the manager asked for.
                adBusy: _rerolling != null,
                onSign: _sign,
                onReroll: () => _watchAndReroll(slot),
              ),
            const SizedBox(height: 12),
          ],
          const _AdNote(),
        ],
      ),
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary({
    required this.total,
    required this.sold,
    required this.openOffers,
  });

  final double total;
  final int sold;
  final int openOffers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'COMMERCIAL INCOME',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_money(total)} a year',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${_money(total / kWeeksPerYear)} lands with every matchday. '
              '$sold of ${SponsorSlot.values.length} slots sold.',
              style: theme.textTheme.bodySmall,
            ),
            if (openOffers > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$openOffers offer${openOffers == 1 ? '' : 's'} on the table. '
                'The board signs the best one left when the season kicks off, '
                'so nothing stays unsold.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.year});

  final Sponsorship deal;
  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = deal.yearsRemaining(year);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(deal.slot), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(deal.brand,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                _Stars(count: deal.prestige),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${deal.slot.label} · ${_money(deal.annualValue)} a year',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Runs to ${deal.endYear} · $remaining season'
              '${remaining == 1 ? '' : 's'} left',
              style: theme.textTheme.bodySmall,
            ),
            if (deal.clause != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Bonus: ${_clauseText(deal.clause!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferBoard extends StatelessWidget {
  const _OfferBoard({
    required this.slot,
    required this.offers,
    required this.rerolling,
    required this.adBusy,
    required this.onSign,
    required this.onReroll,
  });

  final SponsorSlot slot;
  final List<SponsorshipOffer> offers;
  final bool rerolling;
  final bool adBusy;
  final void Function(SponsorshipOffer offer) onSign;
  final VoidCallback onReroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(slot), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slot.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  offers.isEmpty
                      ? 'No offers'
                      : '${offers.length} offer${offers.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (offers.isEmpty)
              Text(
                'The shortlist has run dry. Watch a video to bring the '
                'market back.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final offer in offers)
                _OfferTile(offer: offer, onSign: () => onSign(offer)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: adBusy ? null : onReroll,
                icon: rerolling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ondemand_video_outlined, size: 18),
                label: Text(rerolling
                    ? 'Loading video…'
                    : 'Watch an ad for fresh offers'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.onSign});

  final SponsorshipOffer offer;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.brand,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _Stars(count: offer.prestige),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_money(offer.annualValue)} a year · ${offer.durationYears} '
            'season${offer.durationYears == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Criteria: ${offer.requirement}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (offer.clause != null) ...[
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.emoji_events_outlined,
                    size: 14, color: theme.colorScheme.tertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Bonus: ${_clauseText(offer.clause!)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onSign,
              child: const Text('Sign'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= count ? Icons.star : Icons.star_border,
            size: 14,
            color: theme.colorScheme.tertiary.withValues(
              alpha: i <= count ? 1 : 0.35,
            ),
          ),
      ],
    );
  }
}

class _AdNote extends StatelessWidget {
  const _AdNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline,
            size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Rerolls are free. Watching a short rewarded video is the only '
            'way to refresh the shortlist — there are no banners or pop-ups '
            'anywhere in the game.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

IconData _iconFor(SponsorSlot slot) => switch (slot) {
      SponsorSlot.front => Icons.checkroom,
      SponsorSlot.back => Icons.article_outlined,
      SponsorSlot.sleeve => Icons.dry_cleaning,
    };

String _clauseText(SponsorshipClause clause) => switch (clause.kind) {
      ClauseKind.leagueTop =>
        '${_money(clause.amount)} for a top-${clause.threshold} finish',
      ClauseKind.cupWin => '${_money(clause.amount)} for winning the cup',
      ClauseKind.goals => '${_money(clause.amount)} per league goal',
    };

String _money(num amount) {
  if (amount >= 1000000) {
    final millions = amount / 1000000;
    final text = millions >= 10
        ? millions.toStringAsFixed(1)
        : millions.toStringAsFixed(2);
    return '€${text.replaceFirst(RegExp(r'\.?0+$'), '')}M';
  }
  if (amount >= 1000) return '€${(amount / 1000).round()}k';
  return '€${amount.round()}';
}
