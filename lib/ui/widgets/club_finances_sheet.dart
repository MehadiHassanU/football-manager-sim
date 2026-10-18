import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/game_constants.dart';
import '../../core/models/sponsorship.dart';
import '../../core/services/financial_service.dart';
import '../../core/services/sponsorship_service.dart';
import '../../providers/career_session_provider.dart';

/// Opens the club's books: cash, what a matchday earns and the kit deals that
/// produce it.
///
/// The Home screen only had one number and no explanation of where the next
/// one comes from. This is the answer: every source of income, the wage bill,
/// and what a home week is actually worth compared to an away week.
void showClubFinancesSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _ClubFinancesSheet(controller: scrollController),
    ),
  );
}

class _ClubFinancesSheet extends ConsumerWidget {
  const _ClubFinancesSheet({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final team = session.team;
    final season = session.season;
    final finance = FinancialService();
    final wages = finance.calculateWageBill(team) + team.loanedOutWages;
    final broadcast = finance.broadcastPerMatch(team.reputation);
    final kits = SponsorshipService()
        .weeklyIncome(session.sponsorships, season.currentYear);
    final gate = finance.estimateGateReceipts(team);
    final homeNet = gate + broadcast + kits - wages;
    final awayNet = broadcast + kits - wages;
    final projected = projectedSeasonRevenue(session);
    final rounds = season.rounds.length;
    final seasonWages = wages * rounds;
    final position =
        season.records.isEmpty ? 10 : season.positionOf(team.id);
    final prize = finance.meritPrize(
        team.reputation, position, season.records.length);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text('Club finances', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(team.name, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Cash',
                value: _euro(team.budget.toDouble()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Transfer budget',
                value: _euro(team.transferBudget),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Every matchday', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        _MoneyRow(
          label: 'Gate receipts',
          detail: 'Home games only',
          value: gate,
        ),
        _MoneyRow(
          label: 'Broadcast money',
          detail: 'Every match, home or away',
          value: broadcast,
        ),
        _MoneyRow(
          label: 'Kit instalments',
          detail: 'Every week',
          value: kits,
        ),
        _MoneyRow(
          label: 'Wages',
          detail: 'Every week',
          value: -wages,
        ),
        const Divider(height: 20),
        _MoneyRow(
          label: 'Home match',
          detail: 'Gate + broadcast + kit − wages',
          value: homeNet,
          emphasise: true,
        ),
        _MoneyRow(
          label: 'Away match',
          detail: 'Broadcast + kit − wages',
          value: awayNet,
          emphasise: true,
        ),
        const SizedBox(height: 20),
        Text('Kit deals', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        if (session.sponsorships.isEmpty)
          Text('No deals signed.', style: theme.textTheme.bodySmall)
        else
          for (final deal in session.sponsorships)
            _SponsorTile(deal: deal, year: season.currentYear),
        const SizedBox(height: 20),
        Text('Season outlook', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        _MoneyRow(
          label: 'Projected revenue',
          detail: 'Banked plus what is still to come',
          value: projected,
        ),
        if (rounds > 0 && projected > 0)
          _RatioRow(
            label: 'Squad cost',
            ratio: seasonWages / projected,
            limit: ffpWageRatioLimit,
          ),
        _MoneyRow(
          label: 'Merit prize from ${_ordinal(position)}',
          detail: 'If the table finished today',
          value: prize,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.detail,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String detail;
  final double value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = value >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: emphasise
                      ? theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)
                      : theme.textTheme.bodyMedium,
                ),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${positive && emphasise ? '+' : ''}${_euro(value)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasise ? FontWeight.w600 : null,
              color: emphasise
                  ? (positive
                      ? Colors.green.shade700
                      : theme.colorScheme.error)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatioRow extends StatelessWidget {
  const _RatioRow({
    required this.label,
    required this.ratio,
    required this.limit,
  });

  final String label;
  final double ratio;
  final double limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = ratio > limit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  'Wages as a share of that revenue · board guide '
                  '${(limit * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(ratio * 100).round()}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: over ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SponsorTile extends StatelessWidget {
  const _SponsorTile({required this.deal, required this.year});

  final Sponsorship deal;
  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = deal.yearsRemaining(year);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(_iconFor(deal.slot), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.brand, style: theme.textTheme.bodyMedium),
                Text(
                  '${deal.slot.label} · '
                  '${remaining == 1 ? 'final season' : '$remaining seasons left'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_euro(deal.annualValue)} a year',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SponsorSlot slot) => switch (slot) {
        SponsorSlot.front => Icons.checkroom,
        SponsorSlot.back => Icons.article_outlined,
        SponsorSlot.sleeve => Icons.dry_cleaning,
      };
}

/// '1st', '2nd', '3rd', '11th'.
String _ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Compact euro figure, in the same dialect the player sheet uses.
String _euro(double amount) {
  final abs = amount.abs();
  if (abs >= 1000000000) return '€${(amount / 1000000000).toStringAsFixed(1)}B';
  if (abs >= 1000000) return '€${(amount / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) return '€${(amount / 1000).toStringAsFixed(0)}K';
  return '€${amount.toStringAsFixed(0)}';
}
