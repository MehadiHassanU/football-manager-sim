import 'dart:io';

/// Desktop/mobile implementation backed by the real file system.
///
/// Returns the file contents, or `null` when the file is missing or unreadable
/// so callers can fall back gracefully.
Future<String?> readCsvFile(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}
