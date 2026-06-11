import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bus_models.dart';
import '../models/ride_models.dart';

/// Central service for all Firestore read/write operations.
/// UI layers must never call Firestore directly — use this service.
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._();
  factory FirestoreService() => _instance;
  FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────
  // BUS ACCOUNT  (collection: buses)
  // ─────────────────────────────────────────

  /// Login: find bus document by bus_number field.
  Future<BusAccount?> loginWithBusNumber(String busNumber) async {
    final snap = await _db
        .collection('buses')
        .where('bus_number', isEqualTo: busNumber.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return BusAccount.fromDoc(snap.docs.first);
  }

  Future<BusAccount?> fetchBusAccountByNumber(String busNumber) async {
    final snap = await _db
        .collection('buses')
        .where('bus_number', isEqualTo: busNumber.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return BusAccount.fromDoc(snap.docs.first);
  }

  Future<void> assignBusRoutes({
    required String busId,
    required String forwardRouteId,
    required String returnRouteId,
    String? currentRouteId,
    String? tripStatus,
  }) {
    final selectedRouteId = currentRouteId?.isNotEmpty == true
        ? currentRouteId!
        : forwardRouteId;
    return _db.collection('buses').doc(busId).set({
      'forward_route_id': forwardRouteId,
      'return_route_id': returnRouteId,
      'current_route_id': selectedRouteId,
      'route_id': selectedRouteId,
      if (tripStatus != null) 'trip_status': tripStatus,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateBusCurrentRoute({
    required String busId,
    required String routeId,
    String? tripStatus,
  }) {
    return _db.collection('buses').doc(busId).set({
      'current_route_id': routeId,
      'route_id': routeId,
      if (tripStatus != null) 'trip_status': tripStatus,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─────────────────────────────────────────
  // ROUTES  (collection: routes)
  // ─────────────────────────────────────────

  Future<List<BusRoute>> fetchAllRoutes() async {
    final snap = await _db.collection('routes').get();
    return snap.docs.map(BusRoute.fromDoc).toList();
  }

  Future<BusRoute?> fetchRoute(String routeId) async {
    final doc = await _db.collection('routes').doc(routeId).get();
    if (!doc.exists) return null;
    return BusRoute.fromDoc(doc);
  }

  // ─────────────────────────────────────────
  // STOPS  (collection: stops)
  // ─────────────────────────────────────────

  Future<List<BusStop>> fetchAllStops() async {
    final snap = await _db.collection('stops').get();
    return snap.docs.map(BusStop.fromDoc).toList();
  }

  Future<BusStop?> fetchStop(String stopId) async {
    final doc = await _db.collection('stops').doc(stopId).get();
    if (!doc.exists) return null;
    return BusStop.fromDoc(doc);
  }

  Future<List<BusStop>> fetchStopsForRoute(String routeId) async {
    final snap = await _db
        .collection('stops')
        .where('route_id', isEqualTo: routeId)
        .get();
    final directStops = snap.docs.map(BusStop.fromDoc).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (directStops.isNotEmpty) {
      return directStops;
    }

    final route = await fetchRoute(routeId);
    if (route == null || route.stops.isEmpty) {
      return const [];
    }

    final orderedStops = <BusStop>[];
    for (final stopId in route.stops) {
      final stop = await fetchStop(stopId);
      if (stop == null) continue;
      orderedStops.add(
        BusStop(
          id: stop.id,
          name: stop.name,
          latitude: stop.latitude,
          longitude: stop.longitude,
          routeId: routeId,
          order: stop.order,
        ),
      );
    }

    orderedStops.sort((a, b) => a.order.compareTo(b.order));
    return orderedStops;
  }

  // ─────────────────────────────────────────
  // ALL BUS ACCOUNTS  (collection: buses)
  // ─────────────────────────────────────────

  Future<List<BusAccount>> fetchAllBuses() async {
    final snap = await _db.collection('buses').get();
    return snap.docs.map(BusAccount.fromDoc).toList();
  }

  Future<Map<String, String>> fetchDriverNamesByBusIds(List<String> busIds) async {
    if (busIds.isEmpty) return const {};

    final names = <String, String>{};
    for (final chunk in _chunk(busIds, 10)) {
      final snap = await _db
          .collection('drivers')
          .where('bus_number', whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final busNumber = data['bus_number'] as String?;
        if (busNumber != null && busNumber.isNotEmpty) {
          names[busNumber] = data['name'] as String? ?? 'Driver';
        }
      }
    }
    return names;
  }

  // ─────────────────────────────────────────
  // LIVE BUSES  (collection: live_buses)
  // ─────────────────────────────────────────

  /// Stream all active live_buses documents in real-time.
  Stream<List<LiveBus>> streamActiveLiveBuses() {
    return _db
        .collection('live_buses')
        .where('trip_status', whereIn: ['active', 'paused'])
        .snapshots()
        .map((s) => s.docs.map(LiveBus.fromDoc).toList());
  }

  /// Stream a single bus's live document.
  Stream<LiveBus?> streamLiveBus(String busId) {
    return _db
        .collection('live_buses')
        .doc(busId)
        .snapshots()
        .map((d) => d.exists ? LiveBus.fromDoc(d) : null);
  }

  Future<void> upsertLiveBus({
    required String busId,
    required double lat,
    required double lng,
    required double speed,
    required double heading,
    required TripStatus status,
    double? rawLat,
    double? rawLng,
    String? routeId,
    int? routeProgressIndex,
  }) {
    final connectionStatus = status == TripStatus.ended ? 'offline' : 'online';
    return _db.collection('live_buses').doc(busId).set({
      'bus_id': busId,
      'latitude': lat,
      'longitude': lng,
      if (rawLat != null) 'raw_latitude': rawLat,
      if (rawLng != null) 'raw_longitude': rawLng,
      'speed': speed,
      'heading': heading,
      'trip_status': status.name,
      if (routeId != null && routeId.isNotEmpty) 'route_id': routeId,
      if (routeProgressIndex != null) 'route_progress_index': routeProgressIndex,
      'connection_status': connectionStatus,
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<LatLng>> fetchStoredRoutePath(String routeId) async {
    final doc = await _db.collection('route_paths').doc(routeId).get();
    if (doc.exists) {
      final path = _decodePolylinePoints(
        doc.data()?['points'] as List<dynamic>? ?? const [],
      );
      if (path.isNotEmpty) return path;
    }

    final routeDoc = await _db.collection('routes').doc(routeId).get();
    if (!routeDoc.exists) return const [];
    final routeData = routeDoc.data() ?? <String, dynamic>{};
    return _decodePolylinePoints(
      routeData['route_polyline'] as List<dynamic>? ?? const [],
    );
  }

  Future<void> saveRoutePath(String routeId, List<LatLng> points) async {
    if (points.isEmpty) return;
    final serialized = points
        .map((point) => {
              'lat': point.latitude,
              'lng': point.longitude,
            })
        .toList();

    await _db.collection('route_paths').doc(routeId).set({
      'route_id': routeId,
      'points': serialized,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('routes').doc(routeId).set({
      'polyline_points': serialized,
      'route_polyline': serialized,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveRouteStops({
    required String routeId,
    required String routeName,
    required List<BusStop> stops,
    String? startName,
    String? endName,
    String direction = '',
    List<LatLng> polyline = const [],
  }) async {
    if (stops.isEmpty) return;
    final orderedStops = List<BusStop>.from(stops)
      ..sort((a, b) => a.order.compareTo(b.order));

    await _db.collection('routes').doc(routeId).set({
      'name': routeName,
      'route_name': routeName,
      'start_name': startName ?? orderedStops.first.name,
      'end_name': endName ?? orderedStops.last.name,
      'start_point': orderedStops.first.id,
      'end_point': orderedStops.last.id,
      'start_stop': orderedStops.first.id,
      'end_stop': orderedStops.last.id,
      'direction': direction,
      'stops': orderedStops.map((stop) => stop.id).toList(),
      if (polyline.isNotEmpty)
        'polyline_points': polyline
            .map((point) => {'lat': point.latitude, 'lng': point.longitude})
            .toList(),
      if (polyline.isNotEmpty)
        'route_polyline': polyline
            .map((point) => {'lat': point.latitude, 'lng': point.longitude})
            .toList(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final stop in orderedStops) {
      await _db.collection('stops').doc(stop.id).set({
        'name': stop.name,
        'stop_name': stop.name,
        'lat': stop.latitude,
        'lng': stop.longitude,
        'latitude': stop.latitude,
        'longitude': stop.longitude,
        'route_id': routeId,
        'order_index': stop.order,
        'order': stop.order,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveRouteDefinition({
    required String routeId,
    required String routeName,
    required String startName,
    required String endName,
    required String direction,
    required List<BusStop> stops,
    required List<LatLng> polylinePoints,
  }) async {
    await saveRouteStops(
      routeId: routeId,
      routeName: routeName,
      startName: startName,
      endName: endName,
      direction: direction,
      stops: stops,
      polyline: polylinePoints,
    );
    await saveRoutePath(routeId, polylinePoints);
  }

  // ─────────────────────────────────────────
  // TRIPS  (collection: trips)
  // ─────────────────────────────────────────

  Future<Trip> startTrip({
    required String busId,
    required String routeId,
    required String currentStop,
    required String nextStop,
  }) async {
    final ref = _db.collection('trips').doc();
    final data = {
      'trip_id': ref.id,
      'bus_id': busId,
      'route_id': routeId,
      'start_time': FieldValue.serverTimestamp(),
      'end_time': null,
      'current_stop': currentStop,
      'next_stop': nextStop,
    };
    await ref.set(data);
    return Trip(
      id: ref.id,
      busId: busId,
      routeId: routeId,
      startTime: DateTime.now(),
      currentStop: currentStop,
      nextStop: nextStop,
    );
  }

  Future<void> updateTripStops({
    required String tripId,
    required String currentStop,
    required String nextStop,
  }) {
    return _db.collection('trips').doc(tripId).update({
      'current_stop': currentStop,
      'next_stop': nextStop,
    });
  }

  Future<void> endTrip(String tripId) {
    return _db.collection('trips').doc(tripId).update({
      'end_time': FieldValue.serverTimestamp(),
    });
  }

  /// Get the most recent active trip for a bus.
  Future<Trip?> fetchActiveTripForBus(String busId) async {
    final snap = await _db
        .collection('trips')
        .where('bus_id', isEqualTo: busId)
        .where('end_time', isNull: true)
        .orderBy('start_time', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Trip.fromDoc(snap.docs.first);
  }

  Future<void> updateStopCoordinates(String stopId, double lat, double lng) async {
    await _db.collection('stops').doc(stopId).update({
      'latitude': lat,
      'longitude': lng,
    });
  }

  Stream<List<RideRequest>> streamWaitingRidesForRoute(String routeId) {
    return _db
        .collection('rides')
        .where('route_id', isEqualTo: routeId)
        .where('status', whereIn: ['waiting', 'boarded'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map(RideRequest.fromDoc).toList());
  }

  Stream<List<RideRequest>> streamPassengerRides(String passengerId) {
    return _db
        .collection('rides')
        .where('passenger_id', isEqualTo: passengerId)
        .where('status', whereIn: ['waiting', 'boarded'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map(RideRequest.fromDoc).toList());
  }

  Future<void> upsertRide({
    required String rideId,
    required String passengerId,
    required String passengerName,
    required String routeId,
    required String busId,
    required String destinationStopId,
    required String destinationStopName,
    double? passengerLat,
    double? passengerLng,
  }) async {
    await _db.collection('rides').doc(rideId).set({
      'passenger_id': passengerId,
      'passenger_name': passengerName,
      'route_id': routeId,
      'bus_id': busId,
      'destination_stop_id': destinationStopId,
      'destination_stop_name': destinationStopName,
      if (passengerLat != null) 'passenger_latitude': passengerLat,
      if (passengerLng != null) 'passenger_longitude': passengerLng,
      'status': 'waiting',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateRideTracking({
    required String rideId,
    required double passengerLat,
    required double passengerLng,
    double? distanceToDestinationMeters,
    double? distanceToBusMeters,
  }) {
    return _db.collection('rides').doc(rideId).set({
      'passenger_latitude': passengerLat,
      'passenger_longitude': passengerLng,
      if (distanceToDestinationMeters != null)
        'distance_to_destination_meters': distanceToDestinationMeters,
      if (distanceToBusMeters != null) 'distance_to_bus_meters': distanceToBusMeters,
      'last_tracked_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateRideStatus({
    required String rideId,
    required RideStatus status,
  }) {
    return _db.collection('rides').doc(rideId).set({
      'status': status.name,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<List<String>> _chunk(List<String> items, int size) {
    final chunks = <List<String>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ? i + size : items.length;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  List<LatLng> _decodePolylinePoints(List<dynamic> rawPoints) {
    return rawPoints
        .map((point) => Map<String, dynamic>.from(point as Map))
        .map(
          (point) => LatLng(
            (point['lat'] as num?)?.toDouble() ??
                (point['latitude'] as num?)?.toDouble() ??
                0,
            (point['lng'] as num?)?.toDouble() ??
                (point['longitude'] as num?)?.toDouble() ??
                0,
          ),
        )
        .where((point) => point.latitude != 0 || point.longitude != 0)
        .toList();
  }
}
