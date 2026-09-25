# Football Manager Simulation

A hyper-realistic football manager simulation game built in Flutter with Riverpod state management, Hive local storage, and CSV-based player data.

## Features

- **Player Management** — Full stat tracking with 80+ attributes per player, injury/contract/wage systems, and transfer mechanics
- **Match Simulation** — Auto-simulated matches with momentum, drama, and key event tracking
- **Financial System** — FFP (Financial Fair Play) enforcement, transfer budgets, wage management, and gate receipts
- **Team Management** — Formation selection, tactic configuration, squad building, and youth academy integration
- **Career Mode** — Legacy tracking, achievements, fan trust, and manager sackability
- **Settings** — Configurable difficulty, commentary, audio, match speed, and sack rules
- **Season System** — Calendar-driven progression with month-by-month events and prize distributions

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Flutter (Material 3) |
| State Management | Flutter Riverpod |
| Routing | go_router |
| Local Storage | Hive + path_provider |
| Data Import | CSV parsing (EAFC26 player database) |
| Serialization | json_annotation / json_serializable |
| Animations | Rive, Shimmer |
| Charts | fl_chart |

## Getting Started

### Prerequisites
- Flutter SDK >= 3.2.0
- Dart >= 3.2.0

### Install dependencies
```bash
flutter pub get
```

### Run the app
```bash
flutter run
```

### Run tests
```bash
flutter test
```

## Project Structure

```
lib/
├── app.dart                    # App entry with router config & theme
├── main.dart                   # App initialization (Hive, window setup)
├── core/
│   ├── models/                 # Data models (Player, Manager, Team, Match, Season, Tactics, YouthPlayer)
│   ├── services/               # Business logic (CSV Loader, Financial, Save, Match Simulator)
│   ├── adapters/               # Hive type adapters for serialization
│   ├── constants/              # Game constants, position/formation/league/tactic definitions
│   └── utils/                  # Utilities (CSV parser, math helpers)
├── providers/                  # Riverpod providers (game, match, career, season, team, tactics, settings, academy)
├── screens/
│   ├── startup/                # Splash/loading screen
│   ├── main_menu/              # Main navigation hub
│   ├── career/                 # Career dashboard with stats & legacy
│   ├── match/                  # Live match screen with simulation
│   ├── team_management/        # Squad/formation/tactic management
│   └── settings/               # Game settings (difficulty, audio, commentary)
└── data/
    ├── csv/                    # Player CSV database (EAFC26-Men.csv)
    └── assets/                 # Images and sounds

test/
├── models/                     # Model unit tests (Player, Manager, Season, Team)
├── services/                   # Service tests (CSV Loader, Financial, Save)
└── screens/                    # Screen widget tests (Main Menu, Match)
```

## Key Models

### Player
- Identity: name, id, nationality, age
- Core Stats: OVR, PAC, SHO, PAS, DRI, DEF, PHY
- Sub-Stats: 27 attributes covering finishing, vision, defense, physicality, GK skills
- Meta: preferred foot, weak foot quality, skill moves, height, weight, traits
- Runtime: fitness, form, morale, match rating, injury status, contract, wages, transfer value

### Manager
- Career info: name, age, nationality
- Performance: legacy score, achievements, fan trust, sackable percent
- Rival System: rival manager tracking with rivalry score and win history
- Drama Meter: event-driven intensity system for key story moments

### Season
- Calendar-driven progression (August – May)
- Monthly events: matches, injuries, transfers, prizes
- Financial tracking: gate receipts, sponsorship, transfer budget

## Screens

| Screen | Description |
|--------|-------------|
| Startup | Loading/splash screen with initialization |
| Main Menu | Navigation to all game modes |
| Career Dashboard | Season progress, league table, match history, stats charts |
| Match | Live simulated match with real-time commentary and events |
| Team Management | Squad view, formation selection, tactic configuration, youth academy |
| Settings | Difficulty, commentary, audio, match speed, sack rules |

## Contributing

Contributions are welcome! Please open an issue first to discuss changes.

## License

MIT License