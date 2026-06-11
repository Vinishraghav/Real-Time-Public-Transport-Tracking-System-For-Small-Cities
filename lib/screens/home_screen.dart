import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/bus_models.dart';
import '../providers/bus_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _toCtrl = TextEditingController();
  bool _isSearching = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    final locationProvider = context.read<LocationProvider>();
    final busProvider = context.read<BusProvider>();

    await locationProvider.ensurePermissionAndPosition();

    if (!mounted || !locationProvider.isLocationEnabled) return;

    if (busProvider.isDriver && busProvider.tripStatus == TripStatus.active) {
      locationProvider.startDriverLocationStream(
        (lat, lng, speed, heading) =>
            busProvider.sendDriverLocation(lat, lng, speed, heading),
        interval: busProvider.session?.dataSaver == true
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3),
        distanceFilterMeters: busProvider.session?.dataSaver == true ? 12 : 5,
      );
    } else if (!busProvider.isDriver) {
      locationProvider.startPassengerLocationStream(
        (lat, lng) {
          busProvider.checkPassengerProximity(lat, lng);
        },
        distanceFilterMeters: busProvider.session?.dataSaver == true ? 25 : 10,
      );
    }
  }

  void _syncLiveTracking(
    BusProvider busProvider,
    LocationProvider locationProvider,
  ) {
    if (!locationProvider.isLocationEnabled) return;

    if (busProvider.isDriver) {
      final shouldTrackDriver =
          busProvider.tripStatus == TripStatus.active ||
          (busProvider.activeTrip != null &&
              busProvider.tripStatus != TripStatus.ended);
      if (shouldTrackDriver && !locationProvider.isDriverStreaming) {
        locationProvider.startDriverLocationStream(
          (lat, lng, speed, heading) =>
              busProvider.sendDriverLocation(lat, lng, speed, heading),
          interval: busProvider.session?.dataSaver == true
              ? const Duration(seconds: 5)
              : const Duration(seconds: 3),
          distanceFilterMeters: busProvider.session?.dataSaver == true ? 12 : 5,
        );
      } else if (!shouldTrackDriver && locationProvider.isDriverStreaming) {
        locationProvider.stopLocationStream();
      }
      return;
    }

    if (!locationProvider.isPassengerStreaming) {
      locationProvider.startPassengerLocationStream(
        (lat, lng) {
          busProvider.checkPassengerProximity(lat, lng);
        },
        distanceFilterMeters: busProvider.session?.dataSaver == true ? 25 : 10,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: Consumer2<BusProvider, LocationProvider>(
        builder: (context, busProvider, locationProvider, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncLiveTracking(busProvider, locationProvider);
          });
          return SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppTheme.primaryBlue,
              onRefresh: () async {
                await locationProvider.ensurePermissionAndPosition();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, busProvider),
                    const SizedBox(height: 24),
                    _buildMapPreview(context, busProvider, locationProvider),
                    const SizedBox(height: 24),
                    if (busProvider.isDriver)
                      _buildDriverPanel(context, busProvider, locationProvider)
                    else
                      _buildPassengerPanel(context, busProvider),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, BusProvider busProvider) {
    final strings = context.strings;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CityBus Live',
                style: TextStyle(
                  color: AppTheme.surfaceWhite,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accentOrange, width: 1.5),
                ),
                child: Text(
                  busProvider.isDriver
                      ? strings.t('driver_mode')
                      : strings.t('passenger_mode'),
                  style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (busProvider.isDriver && busProvider.busAccount != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bus ${busProvider.busAccount!.busNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.greenAccent,
                  size: 12,
                ),
                const SizedBox(width: 6),
                Text(
                  _tripStatusLabel(context, busProvider.tripStatus),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                if (busProvider.tripStatus == TripStatus.active) ...[
                  Text(
                    _formatDuration(busProvider.tripElapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  strings.t(
                    'nearby_buses_active',
                    params: {
                      'count': '${busProvider.nearbyActiveBuses.length}',
                    },
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _tripStatusLabel(BuildContext context, TripStatus status) {
    final strings = context.strings;
    switch (status) {
      case TripStatus.active:
        return strings.t('trip_active');
      case TripStatus.paused:
        return strings.t('trip_paused');
      case TripStatus.ended:
        return strings.t('trip_ended');
      case TripStatus.notStarted:
        return strings.t('no_active_trip');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Widget _buildMapPreview(
    BuildContext context,
    BusProvider busProvider,
    LocationProvider location,
  ) {
    final strings = context.strings;
    final markers = <Marker>{};
    final polylines = <Polyline>{};
    var target = const LatLng(10.7426, 77.1032);

    if (busProvider.isDriver && location.currentPosition != null) {
      target = LatLng(
        location.currentPosition!.latitude,
        location.currentPosition!.longitude,
      );
    } else if (busProvider.nearbyActiveBuses.isNotEmpty) {
      final liveBus = busProvider.nearbyActiveBuses.first;
      target = LatLng(liveBus.latitude, liveBus.longitude);
    } else if (location.currentPosition != null) {
      target = LatLng(
        location.currentPosition!.latitude,
        location.currentPosition!.longitude,
      );
    }

    for (final liveBus in busProvider.nearbyActiveBuses.take(5)) {
      markers.add(
        Marker(
          markerId: MarkerId('preview_${liveBus.busId}'),
          position: LatLng(liveBus.latitude, liveBus.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            liveBus.busId == busProvider.trackedBusId
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (busProvider.roadPoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('preview_route'),
          points: busProvider.roadPoints,
          color: Colors.white,
          width: 4,
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.push('/map'),
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryBlue.withValues(alpha: 0.8),
              AppTheme.primaryBlue.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: target, zoom: 13),
                myLocationEnabled: busProvider.isDriver,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                liteModeEnabled: true,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                markers: markers,
                polylines: polylines,
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      Icon(
                        Icons.map_rounded,
                        color: AppTheme.surfaceWhite,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Text(
                        strings.t('view_live_map'),
                        style: TextStyle(
                          color: AppTheme.surfaceWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppTheme.surfaceWhite,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverPanel(
    BuildContext context,
    BusProvider busProvider,
    LocationProvider location,
  ) {
    final strings = context.strings;
    final status = busProvider.tripStatus;
    final canStart =
        status == TripStatus.notStarted || status == TripStatus.ended;
    final canPause = status == TripStatus.active;
    final canResume = status == TripStatus.paused;
    final canEnd = status == TripStatus.active || status == TripStatus.paused;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.t('trip_management'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          if (busProvider.activeTrip != null) ...[
            Text(
              strings.t(
                'current_next',
                params: {
                  'current': _stopName(
                    busProvider,
                    busProvider.activeTrip!.currentStop,
                  ),
                  'next': _nextStopName(
                    busProvider,
                    busProvider.activeTrip!.nextStop,
                  ),
                },
              ),
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.t('trip_time')}: ${_formatDuration(busProvider.tripElapsed)}',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (busProvider.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                busProvider.error!,
                style: const TextStyle(color: AppTheme.alertRed, fontSize: 13),
              ),
            ),
          if (canStart)
            _tripButton(
              label: strings.t('start_trip'),
              icon: Icons.play_arrow_rounded,
              color: AppTheme.successGreen,
              onPressed: () async {
                final position = location.currentPosition;
                if (position == null) {
                  await location.ensurePermissionAndPosition();
                  return;
                }
                await busProvider.startTrip(
                  position.latitude,
                  position.longitude,
                  position.speed * 3.6,
                  position.heading,
                );
                location.startDriverLocationStream(
                  (lat, lng, speed, heading) =>
                      busProvider.sendDriverLocation(lat, lng, speed, heading),
                  interval: busProvider.session?.dataSaver == true
                      ? const Duration(seconds: 5)
                      : const Duration(seconds: 3),
                  distanceFilterMeters: busProvider.session?.dataSaver == true
                      ? 12
                      : 5,
                );
              },
            ),
          if (canPause) ...[
            const SizedBox(height: 12),
            _tripButton(
              label: strings.t('pause_trip'),
              icon: Icons.pause_rounded,
              color: AppTheme.accentOrange,
              onPressed: () async {
                await busProvider.pauseTrip();
                location.stopLocationStream();
              },
            ),
          ],
          if (canResume) ...[
            const SizedBox(height: 12),
            _tripButton(
              label: strings.t('resume_trip'),
              icon: Icons.play_circle_rounded,
              color: AppTheme.primaryBlue,
              onPressed: () async {
                final position = location.currentPosition;
                if (position == null) {
                  await location.ensurePermissionAndPosition();
                  return;
                }
                await busProvider.resumeTrip(
                  position.latitude,
                  position.longitude,
                  position.speed * 3.6,
                  position.heading,
                );
                location.startDriverLocationStream(
                  (lat, lng, speed, heading) =>
                      busProvider.sendDriverLocation(lat, lng, speed, heading),
                  interval: busProvider.session?.dataSaver == true
                      ? const Duration(seconds: 5)
                      : const Duration(seconds: 3),
                  distanceFilterMeters: busProvider.session?.dataSaver == true
                      ? 12
                      : 5,
                );
              },
            ),
          ],
          if (canEnd) ...[
            const SizedBox(height: 12),
            _tripButton(
              label: strings.t('end_trip'),
              icon: Icons.stop_rounded,
              color: AppTheme.alertRed,
              onPressed: () async {
                await busProvider.endTrip();
                location.stopLocationStream();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _tripButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, color: AppTheme.surfaceWhite),
        label: Text(
          label,
          style: const TextStyle(
            color: AppTheme.surfaceWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _stopName(BusProvider provider, String stopId) {
    if (stopId.isEmpty) {
      return provider.fallbackCurrentStopName();
    }
    final stop = provider.allStops.cast<BusStop?>().firstWhere(
      (candidate) => candidate?.id == stopId,
      orElse: () => null,
    );
    return stop?.name ?? provider.fallbackCurrentStopName();
  }

  String _nextStopName(BusProvider provider, String stopId) {
    if (stopId.isEmpty) {
      return provider.fallbackNextStopName();
    }
    final stop = provider.allStops.cast<BusStop?>().firstWhere(
      (candidate) => candidate?.id == stopId,
      orElse: () => null,
    );
    return stop?.name ?? provider.fallbackNextStopName();
  }

  Widget _buildPassengerPanel(BuildContext context, BusProvider busProvider) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.t('find_destination'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _toCtrl,
                decoration: InputDecoration(
                  hintText: strings.t('enter_destination_stop'),
                  prefixIcon: const Icon(
                    Icons.location_on_rounded,
                    color: AppTheme.accentOrange,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSearching
                      ? null
                      : () async {
                          setState(() => _isSearching = true);
                          await busProvider.searchRoute(_toCtrl.text);
                          if (mounted) {
                            setState(() => _isSearching = false);
                          }
                        },
                  icon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    strings.t('search'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (busProvider.selectedDestination != null) ...[
          const SizedBox(height: 24),
          _buildActiveDestination(busProvider),
        ],
        if (busProvider.error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.alertRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.alertRed),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    busProvider.error!,
                    style: const TextStyle(color: AppTheme.alertRed),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          strings.isTamil
              ? 'அருகிலுள்ள செயலில் உள்ள பேருந்துகள்'
              : 'Nearby Active Buses',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        if (busProvider.nearbyActiveBuses.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Text(
                strings.isTamil
                    ? 'அருகில் செயலில் உள்ள பேருந்துகள் இல்லை'
                    : 'No nearby active buses',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ),
          )
        else
          ...busProvider.nearbyActiveBuses.map(
            (live) => _LiveBusTile(live: live, busProvider: busProvider),
          ),
      ],
    );
  }

  Widget _buildActiveDestination(BusProvider busProvider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.successGreen, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.successGreen,
              ),
              const SizedBox(width: 8),
              const Text(
                'Tracking Destination',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            busProvider.selectedDestination!.name,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 16),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/map'),
              icon: const Icon(Icons.map_rounded),
              label: const Text('View on Map'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBusTile extends StatelessWidget {
  const _LiveBusTile({required this.live, required this.busProvider});

  final LiveBus live;
  final BusProvider busProvider;

  @override
  Widget build(BuildContext context) {
    final statusColor = live.tripStatus == TripStatus.active
        ? AppTheme.successGreen
        : AppTheme.accentOrange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: AppTheme.primaryBlue,
              size: 26,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${live.speed.toStringAsFixed(1)} km/h • Updated ${_timeAgo(live.lastUpdated)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  live.tripStatus == TripStatus.active ? 'ACTIVE' : 'PAUSED',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  await context.read<BusProvider>().trackBus(live.busId);
                  if (context.mounted) {
                    context.push('/map');
                  }
                },
                child: const Icon(
                  Icons.map_rounded,
                  color: AppTheme.primaryBlue,
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    return '${difference.inHours}h ago';
  }
}
