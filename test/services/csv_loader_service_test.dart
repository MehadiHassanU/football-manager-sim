import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/services/csv_loader_service.dart';

void main() {
  group('CsvLoaderService', () {
    test('loadFromAsset returns false for missing asset', () async {
      final service = CsvLoaderService();
      final result = await service.loadFromAsset('nonexistent.csv');
      expect(result, isFalse);
    });

    test('players list is empty initially', () {
      final service = CsvLoaderService();
      expect(service.players, isEmpty);
      expect(service.playersById, isEmpty);
      expect(service.teams, isEmpty);
    });
  });
}