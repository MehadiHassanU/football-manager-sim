// Tactic definitions

enum PlayingStyle { attacking, balanced, defensive, possession, counterAttack }
enum PressingIntensity { highPress, mediumPress, lowBlock, false9Press }
enum Tempo { fast, normal, slow }
enum Width { narrow, normal, wide }
enum DefensiveLine { high, medium, low }
enum PossessionFocus { shortPassing, longBalls }

/// Formations a manager can pick.
///
/// This is not cosmetic: the chosen formation decides which positions the
/// starting-XI selector looks for, and it drives the pitch preview on the
/// tactics screen, so what the manager arranges is what starts.
///
/// The catalogue is ordered by back line — four, three, then five — and every
/// shape here has a layout in `kFormationLayouts`, so the dropdown can never
/// offer a formation the pitch cannot draw.
enum Formation {
  fourFourTwo('4-4-2'),
  fourFourOneOne('4-4-1-1'),
  fourFiveOne('4-5-1'),
  fourOneFourOne('4-1-4-1'),
  fourThreeThree('4-3-3'),
  fourTwoThreeOne('4-2-3-1'),
  fourThreeOneTwo('4-3-1-2'),
  fourTwoTwoTwo('4-2-2-2'),
  threeFourThree('3-4-3'),
  threeFiveTwo('3-5-2'),
  fiveThreeTwo('5-3-2'),
  fiveFourOne('5-4-1');

  const Formation(this.label);

  /// The manager-facing shape, e.g. '4-4-2'.
  final String label;
}

