/// Guards against bad map-match / teleport official km inflating trip totals.
class DistanceSanity {
  /// Above this average speed, official km is treated as garbage.
  static const double maxAvgSpeedKmh = 120;

  /// Official may exceed GPS a bit (road matching), but not by this ratio.
  static const double maxOfficialVsGpsRatio = 2.5;

  static const double minAbsDeltaKm = 3;

  /// Hard ceiling for a single leg in this product (field sales).
  static const double hardMaxLegKm = 800;

  static bool isOfficialAbsurd({
    required double officialKm,
    double? gpsKm,
    double? plannedKm,
    int? travelMinutes,
  }) {
    if (officialKm <= 0) return false;
    if (officialKm > hardMaxLegKm) return true;

    if (travelMinutes != null && travelMinutes > 0) {
      final hours = travelMinutes / 60.0;
      if (hours > 0 && officialKm / hours > maxAvgSpeedKmh) return true;
    }

    if (gpsKm != null && gpsKm > 0.15) {
      if (officialKm > gpsKm * maxOfficialVsGpsRatio &&
          officialKm - gpsKm > minAbsDeltaKm) {
        return true;
      }
    }

    if (plannedKm != null && plannedKm > 0.15) {
      if (officialKm > plannedKm * 4 && officialKm - plannedKm > 5) {
        return true;
      }
    }

    return false;
  }

  /// Prefer sane official, else GPS / planned / punch distance.
  static double? selectLegKm({
    double? officialKm,
    double? provisionalKm,
    double? trackKm,
    double? plannedKm,
    double? punchKm,
    int? travelMinutes,
  }) {
    final gps = provisionalKm ?? trackKm;
    if (officialKm != null &&
        officialKm > 0 &&
        !isOfficialAbsurd(
          officialKm: officialKm,
          gpsKm: gps,
          plannedKm: plannedKm,
          travelMinutes: travelMinutes,
        )) {
      return officialKm;
    }
    if (gps != null && gps > 0) return gps;
    if (plannedKm != null && plannedKm > 0) return plannedKm;
    if (punchKm != null && punchKm > 0) return punchKm;
    return null;
  }
}
