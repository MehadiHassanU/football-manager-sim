// Position definitions and validation

const List<String> allPositions = [
  'GK',   // Goalkeeper
  'LB',   // Left Back
  'CB',   // Center Back
  'RB',   // Right Back
  'CDM',  // Central Defensive Midfielder
  'CM',   // Central Midfielder
  'CAM',  // Central Attacking Midfielder
  'LM',   // Left Midfielder
  'RM',   // Right Midfielder
  'LW',   // Left Winger
  'RW',   // Right Winger
  'ST',   // Striker
  'LCB',  // Left Center Back
  'RCB',  // Right Center Back
  'CWB',  // Center Wing Back
  'LM',   // Left Mid (alias)
];

// Position categories
const Map<String, String> positionCategory = {
  'GK': 'GK',
  'LB': 'DEF', 'CB': 'DEF', 'RB': 'DEF',
  'LCB': 'DEF', 'RCB': 'DEF', 'CWB': 'DEF',
  'CDM': 'MID', 'CM': 'MID', 'CAM': 'MID',
  'LM': 'MID', 'RM': 'MID',
  'LW': 'WING', 'RW': 'WING',
  'ST': 'FWD',
};

const Map<String, List<String>> primaryToAlternatives = {
  'GK': [],
  'CB': ['LB', 'RB'],
  'LB': ['CB'],
  'RB': ['CB'],
  'CDM': ['CM'],
  'CM': ['CDM', 'CAM'],
  'CAM': ['CM', 'ST'],
  'LW': ['LM'],
  'RW': ['RM'],
  'LM': ['LW', 'RM'],
  'RM': ['RW', 'LM'],
  'ST': ['CAM'],
  'LCB': ['CB', 'LB'],
  'RCB': ['CB', 'RB'],
  'CWB': ['LB', 'RB', 'CM'],
};

// Stat modifiers when playing out of position
// Format: '{primary}_{alternative}': {stat: modifier}
const Map<String, Map<String, int>> positionStatModifiers = {
  // CB playing LB/RB
  'CB_LB': {'pac': -2, 'def': 2, 'stamina': -1},
  'CB_RB': {'pac': -2, 'def': 2, 'stamina': -1},
  // LB/CB
  'LB_CB': {'pac': -3, 'def': 3, 'crossing': -2},
  'RB_CB': {'pac': -3, 'def': 3, 'crossing': -2},
  // CDM ↔ CM
  'CDM_CM': {'def': -3, 'sta': 0, 'pass': 2, 'vis': 2},
  'CM_CDM': {'def': 3, 'sta': 0, 'pass': -2, 'vis': -2},
  // CAM ↔ ST
  'CAM_ST': {'def': -5, 'pass': 0, 'sho': 2, 'vis': -2},
  'ST_CAM': {'def': 5, 'pass': 2, 'sho': -2, 'vis': 2},
  // LW ↔ LM
  'LW_LM': {'dri': 1, 'cross': 2, 'pass': 2, 'pace': -1},
  'LM_LW': {'dri': 1, 'cross': 2, 'pass': 2, 'pace': -1},
  // RW ↔ RM
  'RW_RM': {'dri': 1, 'cross': 2, 'pass': 2, 'pace': -1},
  'RM_RW': {'dri': 1, 'cross': 2, 'pass': 2, 'pace': -1},
  // GK playing outfield (severe penalty)
  'GK_OUTFIELD': {
    'pac': -10, 'sho': -15, 'pas': -15, 'dri': -15,
    'def': -10, 'phy': -10, 'vis': -15,
  },
};

bool isValidPosition(String position) {
  return allPositions.contains(position);
}

bool canPlayPosition(String primaryPos, String targetPos) {
  if (primaryPos == targetPos) return true;
  final alternatives = primaryToAlternatives[primaryPos] ?? [];
  if (alternatives.contains(targetPos)) return true;
  // Check modifier key exists
  final key = '${primaryPos}_${targetPos}';
  if (positionStatModifiers.containsKey(key)) return true;
  if (positionStatModifiers.containsKey('GK_OUTFIELD') && targetPos == 'GK') return true;
  return false;
}

int getPositionModifier(String primaryPos, String targetPos, String stat) {
  if (primaryPos == targetPos) return 0;
  final key = '${primaryPos}_${targetPos}';
  final modifiers = positionStatModifiers[key];
  if (modifiers != null && modifiers.containsKey(stat)) {
    return modifiers[stat]!;
  }
  // Check GK_OUTFIELD
  if (targetPos == 'GK' && positionStatModifiers.containsKey('GK_OUTFIELD')) {
    final gkMods = positionStatModifiers['GK_OUTFIELD']!;
    if (gkMods.containsKey(stat)) return gkMods[stat]!;
  }
  return 0;
}

List<String> getValidPositions(String primaryPos) {
  return [primaryPos, ...(primaryToAlternatives[primaryPos] ?? [])];
}