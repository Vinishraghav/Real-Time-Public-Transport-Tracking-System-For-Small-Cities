import 'dart:convert';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/bus_models.dart';

class RoutePathResult {
  const RoutePathResult({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
    required this.provider,
  });

  final List<LatLng> points;
  final int? distanceMeters;
  final int? durationSeconds;
  final String provider;
}

class ResolvedGoogleMapsRoute {
  const ResolvedGoogleMapsRoute({
    required this.shareUri,
    required this.resolvedUri,
    required this.origin,
    required this.destination,
    this.waypoints = const [],
  });

  final Uri shareUri;
  final Uri resolvedUri;
  final LatLng origin;
  final LatLng destination;
  final List<LatLng> waypoints;
}

class RouteEngineService {
  static const String _googleDirectionsKey = String.fromEnvironment(
    'GOOGLE_DIRECTIONS_API_KEY',
  );

  Future<RoutePathResult?> fetchRoutePath(List<BusStop> stops) async {
    if (stops.length < 2) return null;

    final google = await _fetchGoogleDirectionsFromStops(stops);
    if (google != null && google.points.isNotEmpty) {
      return google;
    }

    final osrm = await _fetchOsrmDirectionsFromStops(stops);
    if (osrm != null && osrm.points.isNotEmpty) {
      return osrm;
    }

    return null;
  }

  Future<RoutePathResult?> fetchRoutePathBetweenPoints({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final google = await _fetchGoogleDirections(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );
    if (google != null && google.points.isNotEmpty) {
      return google;
    }

    final osrm = await _fetchOsrmDirections(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
    );
    if (osrm != null && osrm.points.isNotEmpty) {
      return osrm;
    }

    return null;
  }

  Future<ResolvedGoogleMapsRoute?> resolveGoogleMapsShareLink(
    String shareLink,
  ) async {
    final trimmed = shareLink.trim();
    if (trimmed.isEmpty) return null;

    final shareUri = Uri.tryParse(trimmed);
    if (shareUri == null) return null;

    try {
      final response = await http.get(
        shareUri,
        headers: const {
          'User-Agent': 'CityBusLive/1.0',
        },
      );
      final resolvedUri = response.request?.url ?? shareUri;
      final parsed = _extractRoutePointsFromUri(resolvedUri);
      if (parsed == null) return null;

      return ResolvedGoogleMapsRoute(
        shareUri: shareUri,
        resolvedUri: resolvedUri,
        origin: parsed.$1,
        destination: parsed.$2,
        waypoints: parsed.$3,
      );
    } catch (_) {
      final parsed = _extractRoutePointsFromUri(shareUri);
      if (parsed == null) return null;
      return ResolvedGoogleMapsRoute(
        shareUri: shareUri,
        resolvedUri: shareUri,
        origin: parsed.$1,
        destination: parsed.$2,
        waypoints: parsed.$3,
      );
    }
  }

  LatLng snapToRoute({
    required LatLng rawLocation,
    required List<LatLng> routePoints,
  }) {
    if (routePoints.isEmpty) return rawLocation;
    if (routePoints.length == 1) return routePoints.first;

    var bestPoint = routePoints.first;
    var bestDistanceSquared = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projected = _projectPointOnSegment(
        rawLocation,
        routePoints[i],
        routePoints[i + 1],
      );
      final distanceSquared = _distanceSquared(rawLocation, projected);
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestPoint = projected;
      }
    }

    return bestPoint;
  }

  Future<RoutePathResult?> _fetchGoogleDirectionsFromStops(
    List<BusStop> stops,
  ) {
    return _fetchGoogleDirections(
      origin: LatLng(stops.first.latitude, stops.first.longitude),
      destination: LatLng(stops.last.latitude, stops.last.longitude),
      waypoints: stops
          .sublist(1, stops.length - 1)
          .map((stop) => LatLng(stop.latitude, stop.longitude))
          .toList(),
    );
  }

  Future<RoutePathResult?> _fetchGoogleDirections({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    if (_googleDirectionsKey.isEmpty) return null;

    try {
      final originValue = '${origin.latitude},${origin.longitude}';
      final destinationValue = '${destination.latitude},${destination.longitude}';
      var waypointQuery = '';

      if (waypoints.isNotEmpty) {
        final waypointList = waypoints
            .map((point) => '${point.latitude},${point.longitude}')
            .join('|');
        waypointQuery = '&waypoints=optimize:false|$waypointList';
      }

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${Uri.encodeComponent(originValue)}'
        '&destination=${Uri.encodeComponent(destinationValue)}'
        '$waypointQuery'
        '&mode=driving'
        '&key=$_googleDirectionsKey',
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final routes = data['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final encoded = ((route['overview_polyline'] as Map<String, dynamic>?) ??
              const {})['points'] as String?;
      if (encoded == null || encoded.isEmpty) return null;

      final legs = route['legs'] as List<dynamic>? ?? const [];
      final distanceMeters = legs.fold<int>(
        0,
        (sum, leg) =>
            sum +
            ((((leg as Map<String, dynamic>)['distance']
                            as Map<String, dynamic>?)?['value']
                        as num?)
                    ?.round() ??
                0),
      );
      final durationSeconds = legs.fold<int>(
        0,
        (sum, leg) =>
            sum +
            ((((leg as Map<String, dynamic>)['duration']
                            as Map<String, dynamic>?)?['value']
                        as num?)
                    ?.round() ??
                0),
      );

      final points = PolylinePoints.decodePolyline(encoded)
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
      if (points.isEmpty) return null;

      return RoutePathResult(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        provider: 'google_directions',
      );
    } catch (_) {
      return null;
    }
  }

  Future<RoutePathResult?> _fetchOsrmDirectionsFromStops(List<BusStop> stops) {
    return _fetchOsrmDirections(
      origin: LatLng(stops.first.latitude, stops.first.longitude),
      destination: LatLng(stops.last.latitude, stops.last.longitude),
      waypoints: stops
          .sublist(1, stops.length - 1)
          .map((stop) => LatLng(stop.latitude, stop.longitude))
          .toList(),
    );
  }

  Future<RoutePathResult?> _fetchOsrmDirections({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    try {
      final coordinates = [origin, ...waypoints, destination]
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$coordinates?overview=full&geometries=polyline',
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      final routes = data['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final encoded = route['geometry'] as String?;
      if (encoded == null || encoded.isEmpty) return null;

      final points = PolylinePoints.decodePolyline(encoded)
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
      if (points.isEmpty) return null;

      return RoutePathResult(
        points: points,
        distanceMeters: (route['distance'] as num?)?.round(),
        durationSeconds: (route['duration'] as num?)?.round(),
        provider: 'osrm',
      );
    } catch (_) {
      return null;
    }
  }

  LatLng _projectPointOnSegment(LatLng point, LatLng start, LatLng end) {
    final startX = start.longitude;
    final startY = start.latitude;
    final endX = end.longitude;
    final endY = end.latitude;
    final pointX = point.longitude;
    final pointY = point.latitude;

    final segmentX = endX - startX;
    final segmentY = endY - startY;
    final segmentLengthSquared =
        (segmentX * segmentX) + (segmentY * segmentY);

    if (segmentLengthSquared == 0) return start;

    final t = (((pointX - startX) * segmentX) +
                ((pointY - startY) * segmentY)) /
            segmentLengthSquared;
    final clampedT = t.clamp(0.0, 1.0);

    return LatLng(
      startY + (segmentY * clampedT),
      startX + (segmentX * clampedT),
    );
  }

  double _distanceSquared(LatLng a, LatLng b) {
    final dx = a.longitude - b.longitude;
    final dy = a.latitude - b.latitude;
    return (dx * dx) + (dy * dy);
  }

  (LatLng, LatLng, List<LatLng>)? _extractRoutePointsFromUri(Uri uri) {
    final queryOrigin = _parsePointString(
      uri.queryParameters['origin'] ?? uri.queryParameters['saddr'],
    );
    final queryDestination = _parsePointString(
      uri.queryParameters['destination'] ?? uri.queryParameters['daddr'],
    );

    final waypointValues =
        uri.queryParameters['waypoints']?.split('|') ?? const <String>[];
    final queryWaypoints = waypointValues
        .map(_parsePointString)
        .whereType<LatLng>()
        .toList();

    if (queryOrigin != null && queryDestination != null) {
      return (queryOrigin, queryDestination, queryWaypoints);
    }

    final extracted = <LatLng>[];
    final pairRegex = RegExp(r'(-?\d+\.\d+),\s*(-?\d+\.\d+)');
    for (final match in pairRegex.allMatches(uri.toString())) {
      final point = _parsePointString('${match.group(1)},${match.group(2)}');
      if (point != null && !_containsPoint(extracted, point)) {
        extracted.add(point);
      }
    }

    final dataRegex = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)');
    for (final match in dataRegex.allMatches(uri.toString())) {
      final point = _parsePointString('${match.group(1)},${match.group(2)}');
      if (point != null && !_containsPoint(extracted, point)) {
        extracted.add(point);
      }
    }

    if (extracted.length < 2) return null;
    return (
      extracted.first,
      extracted.last,
      extracted.length > 2
          ? extracted.sublist(1, extracted.length - 1)
          : const <LatLng>[],
    );
  }

  LatLng? _parsePointString(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split(',');
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  bool _containsPoint(List<LatLng> points, LatLng candidate) {
    for (final point in points) {
      if ((point.latitude - candidate.latitude).abs() < 0.000001 &&
          (point.longitude - candidate.longitude).abs() < 0.000001) {
        return true;
      }
    }
    return false;
  }
}
