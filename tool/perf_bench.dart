// Phase 0 performance benchmark: measures the startup CSV load pipeline.
//
// Run with: dart run tool/perf_bench.dart
//
// Gives a baseline to compare against when the parse is optimized / moved
// onto an isolate, so improvements are measured rather than guessed.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:csv/csv.dart';

void main() async {
  final path = 'lib/data/csv/EAFC26-Men.csv';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('CSV not found at $path (run from the repo root)');
    exitCode = 1;
    return;
  }

  print(
      'CSV size        : ${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB');

  // ---- Stage 1: read text (3 runs, best kept) ----------------------------
  var readMs = 1 << 30;
  String csvString = '';
  for (var i = 0; i < 3; i++) {
    final w = Stopwatch()..start();
    csvString = await file.readAsString();
    w.stop();
    readMs = readMs < w.elapsedMilliseconds ? readMs : w.elapsedMilliseconds;
  }
  print('Stage 1 read    : $readMs ms');

  // ---- Stage 2: CsvToListConverter (3 runs) ------------------------------
  List<List<dynamic>> rows = const [];
  var convertMs = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final w = Stopwatch()..start();
    rows = const CsvToListConverter().convert(csvString);
    w.stop();
    convertMs =
        convertMs < w.elapsedMilliseconds ? convertMs : w.elapsedMilliseconds;
  }
  print('Stage 2 convert : $convertMs ms (${rows.length - 1} data rows)');

  // ---- Stage 2b: converter WITHOUT number parsing ------------------------
  // The real parser stringifies every cell (getValue -> ?.toString()), so
  // number parsing may be wasted work. Empty-cell semantics differ (null vs
  // '') -- measured here first, used only if both safe and faster.
  List<List<dynamic>> stringRows = const [];
  var stringConvertMs = 1 << 30;
  var nullIdCount = 0;
  var emptyIdCount = 0;
  for (var i = 0; i < 3; i++) {
    final w = Stopwatch()..start();
    stringRows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(csvString);
    w.stop();
    stringConvertMs = stringConvertMs < w.elapsedMilliseconds
        ? stringConvertMs
        : w.elapsedMilliseconds;
  }
  for (var i = 1; i < stringRows.length; i++) {
    final r = stringRows[i];
    if (r.length >= 2) {
      if (r[1] == null) nullIdCount++;
      if (r[1] is String && (r[1] as String).isEmpty) emptyIdCount++;
      if (r[1] is int) emptyIdCount = -999999; // still parsing numbers?
    }
  }
  print('Stage 2b strings: $stringConvertMs ms '
      '(null-ID rows: $nullIdCount, empty-ID rows: $emptyIdCount)');

  // ---- Stage 3: header scan cost, current vs index-map -------------------
  final header = rows.first.map((v) => v.toString()).toList();

  var indexOfMs = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final w = Stopwatch()..start();
    var sink = 0;
    for (final key in _sampleKeys) {
      for (var r = 0; r < 1000; r++) {
        sink += header.indexOf(key);
      }
    }
    w.stop();
    if (sink < 0) print(sink); // keep the loop observable
    indexOfMs =
        indexOfMs < w.elapsedMilliseconds ? indexOfMs : w.elapsedMilliseconds;
  }
  print('Stage 3 indexOf : $indexOfMs ms '
      '(${_sampleKeys.length * 1000} lookups; x~16k rows => extrapolate)');

  final map = {for (var i = 0; i < header.length; i++) header[i]: i};
  var mapMs = 1 << 30;
  for (var i = 0; i < 3; i++) {
    final w = Stopwatch()..start();
    var sink = 0;
    for (final key in _sampleKeys) {
      for (var r = 0; r < 1000; r++) {
        sink += map[key] ?? -1;
      }
    }
    w.stop();
    if (sink < 0) print(sink);
    mapMs = mapMs < w.elapsedMilliseconds ? mapMs : w.elapsedMilliseconds;
  }
  print('Stage 3 map hit : $mapMs ms (same lookup volume)');
}

const List<String> _sampleKeys = [
  'Name', 'ID', 'Age', 'Nation', 'Team', 'League', 'Position', 'OVR', 'PAC',
  'SHO', 'PAS', 'DRI', 'DEF', 'PHY', 'Acceleration', 'Sprint Speed',
  'Finishing', 'Vision', 'Reactions', 'Standing Tackle', 'Height', 'Weight',
];
