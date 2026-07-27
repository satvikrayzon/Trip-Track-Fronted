import 'dart:convert';
import 'package:web/web.dart' as web;

class FileDownloadService {
  static Future<void> downloadFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    final base64String = base64Encode(bytes);
    final anchor = web.HTMLAnchorElement()
      ..href = 'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64String'
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
}
