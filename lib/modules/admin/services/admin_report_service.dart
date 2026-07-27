import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/models/api_result.dart';
import '../../../../core/services/file_download_service.dart';
import '../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../../travel/data/models/travel_request_model.dart';
import '../../travel/data/models/travel_request_list_result.dart';

class AdminReportService {
  AdminReportService({required this.travelApi});

  final TravelRequestRemoteDataSource travelApi;

  Future<void> exportReport({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
  }) async {
    // 1. Fetch all requests
    final allRequests = <TravelRequestModel>[];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final res = await travelApi.listTravelRequests(page: page, limit: 50, mine: false);
      if (res is ApiSuccess<TravelRequestListResult>) {
        final items = res.data.items.map((m) => TravelRequestModel.fromMap(m)).toList();
        allRequests.addAll(items);
        if (items.length < 50 || !res.data.hasMore) {
          hasMore = false;
        } else {
          page++;
        }
      } else {
        throw Exception('Failed to fetch travel requests for report');
      }
    }

    // 2. Filter requests locally
    final filtered = allRequests.where((req) {
      bool match = true;
      if (userId != null && req.userId != userId) {
        match = false;
      }
      if (startDate != null && req.requestDate.isBefore(startDate)) {
        match = false;
      }
      if (endDate != null) {
        final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        if (req.requestDate.isAfter(endOfDay)) {
          match = false;
        }
      }
      return match;
    }).toList();

    // Sort by date ascending
    filtered.sort((a, b) => a.requestDate.compareTo(b.requestDate));

    await generateExcelFile(filtered);
  }

  Future<void> generateExcelFile(List<TravelRequestModel> requests) async {
    final excel = Excel.createExcel();
    final sheet = excel['Trip Report'];
    excel.setDefaultSheet('Trip Report');

    // Headers
    final headers = [
      'Sr no.',
      'Date',
      'Status',
      'Employee Name',
      'Employee Code',
      'From Location',
      'To Location',
      'Route Summary (All Legs)',
      'Vehicle Type',
      'Fuel Type',
      'Distance (km)',
      'Travel Time (min)',
      'Meeting Time (min)',
      'Missing GPS Time (min)',
      'Travel Allowance (₹)',
      'Purpose',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Rows
    final df = DateFormat('yyyy-MM-dd HH:mm');
    int srNo = 1;
    for (final req in requests) {
      final r = req.withRecalculatedSummary();
      final dist = r.totalDistanceKm > 0 ? r.totalDistanceKm : (r.distance ?? 0.0);
      
      final gpsMissingTime = r.totalTravelDurationMinutes > 0
          ? (r.totalTravelDurationMinutes - (r.totalMovingMinutesFromTrack + r.totalStoppedMinutesFromTrack)).clamp(0, r.totalTravelDurationMinutes)
          : 0;

      final row = [
        IntCellValue(srNo++),
        TextCellValue(df.format(r.requestDate)),
        TextCellValue(r.status),
        TextCellValue(r.userName),
        TextCellValue(r.employeeCode ?? ''),
        TextCellValue(r.fromLocation),
        TextCellValue(r.displayToLocation),
        TextCellValue(r.compactLegsSummary),
        TextCellValue(r.vehicleType),
        TextCellValue(r.fuelType ?? ''),
        DoubleCellValue(dist),
        IntCellValue(r.totalTravelDurationMinutes),
        IntCellValue(r.totalMeetingDurationMinutes),
        IntCellValue(gpsMissingTime),
        DoubleCellValue(r.displayTravelAllowance),
        TextCellValue(r.purpose ?? ''),
      ];
      sheet.appendRow(row);
    }

    // 4. Save/Download
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file');
    }

    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Trip_Report_$dateStr.xlsx';

    await FileDownloadService.downloadFile(
      bytes: bytes,
      fileName: fileName,
    );
  }
}
