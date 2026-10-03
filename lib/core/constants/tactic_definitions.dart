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
enum Formation { fourFourTwo, fourThreeThree, threeFiveTwo, fourTwoThreeOne }

