import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/bus_models.dart';
import '../providers/bus_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  bool _mapReady = false;
  Timer? _cameraFollowDebounce;
  Timer? _markerAnimationTimer;
  LatLng? _lastCameraTarget;
  DateTime? _lastCameraFollowAt;
  LatLng? _animatedTrackedPosition;
  double _animatedTrackedHeading = 0;
  String? _animatedTrackedBusId;

  BitmapDescriptor? _stopIcon;
  BitmapDescriptor? _busIcon;
  BitmapDescriptor? _trackedBusIcon;
  BitmapDescriptor? _pausedBusIcon;

  static const Duration _cameraFollowInterval = Duration(seconds: 2);
  static const double _cameraFollowMinMoveMeters = 20;
  static const Duration _markerAnimationStep = Duration(milliseconds: 180);
  static const int _markerAnimationFrames = 8;

  int _findNearestIndex(List<LatLng> points, LatLng target) {
    if (points.isEmpty) return 0;
    var nearestIndex = 0;
    var minDistance = double.infinity;

    for (var i = 0; i < points.length; i++) {
      final distance = Geolocator.distanceBetween(
        target.latitude,
        target.longitude,
        points[i].latitude,
        points[i].longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  @override
  void initState() {
    super.initState();
    _initCustomMarkers();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<LocationProvider>().ensurePermissionAndPosition();
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _initCustomMarkers() async {
    _stopIcon = await _buildStopMarker();
    _busIcon = await _buildBusMarker(AppTheme.primaryBlue);
    _trackedBusIcon = await _buildBusMarker(Colors.orangeAccent);
    _pausedBusIcon = await _buildBusMarker(Colors.grey);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _buildStopMarker() async {
    const double size = 32.0;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    final Paint fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const double center = size / 2;
    canvas.drawCircle(const Offset(center, center), size / 2.0, borderPaint);
    canvas.drawCircle(const Offset(center, center), (size / 2.0) - 2.5, fillPaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(
          size.toInt(),
          size.toInt(),
        );
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _buildBusMarker(Color color) async {
    const double size = 80.0;
    
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    
    final Paint arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    final Path path = Path();
    path.moveTo(size / 2, 6);
    path.lineTo(size - 14, size - 14);
    path.lineTo(size / 2, size - 26);
    path.lineTo(14, size - 14);
    path.close();

    final Path shadowPath = path.shift(const Offset(0, 4));
    
    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, arrowPaint);
    canvas.drawPath(path, strokePaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(
          size.toInt(),
          size.toInt(),
        );
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _cameraFollowDebounce?.cancel();
    _markerAnimationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      body: Consumer2<LocationProvider, BusProvider>(
        builder: (context, locationProvider, busProvider, _) {
          final visibleBuses = busProvider.liveBuses
              .where((bus) => bus.tripStatus != TripStatus.ended)
              .toList();

          LiveBus? trackedBus;
          if (busProvider.trackedBusId != null) {
            trackedBus = visibleBuses.cast<LiveBus?>().firstWhere(
              (bus) => bus?.busId == busProvider.trackedBusId,
              orElse: () => null,
            );
          }

          trackedBus ??= _nearestBusToPassenger(locationProvider, visibleBuses);
          _syncTrackedMarker(trackedBus);

          final destinationStop = busProvider.selectedDestination;
          final eta = trackedBus != null && destinationStop != null
              ? busProvider.computeEta(trackedBus, destinationStop)
              : null;
          final distanceToTracked = _distanceToTrackedBus(
            locationProvider,
            trackedBus,
          );

          final polylines = _buildPolylines(
            busProvider: busProvider,
            trackedBus: trackedBus,
            locationProvider: locationProvider,
          );
          final markers = _buildMarkers(
            context: context,
            busProvider: busProvider,
            visibleBuses: visibleBuses,
            trackedBus: trackedBus,
          );

          _autoFollowIfNeeded(
            busProvider: busProvider,
            locationProvider: locationProvider,
            trackedBus: trackedBus,
          );

          return Stack(
            children: [
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  setState(() => _mapReady = true);
                },
                initialCameraPosition: CameraPosition(
                  target: _initialTarget(locationProvider, trackedBus),
                  zoom: 13,
                ),
                myLocationEnabled: busProvider.isDriver,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: markers,
                polylines: polylines,
              ),
              Positioned(
                top: 60,
                left: 20,
                right: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface(context),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: TextField(
                    onSubmitted: (value) =>
                        context.read<BusProvider>().searchRoute(value),
                    decoration: InputDecoration(
                      hintText: strings.t('search_stops_routes'),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.primaryBlue,
                        size: 24,
                      ),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      fillColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: trackedBus != null ? 230 : 100,
                child: FloatingActionButton(
                  heroTag: 'loc_btn',
                  onPressed: () => _centerOnRelevantTarget(
                    busProvider: busProvider,
                    locationProvider: locationProvider,
                    trackedBus: trackedBus,
                  ),
                  backgroundColor: AppTheme.surface(context),
                  elevation: 4,
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ),
              if (trackedBus != null)
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: _TrackedBusCard(
                    live: trackedBus,
                    distance: distanceToTracked,
                    eta: eta,
                    destinationStop: destinationStop,
                    driverName: busProvider.driverNameForBus(trackedBus.busId),
                    stopCount: busProvider.routeStops.length,
                    showRideAction:
                        !busProvider.isDriver &&
                        destinationStop != null &&
                        trackedBus.tripStatus == TripStatus.active,
                    onRidePressed: destinationStop == null
                        ? null
                        : () => busProvider.confirmRide(
                            busId: trackedBus!.busId,
                            destination: destinationStop,
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  LiveBus? _nearestBusToPassenger(
    LocationProvider locationProvider,
    List<LiveBus> visibleBuses,
  ) {
    if (visibleBuses.isEmpty || locationProvider.currentPosition == null) {
      return visibleBuses.isEmpty ? null : visibleBuses.first;
    }

    LiveBus? nearestBus;
    var minDistance = double.infinity;
    for (final bus in visibleBuses.where(
      (bus) => bus.tripStatus == TripStatus.active,
    )) {
      final distance = Geolocator.distanceBetween(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
        bus.latitude,
        bus.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestBus = bus;
      }
    }
    return nearestBus ?? visibleBuses.first;
  }

  double? _distanceToTrackedBus(
    LocationProvider locationProvider,
    LiveBus? trackedBus,
  ) {
    if (trackedBus == null || locationProvider.currentPosition == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      locationProvider.currentPosition!.latitude,
      locationProvider.currentPosition!.longitude,
      trackedBus.latitude,
      trackedBus.longitude,
    );
  }

  Set<Polyline> _buildPolylines({
    required BusProvider busProvider,
    required LiveBus? trackedBus,
    required LocationProvider locationProvider,
  }) {
    final polylines = <Polyline>{};
    final roadPoints = busProvider.roadPoints;
    final fallbackRoutePoints = busProvider.routeStops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();
    final routePoints = roadPoints.isNotEmpty ? roadPoints : fallbackRoutePoints;
    if (routePoints.length < 2) return polylines;

    LatLng? currentTarget;
    if (busProvider.isDriver && locationProvider.currentPosition != null) {
      currentTarget = LatLng(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
      );
    } else if (trackedBus != null) {
      currentTarget = _displayPositionForBus(trackedBus);
    }

    if (currentTarget == null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: AppTheme.primaryBlue,
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
        ),
      );
      return polylines;
    }

    final nearestIndex =
        trackedBus?.routeProgressIndex?.clamp(0, routePoints.length - 1) ??
        _findNearestIndex(routePoints, currentTarget);
    final completedPath = routePoints.sublist(0, nearestIndex + 1);
    final remainingPath = routePoints.sublist(nearestIndex);

    if (completedPath.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('completed_route'),
          points: completedPath,
          color: Colors.grey.shade400,
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
        ),
      );
    }

    if (remainingPath.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('remaining_route'),
          points: remainingPath,
          color: AppTheme.primaryBlue,
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
        ),
      );
    }

    return polylines;
  }

  Set<Marker> _buildMarkers({
    required BuildContext context,
    required BusProvider busProvider,
    required List<LiveBus> visibleBuses,
    required LiveBus? trackedBus,
  }) {
    final markers = <Marker>{};

    for (final liveBus in visibleBuses) {
      if (liveBus.latitude == 0 && liveBus.longitude == 0) continue;
      final isTracked = trackedBus?.busId == liveBus.busId;
      final position = isTracked
          ? _displayPositionForBus(liveBus)
          : LatLng(liveBus.latitude, liveBus.longitude);
      final icon = liveBus.tripStatus == TripStatus.active
          ? (isTracked ? _trackedBusIcon : _busIcon)
          : _pausedBusIcon;

      markers.add(
        Marker(
          markerId: MarkerId('bus_${liveBus.busId}'),
          position: position,
          rotation: isTracked ? _animatedTrackedHeading : liveBus.heading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: icon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: 'Bus ${liveBus.busId}',
            snippet: busProvider.driverNameForBus(liveBus.busId),
          ),
          onTap: () => context.read<BusProvider>().trackBus(liveBus.busId),
          zIndexInt: isTracked ? 3 : 2,
        ),
      );
    }

    for (var i = 0; i < busProvider.routeStops.length; i++) {
      final stop = busProvider.routeStops[i];

      markers.add(
        Marker(
          markerId: MarkerId('stop_${stop.id}'),
          position: LatLng(stop.latitude, stop.longitude),
          icon: _stopIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
          infoWindow: InfoWindow(
            title: stop.name,
            snippet: i == 0
                ? 'Start Stop'
                : i == busProvider.routeStops.length - 1
                ? 'Destination Stop'
                : 'Stop ${i + 1}',
          ),
        ),
      );
    }

    final searchedPlacePosition = busProvider.searchedPlacePosition;
    final searchedPlaceLabel = busProvider.searchedPlaceLabel;
    if (searchedPlacePosition != null && searchedPlaceLabel != null) {
      final isNearExistingStop = busProvider.routeStops.any((stop) {
        final distance = Geolocator.distanceBetween(
          searchedPlacePosition.latitude,
          searchedPlacePosition.longitude,
          stop.latitude,
          stop.longitude,
        );
        return distance <= 25;
      });

      if (!isNearExistingStop) {
        markers.add(
          Marker(
            markerId: const MarkerId('searched_place'),
            position: searchedPlacePosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueCyan,
            ),
            infoWindow: InfoWindow(
              title: searchedPlaceLabel,
              snippet: 'Searched place',
            ),
          ),
        );
      }
    }

    return markers;
  }

  LatLng _initialTarget(
    LocationProvider locationProvider,
    LiveBus? trackedBus,
  ) {
    if (trackedBus != null) {
      return LatLng(trackedBus.latitude, trackedBus.longitude);
    }
    final routeStops = context.read<BusProvider>().routeStops;
    if (routeStops.isNotEmpty) {
      return LatLng(routeStops.first.latitude, routeStops.first.longitude);
    }
    final searchedPlace = context.read<BusProvider>().searchedPlacePosition;
    if (searchedPlace != null) {
      return searchedPlace;
    }
    if (locationProvider.currentPosition != null) {
      return LatLng(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
      );
    }
    return const LatLng(10.7426, 77.1032);
  }

  void _autoFollowIfNeeded({
    required BusProvider busProvider,
    required LocationProvider locationProvider,
    required LiveBus? trackedBus,
  }) {
    if (!_mapReady || _mapController == null) return;

    LatLng? target;
    if (busProvider.isDriver && locationProvider.currentPosition != null) {
      target = LatLng(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
      );
    } else if (trackedBus != null && busProvider.trackedBusId != null) {
      target = _displayPositionForBus(trackedBus);
    }

    if (target == null) return;
    final followTarget = target;

    final now = DateTime.now();
    if (_lastCameraTarget != null) {
      final movedDistance = Geolocator.distanceBetween(
        _lastCameraTarget!.latitude,
        _lastCameraTarget!.longitude,
        target.latitude,
        target.longitude,
      );
      final followedRecently =
          _lastCameraFollowAt != null &&
          now.difference(_lastCameraFollowAt!) < _cameraFollowInterval;
      if (followedRecently && movedDistance < _cameraFollowMinMoveMeters) {
        return;
      }
    }

    _cameraFollowDebounce?.cancel();
    _cameraFollowDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _mapController == null) return;
      _lastCameraTarget = followTarget;
      _lastCameraFollowAt = DateTime.now();
      _mapController!.animateCamera(CameraUpdate.newLatLng(followTarget));
    });
  }

  Future<void> _centerOnRelevantTarget({
    required BusProvider busProvider,
    required LocationProvider locationProvider,
    required LiveBus? trackedBus,
  }) async {
    if (busProvider.isDriver) {
      await locationProvider.ensurePermissionAndPosition();
      if (locationProvider.currentPosition != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              locationProvider.currentPosition!.latitude,
              locationProvider.currentPosition!.longitude,
            ),
            15,
          ),
        );
      }
      return;
    }

    if (trackedBus != null) {
      final position = _displayPositionForBus(trackedBus);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
      return;
    }

    final searchedPlace = busProvider.searchedPlacePosition;
    if (searchedPlace != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(searchedPlace, 15),
      );
      return;
    }

    await locationProvider.ensurePermissionAndPosition();
    if (locationProvider.currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(
            locationProvider.currentPosition!.latitude,
            locationProvider.currentPosition!.longitude,
          ),
          15,
        ),
      );
    }
  }

  LatLng _displayPositionForBus(LiveBus bus) {
    if (_animatedTrackedBusId == bus.busId &&
        _animatedTrackedPosition != null) {
      return _animatedTrackedPosition!;
    }
    return LatLng(bus.latitude, bus.longitude);
  }

  void _syncTrackedMarker(LiveBus? trackedBus) {
    if (trackedBus == null) {
      _markerAnimationTimer?.cancel();
      _animatedTrackedBusId = null;
      _animatedTrackedPosition = null;
      _animatedTrackedHeading = 0;
      return;
    }

    final target = LatLng(trackedBus.latitude, trackedBus.longitude);
    if (_animatedTrackedBusId != trackedBus.busId ||
        _animatedTrackedPosition == null) {
      _animatedTrackedBusId = trackedBus.busId;
      _animatedTrackedPosition = target;
      _animatedTrackedHeading = trackedBus.heading;
      return;
    }

    final movedDistance = Geolocator.distanceBetween(
      _animatedTrackedPosition!.latitude,
      _animatedTrackedPosition!.longitude,
      target.latitude,
      target.longitude,
    );
    if (movedDistance < 3) {
      _animatedTrackedHeading = trackedBus.heading;
      return;
    }

    _markerAnimationTimer?.cancel();
    final start = _animatedTrackedPosition!;
    final startHeading = _animatedTrackedHeading;
    var frame = 0;

    _markerAnimationTimer = Timer.periodic(_markerAnimationStep, (timer) {
      frame += 1;
      final progress = frame / _markerAnimationFrames;
      final nextLat =
          start.latitude + ((target.latitude - start.latitude) * progress);
      final nextLng =
          start.longitude + ((target.longitude - start.longitude) * progress);
      final nextHeading =
          startHeading + ((trackedBus.heading - startHeading) * progress);

      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _animatedTrackedPosition = LatLng(nextLat, nextLng);
        _animatedTrackedHeading = nextHeading;
      });

      if (frame >= _markerAnimationFrames) {
        timer.cancel();
      }
    });
  }
}

class _TrackedBusCard extends StatelessWidget {
  const _TrackedBusCard({
    required this.live,
    required this.driverName,
    required this.stopCount,
    this.distance,
    this.eta,
    this.destinationStop,
    this.showRideAction = false,
    this.onRidePressed,
  });

  final LiveBus live;
  final String driverName;
  final int stopCount;
  final double? distance;
  final String? eta;
  final BusStop? destinationStop;
  final bool showRideAction;
  final Future<void> Function()? onRidePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  color: AppTheme.primaryBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bus ${live.busId}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      driverName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${live.speed.toStringAsFixed(1)} km/h',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.route_rounded,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$stopCount stops',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: live.tripStatus == TripStatus.active
                      ? AppTheme.successGreen
                      : AppTheme.accentOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  live.tripStatus == TripStatus.active ? 'ON ROUTE' : 'PAUSED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (distance != null || (destinationStop != null && eta != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (distance != null) ...[
                  const Icon(
                    Icons.location_on_rounded,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    distance! < 1000
                        ? '${distance!.round()} m away'
                        : '${(distance! / 1000).toStringAsFixed(1)} km away',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                if (destinationStop != null && eta != null) ...[
                  if (distance != null) const SizedBox(width: 12),
                  const Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: AppTheme.accentOrange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'ETA to ${destinationStop!.name}: $eta',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (showRideAction && onRidePressed != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => onRidePressed!.call(),
                child: const Text('Ride this Bus'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
