import 'dart:io';

/// Deletes a file if it exists (IO platforms only).
Future<void> deleteHiveFileIfExists(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
