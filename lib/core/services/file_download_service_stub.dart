import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

class FileDownloadService {
  static Future<void> downloadFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$fileName';
      final file = io.File(path);
      await file.writeAsBytes(bytes);
    } catch (e) {
    }
  }
}
