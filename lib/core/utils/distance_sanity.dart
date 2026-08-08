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

  /// Prefer GPS / provisional when a track exists so list cards, detail, and
  /// allowance stay on one number. Nest "official" is only used when it matches
  /// GPS closely or when no GPS km exists yet.
  static double? selectLegKm({
    double? officialKm,
    double? provisionalKm,
    double? trackKm,
    double? plannedKm,
    double? punchKm,
    int? travelMinutes,
  }) {
    final gps = provisionalKm ?? trackKm;
    if (gps != null && gps > 0.05) {
      if (officialKm != null &&
          officialKm > 0 &&
          !isOfficialAbsurd(
            officialKm: officialKm,
            gpsKm: gps,
            plannedKm: plannedKm,
            travelMinutes: travelMinutes,
          ) &&
          (officialKm - gps).abs() <= 0.15) {
        // Same distance for practical purposes — keep official label value.
        return officialKm;
      }
      return gps;
    }
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
    if (plannedKm != null && plannedKm > 0) return plannedKm;
    if (punchKm != null && punchKm > 0) return punchKm;
    return null;
  }

  /// Label for the value [selectLegKm] would return.
  static String selectLegKmLabel({
    double? officialKm,
    double? provisionalKm,
    double? trackKm,
    double? plannedKm,
    double? punchKm,
    int? travelMinutes,
  }) {
    final chosen = selectLegKm(
      officialKm: officialKm,
      provisionalKm: provisionalKm,
      trackKm: trackKm,
      plannedKm: plannedKm,
      punchKm: punchKm,
      travelMinutes: travelMinutes,
    );
    if (chosen == null || chosen <= 0) return 'Distance';
    final gps = provisionalKm ?? trackKm;
    if (officialKm != null &&
        officialKm > 0 &&
        (chosen - officialKm).abs() <= 0.02 &&
        !isOfficialAbsurd(
          officialKm: officialKm,
          gpsKm: gps,
          plannedKm: plannedKm,
          travelMinutes: travelMinutes,
        )) {
      return 'Official';
    }
    if (gps != null && gps > 0.05 && (chosen - gps).abs() <= 0.02) {
      return 'Approx (GPS)';
    }
    if (plannedKm != null &&
        plannedKm > 0 &&
        (chosen - plannedKm).abs() <= 0.02) {
      return 'Planned';
    }
    return 'Distance';
  }
}
