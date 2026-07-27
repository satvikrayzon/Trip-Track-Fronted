import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../app/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/punch_location_service.dart';
import '../../../../core/utils/map_marker_icon.dart';
import '../../../../core/widgets/google_map_web_gate.dart';
import '../../../../core/widgets/live_employees_map_view.dart';
import '../../../../shared/utils/map_animation_utils.dart';
import '../../../tracking/domain/entities/employee_tracking_status.dart';
import '../providers/live_map_provider.dart';
import '../widgets/employee_detail_sheet.dart';

/// Full-screen admin/HOD live employee map.
class LiveTrackingMapPage extends ConsumerStatefulWidget {
  const LiveTrackingMapPage({super.key});

  @override
  ConsumerState<LiveTrackingMapPage> createState() =>
      _LiveTrackingMapPageState();
}

class _LiveTrackingMapPageState extends ConsumerState<LiveTrackingMapPage>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final GlobalKey<LiveEmployeesMapViewState> _osmMapKey =
      GlobalKey<LiveEmployeesMapViewState>();
  final TextEditingController _searchController = TextEditingController();
  TrackedEmployee? _selected;
  String _search = '';
  LatLng? _deviceLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveMapProvider.notifier).start();
    });
    _initDeviceLocation();
  }

  Future<void> _initDeviceLocation() async {
    try {
      final pos = await PunchLocationService().getFastPosition();
      if (pos != null && mounted) {
        setState(() {
          _deviceLocation = LatLng(pos.latitude, pos.longitude);
        });
        _focusOnDeviceLocation();
      }
    } catch (e) {
    }
  }

  void _focusOnDeviceLocation() {
    if (_deviceLocation == null) return;
    final useGoogleMaps = googleMapsSupported();
    if (useGoogleMaps) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _deviceLocation!,
            zoom: 14,
          ),
        ),
      );
    } else {
      _osmMapKey.currentState?.mapController.move(
        ll.LatLng(_deviceLocation!.latitude, _deviceLocation!.longitude),
        14,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveMapProvider);
    final filtered = _filterEmployees(state.employees);
    final wsUnavailable = ref.watch(webSocketTrackingProvider).isBackendUnavailable;
    final useGoogleMaps = googleMapsSupported();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        title: const Text('Live Map'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(liveMapProvider.notifier).refresh(
                  force: true,
                ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!useGoogleMaps)
            LiveEmployeesMapView(
              key: _osmMapKey,
              employees: filtered,
              focusedEmployeeId: _selected?.id,
              onEmployeeTap: (e) => setState(() => _selected = e),
            )
          else
            GoogleMapWebGate(
              fallback: LiveEmployeesMapView(
                key: _osmMapKey,
                employees: filtered,
                focusedEmployeeId: _selected?.id,
                onEmployeeTap: (e) => setState(() => _selected = e),
              ),
              builder: (_) {
                final initialTarget = filtered.isNotEmpty
                    ? filtered.first.position
                    : (_deviceLocation ?? const LatLng(23.0225, 72.5714));
                
                return GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: 12,
                  ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _buildMarkers(filtered),
                onMapCreated: (c) {
                  _mapController = c;
                  if (filtered.isNotEmpty) {
                    _mapController?.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: filtered.first.position,
                          zoom: 14,
                        ),
                      ),
                    );
                  } else if (_deviceLocation != null) {
                    _focusOnDeviceLocation();
                  }
                },
                onCameraMove: (pos) {},
              );
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                elevation: 2,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(14),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search by name',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      if (_search.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                      _ConnectionStatus(
                        connected: state.isConnected,
                        liveViaSocket: state.liveViaSocket,
                        wsUnavailable: wsUnavailable,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_selected != null)
            EmployeeDetailSheet(
              employee: _selected!,
              onClose: () => setState(() => _selected = null),
              onFocus: () => _focusEmployee(_selected!),
            ),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator()),
          if (!state.isLoading && filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      state.lastRefreshError ??
                          'No active trips on the map.\n'
                          'Employees appear when a trip is in progress and GPS is on.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<TrackedEmployee> _filterEmployees(List<TrackedEmployee> all) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((e) {
      return e.displayName.toLowerCase().contains(q) ||
          (e.employeeCode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Set<Marker> _buildMarkers(List<TrackedEmployee> employees) {
    final items = employees
        .map((e) => MapClusterItem(e.id, e.position, e))
        .toList();
    final clusters = clusterMarkers(items: items, zoom: 12);

    return clusters.map((cluster) {
      if (cluster.items.length == 1) {
        final e = cluster.items.first.data as TrackedEmployee;
        return Marker(
          markerId: MarkerId(e.id),
          position: e.position,
          rotation: e.bearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: mapMarkerIcon(_hueForStatus(e.status)),
          onTap: () => setState(() => _selected = e),
          infoWindow: InfoWindow(
            title: e.displayName,
            snippet: e.tripRouteLabel ?? e.status.label,
          ),
        );
      }
      return Marker(
        markerId: MarkerId('cluster_${cluster.center.latitude}'),
        position: cluster.center,
        icon: mapMarkerIcon(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: '${cluster.items.length} employees',
        ),
      );
    }).toSet();
  }

  double _hueForStatus(TrackingMarkerStatus status) => switch (status) {
        TrackingMarkerStatus.active => BitmapDescriptor.hueGreen,
        TrackingMarkerStatus.online => BitmapDescriptor.hueAzure,
        TrackingMarkerStatus.gpsStopped => BitmapDescriptor.hueRed,
        TrackingMarkerStatus.offline => BitmapDescriptor.hueOrange,
      };

  void _focusEmployee(TrackedEmployee e) {
    final useGoogleMaps = googleMapsSupported();
    if (!useGoogleMaps) {
      _osmMapKey.currentState?.mapController.move(
        ll.LatLng(e.position.latitude, e.position.longitude),
        zoomForSpeed(e.speedKmh),
      );
      return;
    }
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: e.position,
          zoom: zoomForSpeed(e.speedKmh),
          bearing: e.bearing,
        ),
      ),
    );
  }


}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({
    required this.connected,
    required this.liveViaSocket,
    required this.wsUnavailable,
  });

  final bool connected;
  final bool liveViaSocket;
  final bool wsUnavailable;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch ((wsUnavailable, connected, liveViaSocket)) {
      (true, _, _) => (Colors.orange, 'HTTP'),
      (_, true, true) => (Colors.green, 'Live'),
      (_, true, false) => (Colors.orange, 'Socket'),
      _ => (Colors.red, 'Offline'),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
