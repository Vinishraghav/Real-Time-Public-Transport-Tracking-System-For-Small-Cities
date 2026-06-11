import 'package:cloud_firestore/cloud_firestore.dart';

enum TripStatus { active, paused, ended, notStarted }

// ─────────────────────────────────────────────
// BusRoute  (Firestore: "routes")
// ─────────────────────────────────────────────
class BusRoute {
  final String id; // route_id (doc id)
  final String routeName;
  final String startStop; // stop_id
  final String endStop; // stop_id
  final String startName;
  final String endName;
  final String direction;
  final List<String> stops; // ordered stop_ids
  final List<Map<String, double>> polylinePoints;

  const BusRoute({
    required this.id,
    required this.routeName,
    required this.startStop,
    required this.endStop,
    this.startName = '',
    this.endName = '',
    this.direction = '',
    required this.stops,
    this.polylinePoints = const [],
  });

  factory BusRoute.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final startStop =
        d['start_stop'] ?? d['start_point'] ?? d['start_name'] ?? '';
    final endStop = d['end_stop'] ?? d['end_point'] ?? d['end_name'] ?? '';
    final rawPolyline =
        d['polyline_points'] ?? d['route_polyline'] ?? d['points'] ?? const [];
    return BusRoute(
      id: doc.id,
      routeName: d['route_name'] ?? d['name'] ?? '',
      startStop: startStop is String ? startStop : '',
      endStop: endStop is String ? endStop : '',
      startName: (d['start_name'] ?? d['start_stop'] ?? d['start_point'] ?? '')
          as String? ??
          '',
      endName:
          (d['end_name'] ?? d['end_stop'] ?? d['end_point'] ?? '') as String? ??
          '',
      direction: d['direction'] as String? ?? '',
      stops: List<String>.from(d['stops'] ?? []),
      polylinePoints: (rawPolyline as List<dynamic>)
          .map((point) => Map<String, dynamic>.from(point as Map))
          .map(
            (point) => <String, double>{
              'lat': (point['lat'] as num?)?.toDouble() ??
                  (point['latitude'] as num?)?.toDouble() ??
                  0,
              'lng': (point['lng'] as num?)?.toDouble() ??
                  (point['longitude'] as num?)?.toDouble() ??
                  0,
            },
          )
          .where((point) => point['lat'] != 0 || point['lng'] != 0)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'route_name': routeName,
    'start_stop': startStop,
    'end_stop': endStop,
    'start_name': startName,
    'end_name': endName,
    'direction': direction,
    'stops': stops,
    'polyline_points': polylinePoints,
  };
}

// ─────────────────────────────────────────────
// BusStop  (Firestore: "stops")
// ─────────────────────────────────────────────
class BusStop {
  final String id;      // stop_id (doc id)
  final String name;
  final double latitude;
  final double longitude;
  final String routeId;
  final int order;

  const BusStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.routeId = '',
    this.order = 0,
  });

  factory BusStop.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BusStop(
      id: doc.id,
      name: d['stop_name'] ?? d['name'] ?? '',
      latitude:
          (d['latitude'] as num?)?.toDouble() ??
          (d['lat'] as num?)?.toDouble() ??
          0.0,
      longitude:
          (d['longitude'] as num?)?.toDouble() ??
          (d['lng'] as num?)?.toDouble() ??
          0.0,
      routeId: d['route_id'] ?? '',
      order:
          (d['order'] as num?)?.toInt() ??
          (d['order_index'] as num?)?.toInt() ??
          0,
    );
  }

  factory BusStop.fromMap(String id, Map<String, dynamic> d) => BusStop(
    id: id,
    name: d['stop_name'] ?? d['name'] ?? '',
    latitude:
        (d['latitude'] as num?)?.toDouble() ??
        (d['lat'] as num?)?.toDouble() ??
        0.0,
    longitude:
        (d['longitude'] as num?)?.toDouble() ??
        (d['lng'] as num?)?.toDouble() ??
        0.0,
    routeId: d['route_id'] ?? '',
    order:
        (d['order'] as num?)?.toInt() ??
        (d['order_index'] as num?)?.toInt() ??
        0,
  );

  Map<String, dynamic> toMap() => {
    'stop_name': name,
    'latitude': latitude,
    'longitude': longitude,
    'route_id': routeId,
    'order': order,
  };
}

// ─────────────────────────────────────────────
// BusAccount  (Firestore: "buses")
// ─────────────────────────────────────────────
class BusAccount {
  final String id; // bus_id (doc id)
  final String busNumber; // e.g. TN38AB1234
  final String routeId;
  final String forwardRouteId;
  final String returnRouteId;
  final String currentRouteId;
  final String status; // "active" | "inactive"
  final String tripStatus;

  const BusAccount({
    required this.id,
    required this.busNumber,
    required this.routeId,
    this.forwardRouteId = '',
    this.returnRouteId = '',
    this.currentRouteId = '',
    required this.status,
    this.tripStatus = 'notStarted',
  });

  factory BusAccount.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BusAccount(
      id: doc.id,
      busNumber: d['bus_number'] ?? '',
      routeId: d['route_id'] ?? '',
      forwardRouteId: d['forward_route_id'] as String? ?? '',
      returnRouteId: d['return_route_id'] as String? ?? '',
      currentRouteId: d['current_route_id'] as String? ?? '',
      status: d['status'] ?? 'inactive',
      tripStatus: d['trip_status'] as String? ?? 'notStarted',
    );
  }

  List<String> get availableRouteIds {
    final seen = <String>{};
    final routeIds = <String>[];
    for (final routeId in [
      currentRouteId,
      forwardRouteId,
      returnRouteId,
      routeId,
    ]) {
      if (routeId.isEmpty || !seen.add(routeId)) continue;
      routeIds.add(routeId);
    }
    return routeIds;
  }

  String get resolvedCurrentRouteId {
    if (currentRouteId.isNotEmpty) return currentRouteId;
    if (forwardRouteId.isNotEmpty) return forwardRouteId;
    if (routeId.isNotEmpty) return routeId;
    return returnRouteId;
  }

  BusAccount copyWith({
    String? routeId,
    String? forwardRouteId,
    String? returnRouteId,
    String? currentRouteId,
    String? status,
    String? tripStatus,
  }) {
    return BusAccount(
      id: id,
      busNumber: busNumber,
      routeId: routeId ?? this.routeId,
      forwardRouteId: forwardRouteId ?? this.forwardRouteId,
      returnRouteId: returnRouteId ?? this.returnRouteId,
      currentRouteId: currentRouteId ?? this.currentRouteId,
      status: status ?? this.status,
      tripStatus: tripStatus ?? this.tripStatus,
    );
  }
}

// ─────────────────────────────────────────────
// LiveBus  (Firestore: "live_buses")
// ─────────────────────────────────────────────
class LiveBus {
  final String busId;
  final double latitude;
  final double longitude;
  final double rawLatitude;
  final double rawLongitude;
  final double speed;          // km/h
  final double heading;        // direction in degrees
  final DateTime lastUpdated;
  final TripStatus tripStatus;
  final String routeId;
  final int? routeProgressIndex;
  final String connectionStatus;

  const LiveBus({
    required this.busId,
    required this.latitude,
    required this.longitude,
    this.rawLatitude = 0,
    this.rawLongitude = 0,
    required this.speed,
    required this.heading,
    required this.lastUpdated,
    required this.tripStatus,
    this.routeId = '',
    this.routeProgressIndex,
    this.connectionStatus = 'online',
  });

  factory LiveBus.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final latitude = (d['latitude'] as num?)?.toDouble() ?? 0.0;
    final longitude = (d['longitude'] as num?)?.toDouble() ?? 0.0;
    return LiveBus(
      busId: doc.id,
      latitude: latitude,
      longitude: longitude,
      rawLatitude: (d['raw_latitude'] as num?)?.toDouble() ?? latitude,
      rawLongitude: (d['raw_longitude'] as num?)?.toDouble() ?? longitude,
      speed: (d['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (d['heading'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: (d['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      tripStatus: _parseTripStatus(d['trip_status'] as String?),
      routeId: d['route_id'] as String? ?? '',
      routeProgressIndex: (d['route_progress_index'] as num?)?.toInt(),
      connectionStatus: d['connection_status'] as String? ?? 'online',
    );
  }

  static TripStatus _parseTripStatus(String? s) {
    switch (s) {
      case 'active': return TripStatus.active;
      case 'paused': return TripStatus.paused;
      case 'ended':  return TripStatus.ended;
      default:       return TripStatus.notStarted;
    }
  }

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'raw_latitude': rawLatitude,
    'raw_longitude': rawLongitude,
    'speed': speed,
    'heading': heading,
    'last_updated': FieldValue.serverTimestamp(),
    'trip_status': tripStatus.name,
    'route_id': routeId,
    'route_progress_index': routeProgressIndex,
    'connection_status': connectionStatus,
  };
}

// ─────────────────────────────────────────────
// Trip  (Firestore: "trips")
// ─────────────────────────────────────────────
class Trip {
  final String id;        // trip_id (doc id)
  final String busId;
  final String routeId;
  final DateTime startTime;
  final DateTime? endTime;
  final String currentStop;
  final String nextStop;

  const Trip({
    required this.id,
    required this.busId,
    required this.routeId,
    required this.startTime,
    this.endTime,
    required this.currentStop,
    required this.nextStop,
  });

  factory Trip.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Trip(
      id: doc.id,
      busId: d['bus_id'] ?? '',
      routeId: d['route_id'] ?? '',
      startTime: (d['start_time'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (d['end_time'] as Timestamp?)?.toDate(),
      currentStop: d['current_stop'] ?? '',
      nextStop: d['next_stop'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────
// Alert  (local only – proximity detection)
// ─────────────────────────────────────────────
class Alert {
  final String id;
  final String title;
  final String message;
  final String type; // 'info' | 'warning' | 'error'
  final DateTime timestamp;
  bool isRead;

  Alert({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });
}

