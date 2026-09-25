/// Web/unsupported-platform implementation.
///
/// The stub never touches `dart:io` so web builds stay clean, and file based
/// CSV loading degrades to "unavailable" instead of failing at compile time.
Future<String?> readCsvFile(String filePath) async => null;
