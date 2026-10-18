# Touchline Legend

A hyper-realistic football manager simulation built in Flutter with Riverpod
state management, Hive local storage, and CSV-based player data.

## Features

- **Player Management** — 80+ attributes per player, injuries with medical
  types and expected return dates, contracts, wages and transfer value
- **Match Simulation** — Auto-simulated matches with momentum, cards,
  injuries and a live event feed; step into the dressing room at half-time
- **Training & Development** — Training focuses, weekly growth towards a
  potential ceiling, ageing veterans on the way down, and an academy that
  keeps producing
- **A Living League** — Rival clubs buy, sell and develop season after
  season, so the squads you meet again are never quite the same
- **Cups & Honours** — A national knockout cup merged into the league
  calendar, with a trophy cabinet to show for it
- **Financial System** — FFP enforcement, transfer budgets, wage ceilings
  and gate receipts
- **Board & Expectations** — Board patience, sack risk, wage-budget
  sanctions and a verdict on every run of results
- **Season System** — A matchday-driven calendar with a winter break and
  promotion and relegation between divisions

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Flutter (Material 3) |
| State Management | Flutter Riverpod |
| Routing | go_router |
| Local Storage | Hive + path_provider |
| Data Import | CSV parsing (EAFC26 player database) on a worker isolate |
| Serialization | Hive type adapters + json_annotation |
| Utilities | uuid, meta |

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
│   ├── models/                 # Player, Team, Match, Season, Tactics, Transfer, YouthPlayer, Cup
│   ├── services/               # CSV loader, match simulator, development, injuries, cups, finance, save
│   ├── adapters/               # Hive type adapters for serialization
│   ├── constants/              # Game constants, position/formation/tactic/league definitions
│   └── utils/                  # CSV parsing and math helpers
├── providers/                  # Riverpod providers (career session, player database, match, settings)
├── screens/
│   ├── startup/                # Splash/loading screen
│   ├── main_menu/              # Junction to every game mode
│   ├── new_career/             # League and club selection
│   ├── career/                 # Career dashboard (fixture, board, league position)
│   ├── shell/                  # Bottom-navigation shell around the main tabs
│   ├── match/                  # Live match screen with simulation
│   ├── team_management/        # Squad, tactics and youth academy
│   ├── transfer_market/        # Transfer hub: market, live talks, news
│   ├── league_table/           # Standings and fixtures
│   ├── settings/               # Difficulty, commentary, audio, sack rules
│   └── privacy/                # Privacy policy screen
└── data/
    └── csv/                    # Player CSV database (EAFC26-Men.csv)

test/
├── core/                       # Flow tests (career, cups, development, injuries, rollover)
├── models/                     # Model unit tests (Player, Manager, Season, Team)
├── services/                   # Service tests (CSV, finance, transfers, development, injuries, save)
└── screens/                    # Screen widget tests
```

## Key Models

### Player
- Identity: name, id, nationality, age
- Core Stats: OVR, PAC, SHO, PAS, DRI, DEF, PHY
- Sub-Stats: 27 attributes covering finishing, vision, defense, physicality, GK skills
- Meta: preferred foot, weak foot quality, skill moves, height, weight, traits
- Runtime: fitness, form, morale, match rating, games and minutes, injury (type
  and expected return date), contract, wages, transfer value

### Manager
- Career info: name, age, nationality
- Performance: legacy score, achievements, fan trust, sackable percent
- Rival System: rival manager tracking with rivalry score and win history
- Drama Meter: event-driven intensity system for key story moments

### Season
- Matchday-driven calendar (August – May) with a winter break and the cup
  rounds merged into the schedule
- League records, form and league position, with rival fixtures simulated
  around the manager's own matches

### Cup
- A knockout bracket seeded per league per year, anchored into the calendar
  between league matchdays; cup results never touch the league table

## Screens

| Screen | Description |
|--------|-------------|
| Startup | Loading/splash screen with initialization |
| Main Menu | Navigation hub, new career and continue |
| New Career | League and club selection with a pre-commit summary |
| Home (Career Dashboard) | Fixture, board objective, league position, news |
| Match | Live simulated match with real-time commentary and events |
| Team Management | Squad, tactics and youth academy |
| Transfer Hub | Market, live talks, my players and the news feed |
| League Table | Standings and fixtures |
| Settings | Difficulty, commentary, audio, match speed, sack rules |
| Privacy | Offline-storage privacy policy |

## Contributing

Contributions are welcome! Please open an issue first to discuss changes.

## License

MIT License
