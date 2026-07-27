void main() {
  final rd = DateTime.parse("2026-06-25T10:00:00Z").toLocal();
  final s = DateTime(2026, 6, 1);
  final isBefore = DateTime(rd.year, rd.month, rd.day).isBefore(s);
  
  final e = DateTime(2026, 6, 30);
  final isAfter = DateTime(rd.year, rd.month, rd.day).isAfter(e);
}
