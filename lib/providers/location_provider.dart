import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationProvider extends ChangeNotifier {
  Position? _currentPosition;
  bool _isLocationEnabled = false;
  bool _isLoading = false;
  String? _error;

  StreamSubscription<Position>? _positionSub;
  Timer? _throttleTimer;
  Function(double lat, double lng, double speed, double heading)? _onDriverUpdate;
  _LocationStreamMode _streamMode = _LocationStreamMode.none;

  // 3-second drive interval (as per USER requirement 2-3s)
  static const Duration _driverInterval = Duration(seconds: 3);

  Position? get currentPosition => _currentPosition;
  bool get isLocationEnabled => _isLocationEnabled;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isDriverStreaming => _streamMode == _LocationStreamMode.driver;
  bool get isPassengerStreaming => _streamMode == _LocationStreamMode.passenger;

  // ─────────────────────────────────────────
  // PERMISSION
  // ─────────────────────────────────────────

  Future<bool> requestLocationPermission() async {
    _setLoading(true);
    _clearError();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError('Location services are disabled. Enable them in settings.');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setError('Location permission denied.');
        return false;
      }

      _isLocationEnabled = true;
      notifyListeners();
      await _fetchCurrentPosition();
      return true;
    } catch (e) {
      _setError('Permission error: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> ensurePermissionAndPosition() async {
    if (!_isLocationEnabled) {
      await requestLocationPermission();
      return;
    }
    if (_currentPosition == null) {
      await _fetchCurrentPosition();
    }
  }

  Future<void> _fetchCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _currentPosition = pos;
      notifyListeners();
    } catch (e) {
      _setError('Could not get location: $e');
    }
  }

  // ─────────────────────────────────────────
  // PASSENGER — continuous stream (fast, for map updates)
  // ─────────────────────────────────────────

  void startPassengerLocationStream(
    void Function(double lat, double lng) onUpdate, {
    int distanceFilterMeters = 10,
  }) {
    if (!_isLocationEnabled) return;
    _positionSub?.cancel();
    _streamMode = _LocationStreamMode.passenger;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen((pos) {
      _currentPosition = pos;
      onUpdate(pos.latitude, pos.longitude);
      notifyListeners();
    });
  }

  // ─────────────────────────────────────────
  // DRIVER — throttled stream (every 5 seconds)
  // ─────────────────────────────────────────

  void startDriverLocationStream(
    void Function(double lat, double lng, double speed, double heading) onUpdate, {
    Duration interval = _driverInterval,
    int distanceFilterMeters = 5,
  }) {
    if (!_isLocationEnabled) return;
    _onDriverUpdate = onUpdate;
    _positionSub?.cancel();
    _throttleTimer?.cancel();
    _streamMode = _LocationStreamMode.driver;

    // Immediate first update
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilterMeters,
      ),
    ).listen((pos) {
      _currentPosition = pos;
      notifyListeners();
      // Position is buffered; only sent to Firestore by the 5-sec timer
    });

    // Timer fires periodically and sends latest position to Firestore
    _throttleTimer = Timer.periodic(interval, (_) {
      if (_currentPosition != null && _onDriverUpdate != null) {
        final speed = _currentPosition!.speed >= 0
            ? _currentPosition!.speed * 3.6 // m/s → km/h
            : 0.0;
        final heading = _currentPosition!.heading;
        _onDriverUpdate!(_currentPosition!.latitude, _currentPosition!.longitude, speed, heading);
      }
    });
  }

  void stopLocationStream() {
    _positionSub?.cancel();
    _positionSub = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _onDriverUpdate = null;
    _streamMode = _LocationStreamMode.none;
  }

  // ─────────────────────────────────────────
  // UTILITY
  // ─────────────────────────────────────────

  double? calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    try {
      return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    } catch (_) {
      return null;
    }
  }

  String formatDistance(double? meters) {
    if (meters == null) return 'Unknown';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _setError(String msg) {
    _error = msg;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  @override
  void dispose() {
    stopLocationStream();
    super.dispose();
  }
}

enum _LocationStreamMode { none, passenger, driver }
