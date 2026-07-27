import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../features/tracking/domain/entities/employee_tracking_status.dart';
import 'app_map_tile_layer.dart';

/// Admin/HOD live employee map for desktop and web (OpenStreetMap).
class LiveEmployeesMapView extends StatefulWidget {
  const LiveEmployeesMapView({
    super.key,
    required this.employees,
    this.onEmployeeTap,
    this.focusedEmployeeId,
  });

  final List<TrackedEmployee> employees;
  final ValueChanged<TrackedEmployee>? onEmployeeTap;
  final String? focusedEmployeeId;

  @override
  State<LiveEmployeesMapView> createState() => LiveEmployeesMapViewState();
}

class LiveEmployeesMapViewState extends State<LiveEmployeesMapView> {
  final MapController mapController = MapController();

  @override
  void didUpdateWidget(LiveEmployeesMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedEmployeeId != widget.focusedEmployeeId &&
        widget.focusedEmployeeId != null) {
      final employee = widget.employees
          .where((e) => e.id == widget.focusedEmployeeId)
          .firstOrNull;
      if (employee != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          mapController.move(
            ll.LatLng(employee.position.latitude, employee.position.longitude),
            15,
          );
        });
      }
    } else if (oldWidget.employees != widget.employees) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitEmployees());
    }
  }

  void _fitEmployees() {
    final points = widget.employees
        .map((e) => ll.LatLng(e.position.latitude, e.position.longitude))
        .toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      mapController.move(points.first, 13);
      return;
    }
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(64),
      ),
    );
  }

  Color _colorFor(TrackingMarkerStatus status) => Color(status.colorValue);



  @override
  Widget build(BuildContext context) {
    final employees = widget.employees;
    final initial = employees.isNotEmpty
        ? ll.LatLng(
            employees.first.position.latitude,
            employees.first.position.longitude,
          )
        : const ll.LatLng(23.0225, 72.5714);

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initial,
        initialZoom: 12,
        onMapReady: _fitEmployees,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        appMapTileLayer(),

        MarkerLayer(
          markers: [
            for (final e in employees)
              Marker(
                point: ll.LatLng(e.position.latitude, e.position.longitude),
                width: 120,
                height: 48,
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () => widget.onEmployeeTap?.call(e),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 3),
                          ],
                        ),
                        child: Text(
                          e.displayName,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.location_on,
                        color: _colorFor(e.status),
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
