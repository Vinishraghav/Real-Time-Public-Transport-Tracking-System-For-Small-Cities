import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/auth_models.dart';
import '../models/bus_models.dart';
import '../models/ride_models.dart';
import '../l10n/app_strings.dart';
import '../services/firestore_service.dart';
import '../services/route_engine_service.dart';

/// Central app state for both driver and passenger experiences.
class BusProvider extends ChangeNotifier {
  BusProvider({
    FirestoreService? firestoreService,
    RouteEngineService? routeEngineService,
  }) : _fs = firestoreService ?? FirestoreService(),
       _routeEngine = routeEngineService ?? RouteEngineService();

  final FirestoreService _fs;
  final RouteEngineService _routeEngine;

  AppSession? _session;
  bool _isDriver = false;
  BusAccount? _busAccount;
  Trip? _activeTrip;
  Duration _tripElapsed = Duration.zero;

  List<LiveBus> _liveBuses = [];
  List<BusRoute> _allRoutes = [];
  List<BusStop> _allStops = [];
  List<BusAccount> _allBusAccounts = [];
  List<BusStop> _routeStops = [];
  List<LatLng> _roadPoints = [];

  final Map<String, String> _driverNames = {};
  final Map<String, List<BusStop>> _routeStopsCache = {};
  final Map<String, List<LatLng>> _routePathCache = {};
  final Map<String, Map<String, int>> _routeStopProgressCache = {};
  final List<Alert> _alerts = [];
  final Set<String> _firedAlertKeys = {};

  BusStop? _selectedDestination;
  String? _trackedBusId;
  RideRequest? _activeRide;
  LatLng? _passengerPosition;
  LatLng? _searchedPlacePosition;
  String? _searchedPlaceLabel;

  StreamSubscription<List<LiveBus>>? _liveBusSub;
  StreamSubscription<List<RideRequest>>? _routeRideSub;
  StreamSubscription<List<RideRequest>>? _passengerRideSub;
  Timer? _tripTicker;

  DateTime _lastUpdated = DateTime.now();
  DateTime? _lastDelayAlertAt;
  DateTime? _lastDeviationAlertAt;
  DateTime? _lastRideTrackingWriteAt;
  List<RideRequest> _routeRideRequests = [];

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  bool _sessionSyncScheduled = false;

  double _lastDriverLat = 0;
  double _lastDriverLng = 0;
  double _lastDriverHeading = 0;
  double _lastDriverSpeed = 0;
  DateTime? _lastDriverWriteAt;
  TripStatus? _lastDriverSentStatus;

  static const Duration _defaultTripTick = Duration(seconds: 1);
  static const Duration _routeDeviationCooldown = Duration(minutes: 3);
  static const Duration _delayWarningCooldown = Duration(minutes: 2);
  static const Duration _driverWriteMinInterval = Duration(seconds: 2);
  static const double _defaultPassengerRadius = 7000;
  static const double _dataSaverPassengerRadius = 3000;
  static const double _minDriverWriteDistanceMeters = 10;
  static const double _minDriverHeadingDelta = 10;
  static const double _minDriverSpeedDelta = 4;
  static const Duration _rideTrackingWriteInterval = Duration(seconds: 10);
  static const double _maxStopSnapMeters = 80;

  bool get isDriver => _isDriver;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  BusAccount? get busAccount => _busAccount;
  Trip? get activeTrip => _activeTrip;
  Duration get tripElapsed => _tripElapsed;
  DateTime get lastUpdated => _lastUpdated;
  AppSession? get session => _session;
  List<LiveBus> get liveBuses => List.unmodifiable(_liveBuses);
  List<BusRoute> get allRoutes => List.unmodifiable(_allRoutes);
  List<BusStop> get allStops => List.unmodifiable(_allStops);
  List<BusStop> get routeStops => List.unmodifiable(_routeStops);
  List<LatLng> get roadPoints => List.unmodifiable(_roadPoints);
  List<Alert> get alerts => List.unmodifiable(_alerts);
  BusStop? get selectedDestination => _selectedDestination;
  String? get trackedBusId => _trackedBusId;
  RideRequest? get activeRide => _activeRide;
  Map<String, String> get driverNames => Map.unmodifiable(_driverNames);
  LatLng? get searchedPlacePosition => _searchedPlacePosition;
  String? get searchedPlaceLabel => _searchedPlaceLabel;
  String get currentRouteId => _currentRouteIdForSession();
  BusRoute? get currentRoute {
    final routeId = currentRouteId;
    if (routeId.isEmpty) return null;
    try {
      return _allRoutes.firstWhere((route) => route.id == routeId);
    } catch (_) {
      return null;
    }
  }

  List<BusRoute> get driverAvailableRoutes {
    final account = _busAccount;
    if (account == null) return const [];
    final routeLookup = {for (final route in _allRoutes) route.id: route};
    return account.availableRouteIds
        .map((routeId) => routeLookup[routeId])
        .whereType<BusRoute>()
        .toList();
  }

  TripStatus get tripStatus {
    final busNumber = _busAccount?.busNumber;
    if (busNumber == null || busNumber.isEmpty) return TripStatus.notStarted;
    try {
      return _liveBuses.firstWhere((b) => b.busId == busNumber).tripStatus;
    } catch (_) {
      return _activeTrip == null ? TripStatus.notStarted : TripStatus.paused;
    }
  }

  double get _passengerRadiusMeters => _session?.dataSaver == true
      ? _dataSaverPassengerRadius
      : _defaultPassengerRadius;

  List<LiveBus> get nearbyActiveBuses {
    final activeBuses = _liveBuses.where(
      (bus) => bus.tripStatus == TripStatus.active,
    );
    if (_passengerPosition == null) {
      return activeBuses.toList();
    }

    return activeBuses.where((bus) {
      final distance = Geolocator.distanceBetween(
        _passengerPosition!.latitude,
        _passengerPosition!.longitude,
        bus.latitude,
        bus.longitude,
      );
      return distance <= _passengerRadiusMeters;
    }).toList()..sort((a, b) {
      final distanceA = Geolocator.distanceBetween(
        _passengerPosition!.latitude,
        _passengerPosition!.longitude,
        a.latitude,
        a.longitude,
      );
      final distanceB = Geolocator.distanceBetween(
        _passengerPosition!.latitude,
        _passengerPosition!.longitude,
        b.latitude,
        b.longitude,
      );
      return distanceA.compareTo(distanceB);
    });
  }

  Future<void> init() async {
    if (_isInitialized) return;

    _setLoading(true);
    try {
      final results = await Future.wait([
        _fs.fetchAllRoutes(),
        _fs.fetchAllStops(),
        _fs.fetchAllBuses(),
      ]);

      _allRoutes = results[0] as List<BusRoute>;
      _allStops = results[1] as List<BusStop>;
      _allBusAccounts = results[2] as List<BusAccount>;
      _subscribeToLiveBuses();
      _isInitialized = true;
    } catch (e) {
      _setError(
        AppStrings.translateForLanguage(
          _session?.language ?? 'English',
          'init_failed',
          params: {'error': '$e'},
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  void bindSession(AppSession? session) {
    final changedUser =
        _session?.uid != session?.uid ||
        _session?.role != session?.role ||
        _session?.busNumber != session?.busNumber;

    if (!changedUser && _session?.uid == session?.uid) {
      _session = session;
      _isDriver = session?.isDriver ?? false;
      return;
    }

    _session = session;
    _isDriver = session?.isDriver ?? false;

    if (_sessionSyncScheduled) return;
    _sessionSyncScheduled = true;

    Future<void>.microtask(() async {
      _sessionSyncScheduled = false;

      final activeSession = _session;
      if (activeSession == null) {
        _resetSessionState();
        _notifyIfNeeded();
        return;
      }

      if (!_isInitialized) {
        await init();
      }

      await _restoreSessionState(activeSession);
    });
  }

  Future<void> _restoreSessionState(AppSession session) async {
    _setLoading(true);
    _clearSubscriptions();
    _selectedDestination = null;
    _trackedBusId = null;
    _activeRide = null;
    _routeRideRequests = [];
    _firedAlertKeys.clear();
    _lastDelayAlertAt = null;
    _lastDeviationAlertAt = null;
    _tripTicker?.cancel();
    _tripElapsed = Duration.zero;

    try {
      if (session.isDriver) {
        _busAccount = await _fs.fetchBusAccountByNumber(
          session.busNumber ?? '',
        );
        if (_busAccount != null) {
          _activeTrip = await _fs.fetchActiveTripForBus(_busAccount!.busNumber);
          final routeId = _activeTrip?.routeId.isNotEmpty == true
              ? _activeTrip!.routeId
              : _busAccount!.resolvedCurrentRouteId;
          if (routeId.isNotEmpty) {
            await selectDriverRoute(
              routeId,
              persist: routeId != _busAccount!.currentRouteId,
            );
          } else {
            _routeStops = [];
            _roadPoints = [];
          }
          if (_activeTrip != null) {
            _startTripTicker(from: _activeTrip!.startTime);
          }
        }
      } else {
        _busAccount = null;
        _activeTrip = null;
        _routeStops = [];
        _roadPoints = [];
        _passengerRideSub = _fs.streamPassengerRides(session.uid).listen((
          rides,
        ) async {
          _activeRide = rides.isEmpty ? null : rides.first;
          if (_activeRide != null) {
            _trackedBusId = _activeRide!.busId;
            _selectedDestination = _findStopById(
              _activeRide!.destinationStopId,
            );
            await _loadRouteForBus(_activeRide!.busId);
          }
          _notifyIfNeeded();
        });
      }
      _error = null;
    } catch (e) {
      _setError(
        AppStrings.translateForLanguage(
          _session?.language ?? 'English',
          'session_restore_failed',
          params: {'error': '$e'},
        ),
      );
    } finally {
      _setLoading(false);
      _notifyIfNeeded();
    }
  }

  void pauseListeners() {
    _liveBusSub?.pause();
    _routeRideSub?.pause();
    _passengerRideSub?.pause();
  }

  void resumeListeners() {
    _liveBusSub?.resume();
    _routeRideSub?.resume();
    _passengerRideSub?.resume();
    if (!_isInitialized) {
      unawaited(init());
    }
  }

  void _subscribeToLiveBuses() {
    _liveBusSub?.cancel();
    _liveBusSub = _fs.streamActiveLiveBuses().listen((buses) {
      _liveBuses = buses;
      _lastUpdated = DateTime.now();
      unawaited(_refreshDriverNames());
      _evaluatePassengerAlerts();
      _notifyIfNeeded();
    }, onError: (e) => _setError('Live stream error: $e'));
  }

  Future<void> _refreshDriverNames() async {
    final ids = _liveBuses.map((bus) => bus.busId).toSet().toList();
    final missingIds = ids
        .where((id) => !_driverNames.containsKey(id))
        .toList();
    if (missingIds.isEmpty) return;

    final fetched = await _fs.fetchDriverNamesByBusIds(missingIds);
    if (fetched.isEmpty) return;
    _driverNames.addAll(fetched);
    _notifyIfNeeded();
  }

  Future<void> _loadRouteForBus(String busId) async {
    final liveRouteId = _liveBuses
        .cast<LiveBus?>()
        .firstWhere((bus) => bus?.busId == busId, orElse: () => null)
        ?.routeId;
    final account = _findBusAccount(busId);
    final routeId = (liveRouteId?.isNotEmpty == true)
        ? liveRouteId!
        : account?.resolvedCurrentRouteId ?? '';
    if (routeId.isEmpty) return;
    await _loadRouteData(routeId);
    _notifyIfNeeded();
  }

  Future<void> selectDriverRoute(String routeId, {bool persist = true}) async {
    final account = _busAccount;
    if (account == null || routeId.isEmpty) return;
    if (tripStatus == TripStatus.active &&
        account.resolvedCurrentRouteId != routeId) {
      return;
    }

    _busAccount = account.copyWith(currentRouteId: routeId, routeId: routeId);
    if (persist) {
      await _fs.updateBusCurrentRoute(
        busId: account.id,
        routeId: routeId,
        tripStatus: tripStatus.name,
      );
    }
    await _loadRouteData(routeId);
    await _subscribeDriverRideRequests(routeId);
    _notifyIfNeeded();
  }

  Future<void> loginAsPassenger() async {
    if (_session != null && !_session!.isDriver) {
      _notifyIfNeeded();
    }
  }

  Future<void> startTrip(
    double lat,
    double lng,
    double speed,
    double heading,
  ) async {
    if (_busAccount == null || tripStatus == TripStatus.active) return;

    await _pushDriverLiveLocation(
      lat: lat,
      lng: lng,
      speed: speed,
      heading: heading,
      status: TripStatus.active,
      force: true,
    );

    final stopPair = _resolveCurrentAndNextStops(lat, lng);
    final routeId = currentRouteId;
    _activeTrip = await _fs.startTrip(
      busId: _busAccount!.busNumber,
      routeId: routeId,
      currentStop: stopPair.$1?.id ?? '',
      nextStop: stopPair.$2?.id ?? '',
    );
    await _fs.updateBusCurrentRoute(
      busId: _busAccount!.id,
      routeId: routeId,
      tripStatus: TripStatus.active.name,
    );
    _startTripTicker(from: DateTime.now());
    _notifyIfNeeded();
  }

  Future<void> pauseTrip() async {
    if (_busAccount == null || tripStatus != TripStatus.active) return;

    await _pushDriverLiveLocation(
      lat: _lastDriverLat,
      lng: _lastDriverLng,
      speed: 0,
      heading: _lastDriverHeading,
      status: TripStatus.paused,
      force: true,
    );
    _tripTicker?.cancel();
    _notifyIfNeeded();
  }

  Future<void> resumeTrip(
    double lat,
    double lng,
    double speed,
    double heading,
  ) async {
    if (_busAccount == null) return;

    await _pushDriverLiveLocation(
      lat: lat,
      lng: lng,
      speed: speed,
      heading: heading,
      status: TripStatus.active,
      force: true,
    );
    _activeTrip ??= await _fs.fetchActiveTripForBus(_busAccount!.busNumber);
    _startTripTicker(from: DateTime.now().subtract(_tripElapsed));
    _notifyIfNeeded();
  }

  Future<void> endTrip() async {
    if (_busAccount == null) return;

    await _pushDriverLiveLocation(
      lat: 0,
      lng: 0,
      speed: 0,
      heading: 0,
      status: TripStatus.ended,
      force: true,
    );
    if (_activeTrip != null) {
      await _fs.endTrip(_activeTrip!.id);
    }
    _activeTrip = null;
    _tripTicker?.cancel();
    _tripElapsed = Duration.zero;
    _roadPoints = [];
    final routeId = currentRouteId;
    _routeStops = _busAccount == null || routeId.isEmpty
        ? []
        : await _fs.fetchStopsForRoute(routeId);
    await _fs.updateBusCurrentRoute(
      busId: _busAccount!.id,
      routeId: routeId,
      tripStatus: TripStatus.ended.name,
    );
    _notifyIfNeeded();
  }

  Future<void> sendDriverLocation(
    double lat,
    double lng,
    double speed,
    double heading,
  ) async {
    if (_busAccount == null || tripStatus == TripStatus.paused) return;

    final didWrite = await _pushDriverLiveLocation(
      lat: lat,
      lng: lng,
      speed: speed,
      heading: heading,
      status: TripStatus.active,
    );
    if (!didWrite) return;

    await _syncTripStops(lat, lng);
    _evaluateDriverMovementAlerts(lat, lng, speed);

    _lastUpdated = DateTime.now();
    _notifyIfNeeded();
  }

  Future<void> searchRoute(String query) async {
    _setLoading(true);
    try {
      final searchResult = await _resolveDestination(query);
      final destination = searchResult?.stop;
      if (destination == null) {
        _searchedPlacePosition = null;
        _searchedPlaceLabel = null;
        _setError(
          AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'stop_not_found',
          ),
        );
        return;
      }

      _selectedDestination = destination;
      _searchedPlacePosition = searchResult?.searchedPlacePosition;
      _searchedPlaceLabel = searchResult?.searchedPlaceLabel;
      _trackedBusId = null;

      if (destination.routeId.isNotEmpty) {
        await _loadRouteData(destination.routeId);
      }
      _error = null;
    } catch (e) {
      _setError(
        AppStrings.translateForLanguage(
          _session?.language ?? 'English',
          'search_failed',
          params: {'error': '$e'},
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  void setDestination(BusStop stop) {
    _selectedDestination = stop;
    _searchedPlacePosition = null;
    _searchedPlaceLabel = null;
    _notifyIfNeeded();
  }

  Future<void> trackBus(String busId) async {
    _trackedBusId = busId;
    await _loadRouteForBus(busId);
    _notifyIfNeeded();
  }

  Future<void> confirmRide({
    required String busId,
    required BusStop destination,
  }) async {
    final session = _session;
    if (session == null || session.isDriver) return;

    final routeId = destination.routeId.isNotEmpty
        ? destination.routeId
        : _routeIdForBus(busId);
    final rideId = '${session.uid}_$busId';

    await _fs.upsertRide(
      rideId: rideId,
      passengerId: session.uid,
      passengerName: session.displayName,
      routeId: routeId,
      busId: busId,
      destinationStopId: destination.id,
      destinationStopName: destination.name,
      passengerLat: _passengerPosition?.latitude,
      passengerLng: _passengerPosition?.longitude,
    );

    _activeRide = RideRequest(
      id: rideId,
      passengerId: session.uid,
      passengerName: session.displayName,
      routeId: routeId,
      busId: busId,
      destinationStopId: destination.id,
      destinationStopName: destination.name,
      status: RideStatus.waiting,
      createdAt: DateTime.now(),
    );
    _trackedBusId = busId;
    _selectedDestination = destination;
    await _loadRouteForBus(busId);
    _addAlert(
      key: 'ride_confirmed_$rideId',
      alert: Alert(
        id: 'ride_$rideId',
        title: AppStrings.translateForLanguage(
          _session?.language ?? 'English',
          'ride_confirmed',
        ),
        message: AppStrings.translateForLanguage(
          _session?.language ?? 'English',
          'tracking_bus_to',
          params: {'busId': busId, 'destination': destination.name},
        ),
        type: 'info',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> cancelRide() async {
    if (_activeRide == null) return;
    await _fs.updateRideStatus(
      rideId: _activeRide!.id,
      status: RideStatus.cancelled,
    );
    _activeRide = null;
    _trackedBusId = null;
    _searchedPlacePosition = null;
    _searchedPlaceLabel = null;
    _lastRideTrackingWriteAt = null;
    _notifyIfNeeded();
  }

  void checkPassengerProximity(double passengerLat, double passengerLng) {
    if (_isDriver) return;
    _passengerPosition = LatLng(passengerLat, passengerLng);
    unawaited(_syncRideTracking());
    _evaluatePassengerAlerts();
    _notifyIfNeeded();
  }

  Future<void> markAlertAsRead(String alertId) async {
    final index = _alerts.indexWhere((alert) => alert.id == alertId);
    if (index != -1) {
      _alerts[index].isRead = true;
      _notifyIfNeeded();
    }
  }

  Future<void> clearAllAlerts() async {
    _alerts.clear();
    _notifyIfNeeded();
  }

  String computeEta(LiveBus bus, BusStop destination) {
    final distanceMeters =
        _remainingRouteDistanceToStop(
          from: LatLng(bus.latitude, bus.longitude),
          stop: destination,
        ) ??
        Geolocator.distanceBetween(
          bus.latitude,
          bus.longitude,
          destination.latitude,
          destination.longitude,
        );
    final speedKmh = bus.speed > 0 ? bus.speed : 28;
    final etaMinutes = (distanceMeters / 1000) / speedKmh * 60;
    if (etaMinutes < 1) return '< 1 min';
    return '${etaMinutes.ceil()} min';
  }

  String driverNameForBus(String busId) =>
      _driverNames[busId] ?? 'Driver unavailable';

  String routeIdForBus(String busId) => _routeIdForBus(busId);

  BusStop? nextStopForBus(LiveBus bus) =>
      _resolveCurrentAndNextStops(bus.latitude, bus.longitude).$2;

  int stopsRemainingForBus(LiveBus bus, BusStop destination) {
    final nextStop = nextStopForBus(bus);
    if (nextStop == null) return 0;

    final nextIndex = _routeStops.indexWhere((stop) => stop.id == nextStop.id);
    final destinationIndex = _routeStops.indexWhere(
      (stop) => stop.id == destination.id,
    );
    if (nextIndex == -1 || destinationIndex == -1) return 0;
    return destinationIndex >= nextIndex
        ? (destinationIndex - nextIndex + 1)
        : 0;
  }

  Future<void> _syncTripStops(double lat, double lng) async {
    if (_activeTrip == null || _routeStops.isEmpty) return;

    final stopPair = _resolveCurrentAndNextStops(lat, lng);
    final currentStop = stopPair.$1;
    final nextStop = stopPair.$2;
    if (currentStop == null) return;

    if (currentStop.id != _activeTrip!.currentStop ||
        (nextStop?.id ?? '') != _activeTrip!.nextStop) {
      await _fs.updateTripStops(
        tripId: _activeTrip!.id,
        currentStop: currentStop.id,
        nextStop: nextStop?.id ?? '',
      );

      _activeTrip = Trip(
        id: _activeTrip!.id,
        busId: _activeTrip!.busId,
        routeId: _activeTrip!.routeId,
        startTime: _activeTrip!.startTime,
        endTime: _activeTrip!.endTime,
        currentStop: currentStop.id,
        nextStop: nextStop?.id ?? '',
      );
    }
  }

  (BusStop?, BusStop?) _resolveCurrentAndNextStops(double lat, double lng) {
    if (_routeStops.isEmpty) return (null, null);

    final routeId = currentRouteId.isNotEmpty
        ? currentRouteId
        : (_session?.routeId ?? '');
    final stopProgress = _routeStopProgressCache[routeId];
    if (_roadPoints.isNotEmpty &&
        stopProgress != null &&
        stopProgress.isNotEmpty) {
      final currentRouteIndex = _findNearestIndex(
        _roadPoints,
        LatLng(lat, lng),
      );
      BusStop? currentStop;
      BusStop? nextStop;

      for (final stop in _routeStops) {
        final stopIndex = stopProgress[stop.id];
        if (stopIndex == null) continue;
        if (stopIndex <= currentRouteIndex + 3) {
          currentStop = stop;
          continue;
        }
        nextStop = stop;
        break;
      }

      currentStop ??= _routeStops.first;
      if (nextStop == null) {
        final currentIndex = _routeStops.indexWhere(
          (stop) => stop.id == currentStop!.id,
        );
        if (currentIndex >= 0 && currentIndex + 1 < _routeStops.length) {
          nextStop = _routeStops[currentIndex + 1];
        }
      }
      return (currentStop, nextStop);
    }

    BusStop? currentStop;
    var minDistance = double.infinity;
    for (final stop in _routeStops) {
      final distance = Geolocator.distanceBetween(
        lat,
        lng,
        stop.latitude,
        stop.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        currentStop = stop;
      }
    }

    BusStop? nextStop;
    if (currentStop != null) {
      final currentIndex = _routeStops.indexWhere(
        (stop) => stop.id == currentStop!.id,
      );
      if (currentIndex >= 0 && currentIndex + 1 < _routeStops.length) {
        nextStop = _routeStops[currentIndex + 1];
      }
    }
    return (currentStop, nextStop);
  }

  void _evaluateDriverRideAlerts() {
    if (!_isDriver || !_notificationsEnabled || _routeRideRequests.isEmpty) {
      return;
    }

    final nextStop = _findStopById(_activeTrip?.nextStop ?? '');
    if (nextStop == null) return;

    for (final ride in _routeRideRequests) {
      final destinationStop = _findStopById(ride.destinationStopId);
      if (destinationStop == null) continue;
      if (destinationStop.order >= nextStop.order &&
          ride.status == RideStatus.waiting) {
        _addAlert(
          key: 'waiting_${ride.id}',
          alert: Alert(
            id: 'waiting_${ride.id}',
            title: AppStrings.translateForLanguage(
              _session?.language ?? 'English',
              'passenger_waiting_ahead',
            ),
            message: AppStrings.translateForLanguage(
              _session?.language ?? 'English',
              'passenger_waiting_message',
              params: {
                'passenger': ride.passengerName,
                'stop': destinationStop.name,
              },
            ),
            type: 'warning',
            timestamp: DateTime.now(),
          ),
        );
      }
    }
  }

  void _evaluateDriverMovementAlerts(double lat, double lng, double speed) {
    if (!_notificationsEnabled) return;
    final now = DateTime.now();

    if (_roadPoints.isNotEmpty) {
      final nearestDistance = _nearestRoadDistance(lat, lng);
      final shouldAlertDeviation =
          nearestDistance > 200 &&
          (_lastDeviationAlertAt == null ||
              now.difference(_lastDeviationAlertAt!) >=
                  _routeDeviationCooldown);

      if (shouldAlertDeviation) {
        _lastDeviationAlertAt = now;
        _addAlert(
          key: 'route_deviation_${now.millisecondsSinceEpoch}',
          alert: Alert(
            id: 'deviation_${now.millisecondsSinceEpoch}',
            title: AppStrings.translateForLanguage(
              _session?.language ?? 'English',
              'route_deviation',
            ),
            message: AppStrings.translateForLanguage(
              _session?.language ?? 'English',
              'route_deviation_message',
              params: {'distance': '${nearestDistance.round()}'},
            ),
            type: 'warning',
            timestamp: now,
          ),
        );
      }
    }

    final shouldWarnDelay =
        speed < 5 &&
        _tripElapsed.inMinutes >= 2 &&
        (_lastDelayAlertAt == null ||
            now.difference(_lastDelayAlertAt!) >= _delayWarningCooldown);
    if (shouldWarnDelay) {
      _lastDelayAlertAt = now;
      _addAlert(
        key: 'delay_$now',
        alert: Alert(
          id: 'delay_${now.millisecondsSinceEpoch}',
          title: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'delay_warning',
          ),
          message: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'delay_warning_message',
          ),
          type: 'warning',
          timestamp: now,
        ),
      );
    }
  }

  void _evaluatePassengerAlerts() {
    if (_isDriver || !_notificationsEnabled) return;

    final trackedBusId = _trackedBusId ?? _activeRide?.busId;
    final destination = _selectedDestination;
    if (trackedBusId == null || destination == null) return;

    final trackedBus = _liveBuses.cast<LiveBus?>().firstWhere(
      (bus) => bus?.busId == trackedBusId,
      orElse: () => null,
    );
    if (trackedBus == null) return;

    if (trackedBus.tripStatus == TripStatus.paused) {
      _addAlert(
        key: 'delay_passenger_$trackedBusId',
        alert: Alert(
          id: 'delay_passenger_$trackedBusId',
          title: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_delayed',
          ),
          message: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_delayed_message',
            params: {'busId': trackedBusId},
          ),
          type: 'warning',
          timestamp: DateTime.now(),
        ),
      );
    }

    final distanceToDestination =
        _remainingRouteDistanceToStop(
          from: LatLng(trackedBus.latitude, trackedBus.longitude),
          stop: destination,
        ) ??
        Geolocator.distanceBetween(
          trackedBus.latitude,
          trackedBus.longitude,
          destination.latitude,
          destination.longitude,
        );

    if (distanceToDestination <= 100) {
      _addAlert(
        key: 'approaching_${trackedBus.busId}_${destination.id}',
        alert: Alert(
          id: 'approaching_${trackedBus.busId}_${destination.id}',
          title: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_approaching_stop',
          ),
          message: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_approaching_message',
            params: {
              'busId': trackedBus.busId,
              'destination': destination.name,
            },
          ),
          type: 'info',
          timestamp: DateTime.now(),
        ),
      );
    }

    if (distanceToDestination <= 35) {
      _addAlert(
        key: 'arrival_${trackedBus.busId}_${destination.id}',
        alert: Alert(
          id: 'arrival_${trackedBus.busId}_${destination.id}',
          title: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_arrived',
          ),
          message: AppStrings.translateForLanguage(
            _session?.language ?? 'English',
            'bus_arrived_message',
            params: {
              'busId': trackedBus.busId,
              'destination': destination.name,
            },
          ),
          type: 'info',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<_ResolvedDestination?> _resolveDestination(String query) async {
    final localStop = _findStopByName(query);
    if (localStop != null) {
      return _ResolvedDestination(stop: localStop);
    }

    try {
      final geocoded = await locationFromAddress(query.trim());
      if (geocoded.isEmpty) return null;

      final target = geocoded.first;
      BusStop? nearest;
      var minDistance = double.infinity;
      for (final stop in _allStops) {
        final distance = Geolocator.distanceBetween(
          target.latitude,
          target.longitude,
          stop.latitude,
          stop.longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearest = stop;
        }
      }
      if (nearest == null || minDistance > 5000) {
        return null;
      }

      return _ResolvedDestination(
        stop: nearest,
        searchedPlacePosition: LatLng(target.latitude, target.longitude),
        searchedPlaceLabel: query.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  BusStop? _findStopByName(String query) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return null;

    BusStop? firstPrefixMatch;
    BusStop? firstContainsMatch;

    for (final stop in _allStops) {
      final stopName = _normalizeSearchText(stop.name);
      if (stopName == normalized) {
        return stop;
      }
      if (firstPrefixMatch == null && stopName.startsWith(normalized)) {
        firstPrefixMatch = stop;
      }
      if (firstContainsMatch == null && stopName.contains(normalized)) {
        firstContainsMatch = stop;
      }
    }

    return firstPrefixMatch ?? firstContainsMatch;
  }

  String _normalizeSearchText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  BusStop? _findStopById(String stopId) {
    if (stopId.isEmpty) return null;
    try {
      return _routeStops.firstWhere((stop) => stop.id == stopId);
    } catch (_) {}
    try {
      return _allStops.firstWhere((stop) => stop.id == stopId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchRoadPoints({required String routeId}) async {
    if (_routeStops.length < 2) {
      _roadPoints = [];
      return;
    }

    final memoryPath = _routePathCache[routeId];
    if (memoryPath != null && memoryPath.isNotEmpty) {
      _roadPoints = List<LatLng>.from(memoryPath);
      _cacheStopProgress(routeId);
      return;
    }

    final cachedPath = await _fs.fetchStoredRoutePath(routeId);
    if (cachedPath.isNotEmpty) {
      _roadPoints = cachedPath;
      _routePathCache[routeId] = List<LatLng>.from(cachedPath);
      _cacheStopProgress(routeId);
      return;
    }

    final result = await _routeEngine.fetchRoutePath(_routeStops);
    if (result != null && result.points.isNotEmpty) {
      _roadPoints = result.points;
      _routePathCache[routeId] = List<LatLng>.from(_roadPoints);
      await _fs.saveRoutePath(routeId, _roadPoints);
      _cacheStopProgress(routeId);
      return;
    }

    // Guaranteed fallback: connect the stored bus-stop coordinates directly.
    _roadPoints = _routeStops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();
    _routePathCache[routeId] = List<LatLng>.from(_roadPoints);
    _cacheStopProgress(routeId);
  }

  double _nearestRoadDistance(double lat, double lng) {
    if (_roadPoints.isEmpty) return 0;
    var minDistance = double.infinity;
    for (final point in _roadPoints) {
      final distance = Geolocator.distanceBetween(
        lat,
        lng,
        point.latitude,
        point.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  void _startTripTicker({required DateTime from}) {
    _tripTicker?.cancel();
    _tripElapsed = DateTime.now().difference(from);
    _tripTicker = Timer.periodic(_defaultTripTick, (_) {
      _tripElapsed = DateTime.now().difference(from);
      _notifyIfNeeded();
    });
  }

  void _rememberDriverPosition(
    double lat,
    double lng,
    double speed,
    double heading,
  ) {
    _lastDriverLat = lat;
    _lastDriverLng = lng;
    _lastDriverHeading = heading;
    _lastDriverSpeed = speed;
  }

  BusAccount? _findBusAccount(String busId) {
    try {
      return _allBusAccounts.firstWhere((bus) => bus.busNumber == busId);
    } catch (_) {
      return null;
    }
  }

  List<BusStop> _orderStopsForRoute(BusRoute? route, List<BusStop> stops) {
    final validStops = stops
        .where((stop) => stop.latitude != 0 || stop.longitude != 0)
        .toList();
    if (route == null || route.stops.isEmpty) {
      validStops.sort((a, b) => a.order.compareTo(b.order));
      return validStops;
    }

    final stopMap = {for (final stop in validStops) stop.id: stop};
    final ordered = route.stops
        .map((stopId) => stopMap[stopId])
        .whereType<BusStop>()
        .toList();
    final remaining =
        validStops.where((stop) => !route.stops.contains(stop.id)).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    ordered.addAll(remaining);
    return ordered;
  }

  void _cacheStopProgress(String routeId) {
    if (_roadPoints.isEmpty || _routeStops.isEmpty) return;

    final snappedStops = <BusStop>[];
    final progress = <String, int>{};

    for (final stop in _routeStops) {
      final nearestIndex = _findNearestIndex(
        _roadPoints,
        LatLng(stop.latitude, stop.longitude),
      );
      final snappedPoint = _roadPoints[nearestIndex];
      final snapDistance = Geolocator.distanceBetween(
        stop.latitude,
        stop.longitude,
        snappedPoint.latitude,
        snappedPoint.longitude,
      );

      progress[stop.id] = nearestIndex;
      if (snapDistance <= _maxStopSnapMeters) {
        snappedStops.add(
          BusStop(
            id: stop.id,
            name: stop.name,
            latitude: snappedPoint.latitude,
            longitude: snappedPoint.longitude,
            routeId: stop.routeId,
            order: stop.order,
          ),
        );
      } else {
        snappedStops.add(stop);
      }
    }

    _routeStops = snappedStops;
    _routeStopsCache[routeId] = List<BusStop>.from(snappedStops);
    _routeStopProgressCache[routeId] = progress;
  }

  double? _remainingRouteDistanceToStop({
    required LatLng from,
    required BusStop stop,
  }) {
    if (_roadPoints.length < 2) return null;
    final routeId = stop.routeId.isNotEmpty
        ? stop.routeId
        : (currentRouteId.isNotEmpty
              ? currentRouteId
              : (_session?.routeId ?? ''));
    final stopProgress = _routeStopProgressCache[routeId];
    final stopIndex = stopProgress?[stop.id];
    if (stopIndex == null) return null;

    final fromIndex = _findNearestIndex(_roadPoints, from);
    if (stopIndex <= fromIndex) {
      return Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        stop.latitude,
        stop.longitude,
      );
    }

    return _distanceAlongRoute(fromIndex, stopIndex);
  }

  double _distanceAlongRoute(int startIndex, int endIndex) {
    if (_roadPoints.length < 2) return 0;
    final boundedStart = startIndex.clamp(0, _roadPoints.length - 1);
    final boundedEnd = endIndex.clamp(0, _roadPoints.length - 1);
    if (boundedStart >= boundedEnd) return 0;

    var total = 0.0;
    for (var i = boundedStart; i < boundedEnd; i++) {
      total += Geolocator.distanceBetween(
        _roadPoints[i].latitude,
        _roadPoints[i].longitude,
        _roadPoints[i + 1].latitude,
        _roadPoints[i + 1].longitude,
      );
    }
    return total;
  }

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

  LatLng _snapLocationToRoute(double lat, double lng) {
    if (_roadPoints.isEmpty) {
      return LatLng(lat, lng);
    }
    return _routeEngine.snapToRoute(
      rawLocation: LatLng(lat, lng),
      routePoints: _roadPoints,
    );
  }

  Future<void> _syncRideTracking() async {
    final ride = _activeRide;
    final passengerPosition = _passengerPosition;
    if (ride == null || passengerPosition == null) return;

    final now = DateTime.now();
    if (_lastRideTrackingWriteAt != null &&
        now.difference(_lastRideTrackingWriteAt!) <
            _rideTrackingWriteInterval) {
      return;
    }

    double? distanceToBusMeters;
    try {
      final trackedBus = _liveBuses.firstWhere(
        (bus) => bus.busId == ride.busId,
      );
      distanceToBusMeters = Geolocator.distanceBetween(
        passengerPosition.latitude,
        passengerPosition.longitude,
        trackedBus.latitude,
        trackedBus.longitude,
      );
    } catch (_) {}

    final destinationStop = _findStopById(ride.destinationStopId);
    final distanceToDestinationMeters = destinationStop == null
        ? null
        : Geolocator.distanceBetween(
            passengerPosition.latitude,
            passengerPosition.longitude,
            destinationStop.latitude,
            destinationStop.longitude,
          );

    await _fs.updateRideTracking(
      rideId: ride.id,
      passengerLat: passengerPosition.latitude,
      passengerLng: passengerPosition.longitude,
      distanceToDestinationMeters: distanceToDestinationMeters,
      distanceToBusMeters: distanceToBusMeters,
    );
    _lastRideTrackingWriteAt = now;
  }

  Future<void> _loadRouteData(String routeId) async {
    if (routeId.isEmpty) {
      _routeStops = [];
      _roadPoints = [];
      return;
    }
    final cachedStops = _routeStopsCache[routeId];
    if (cachedStops != null && cachedStops.isNotEmpty) {
      _routeStops = List<BusStop>.from(cachedStops);
      final cachedPath = _routePathCache[routeId];
      if (cachedPath != null && cachedPath.isNotEmpty) {
        _roadPoints = List<LatLng>.from(cachedPath);
        _cacheStopProgress(routeId);
        return;
      }
      await _fetchRoadPoints(routeId: routeId);
      return;
    }

    final fetchedStops = await _fs.fetchStopsForRoute(routeId);
    final route = _allRoutes.cast<BusRoute?>().firstWhere(
      (candidate) => candidate?.id == routeId,
      orElse: () => null,
    );
    final orderedStops = _orderStopsForRoute(route, fetchedStops);
    for (final stop in orderedStops) {
      final existingIndex = _allStops.indexWhere(
        (candidate) => candidate.id == stop.id,
      );
      if (existingIndex >= 0) {
        _allStops[existingIndex] = stop;
      } else {
        _allStops.add(stop);
      }
    }
    _routeStopsCache[routeId] = List<BusStop>.from(orderedStops);
    _routeStops = orderedStops;
    await _fetchRoadPoints(routeId: routeId);
  }

  Future<bool> _pushDriverLiveLocation({
    required double lat,
    required double lng,
    required double speed,
    required double heading,
    required TripStatus status,
    bool force = false,
  }) async {
    if (_busAccount == null) return false;

    final snapped = _snapLocationToRoute(lat, lng);
    final snappedLat = snapped.latitude;
    final snappedLng = snapped.longitude;

    final now = DateTime.now();
    final statusChanged = _lastDriverSentStatus != status;
    final previousLat = _lastDriverLat;
    final previousLng = _lastDriverLng;
    final previousHeading = _lastDriverHeading;
    final previousSpeed = _lastDriverSpeed;

    _rememberDriverPosition(snappedLat, snappedLng, speed, heading);

    if (!force && !statusChanged && _lastDriverWriteAt != null) {
      final elapsed = now.difference(_lastDriverWriteAt!);
      final movedDistance = Geolocator.distanceBetween(
        previousLat,
        previousLng,
        snappedLat,
        snappedLng,
      );
      final headingDelta = _headingDelta(previousHeading, heading);
      final speedDelta = (speed - previousSpeed).abs();

      final hasMeaningfulChange =
          movedDistance >= _minDriverWriteDistanceMeters ||
          headingDelta >= _minDriverHeadingDelta ||
          speedDelta >= _minDriverSpeedDelta;

      if (elapsed < _driverWriteMinInterval && !hasMeaningfulChange) {
        return false;
      }
    }

    await _fs.upsertLiveBus(
      busId: _busAccount!.busNumber,
      lat: snappedLat,
      lng: snappedLng,
      speed: speed,
      heading: heading,
      status: status,
      rawLat: lat,
      rawLng: lng,
      routeId: currentRouteId,
      routeProgressIndex: _roadPoints.isEmpty
          ? null
          : _findNearestIndex(_roadPoints, snapped),
    );
    _lastDriverWriteAt = now;
    _lastDriverSentStatus = status;
    return true;
  }

  double _headingDelta(double from, double to) {
    final diff = (to - from).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  void _addAlert({required String key, required Alert alert}) {
    if (!_notificationsEnabled || _firedAlertKeys.contains(key)) return;
    _firedAlertKeys.add(key);
    _alerts.insert(0, alert);
    HapticFeedback.vibrate();
    _notifyIfNeeded();
  }

  bool get _notificationsEnabled => _session?.notificationsEnabled ?? true;

  void _resetSessionState() {
    _clearSubscriptions();
    _tripTicker?.cancel();
    _session = null;
    _isDriver = false;
    _busAccount = null;
    _activeTrip = null;
    _tripElapsed = Duration.zero;
    _routeStops = [];
    _roadPoints = [];
    _selectedDestination = null;
    _trackedBusId = null;
    _activeRide = null;
    _passengerPosition = null;
    _searchedPlacePosition = null;
    _searchedPlaceLabel = null;
    _routeStopProgressCache.clear();
    _routeRideRequests = [];
    _firedAlertKeys.clear();
    _lastDriverWriteAt = null;
    _lastDriverSentStatus = null;
    _lastRideTrackingWriteAt = null;
    _error = null;
  }

  void _clearSubscriptions() {
    _routeRideSub?.cancel();
    _routeRideSub = null;
    _passengerRideSub?.cancel();
    _passengerRideSub = null;
  }

  String _routeIdForBus(String busId) {
    try {
      final liveRouteId = _liveBuses
          .firstWhere((bus) => bus.busId == busId)
          .routeId;
      if (liveRouteId.isNotEmpty) {
        return liveRouteId;
      }
    } catch (_) {}

    try {
      return _allBusAccounts
          .firstWhere((bus) => bus.busNumber == busId)
          .resolvedCurrentRouteId;
    } catch (_) {
      return '';
    }
  }

  String _currentRouteIdForSession() {
    final activeTripRouteId = _activeTrip?.routeId ?? '';
    if (activeTripRouteId.isNotEmpty) return activeTripRouteId;
    final busRouteId = _busAccount?.resolvedCurrentRouteId ?? '';
    if (busRouteId.isNotEmpty) return busRouteId;
    return _session?.routeId ?? '';
  }

  String fallbackCurrentStopName() {
    if (_routeStops.isEmpty) return 'Unknown';
    if (_lastDriverLat != 0 || _lastDriverLng != 0) {
      return _resolveCurrentAndNextStops(
            _lastDriverLat,
            _lastDriverLng,
          ).$1?.name ??
          _routeStops.first.name;
    }
    return _routeStops.first.name;
  }

  String fallbackNextStopName() {
    if (_routeStops.isEmpty) return 'Unknown';
    if (_lastDriverLat != 0 || _lastDriverLng != 0) {
      final nextStop = _resolveCurrentAndNextStops(
        _lastDriverLat,
        _lastDriverLng,
      ).$2;
      if (nextStop != null) return nextStop.name;
    }
    if (_routeStops.length > 1) return _routeStops[1].name;
    return _routeStops.first.name;
  }

  Future<void> _subscribeDriverRideRequests(String routeId) async {
    await _routeRideSub?.cancel();
    _routeRideSub = null;
    if (routeId.isEmpty) return;
    _routeRideSub = _fs.streamWaitingRidesForRoute(routeId).listen((rides) {
      _routeRideRequests = rides;
      _evaluateDriverRideAlerts();
      _notifyIfNeeded();
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _notifyIfNeeded();
  }

  void _setError(String? message) {
    _error = message;
    _notifyIfNeeded();
  }

  void _notifyIfNeeded() {
    if (hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _liveBusSub?.cancel();
    _clearSubscriptions();
    _tripTicker?.cancel();
    super.dispose();
  }
}

class _ResolvedDestination {
  const _ResolvedDestination({
    required this.stop,
    this.searchedPlacePosition,
    this.searchedPlaceLabel,
  });

  final BusStop stop;
  final LatLng? searchedPlacePosition;
  final String? searchedPlaceLabel;
}
