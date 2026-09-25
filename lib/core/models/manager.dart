
class Manager {
  String name;
  int age;
  String nationality;
  String? teamId;
  int legacyScore;
  List<String> achievements;
  double sackablePercent;
  double fanTrust;
  Rival? rival;

  Manager({
    required this.name,
    required this.age,
    required this.nationality,
    this.teamId,
    this.legacyScore = 0,
    List<String>? achievements,
    double? sackablePercent,
    double? fanTrust,
    this.rival,
  })  : achievements = achievements ?? [],
        sackablePercent = sackablePercent ?? 5.0,
        fanTrust = fanTrust ?? 75.0;
}

class Rival {
  final String rivalName;
  final String rivalTeam;
  int rivalryScore;
  int yourWins;
  int rivalWins;

  Rival({
    required this.rivalName,
    required this.rivalTeam,
    this.rivalryScore = 0,
    this.yourWins = 0,
    this.rivalWins = 0,
  });
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String category;
  bool completed;
  final String? icon;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.completed = false,
    this.icon,
  });
}

class DramaEvent {
  final String id;
  final String title;
  final String description;
  final DateTime timestamp;
  final String type; // 'transfer_request', 'rumor', 'media', 'rivalry'
  final Map<String, dynamic> data;

  DramaEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.type,
    required this.data,
  });
}

class DramaMeter {
  double intensity;
  List<DramaEvent> events;

  DramaMeter({this.intensity = 0.0, List<DramaEvent>? events})
      : events = events ?? [];

  void addEvent(DramaEvent event) {
    events.add(event);
    switch (event.type) {
      case 'transfer_request':
        intensity = (intensity + 15).clamp(0, 100);
        break;
      case 'rumor':
        intensity = (intensity + 5).clamp(0, 100);
        break;
      case 'media':
        intensity = (intensity + 8).clamp(0, 100);
        break;
      case 'rivalry':
        intensity = (intensity + 10).clamp(0, 100);
        break;
    }
  }
}