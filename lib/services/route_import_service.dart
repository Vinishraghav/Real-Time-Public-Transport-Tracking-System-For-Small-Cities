import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/bus_models.dart';
import 'firestore_service.dart';
import 'route_engine_service.dart';

class ImportedRouteDefinition {
  const ImportedRouteDefinition({
    required this.route,
    required this.stops,
    required this.polylinePoints,
    required this.sourceUrl,
    required this.provider,
  });

  final BusRoute route;
  final List<BusStop> stops;
  final List<LatLng> polylinePoints;
  final String sourceUrl;
  final String provider;
}

class RouteImportService {
  RouteImportService({
    FirestoreService? firestoreService,
    RouteEngineService? routeEngineService,
  }) : _fs = firestoreService ?? FirestoreService(),
       _routeEngine = routeEngineService ?? RouteEngineService();

  final FirestoreService _fs;
  final RouteEngineService _routeEngine;

  Future<ImportedRouteDefinition> importFromGoogleMapsShareLink({
    required String shareLink,
    required String routeId,
    required String routeName,
    required String direction,
    required List<BusStop> stops,
    String? startName,
    String? endName,
  }) async {
    final resolved = await _routeEngine.resolveGoogleMapsShareLink(shareLink);
    if (resolved == null) {
      throw Exception('Unable to resolve Google Maps share link.');
    }

    final path = await _routeEngine.fetchRoutePathBetweenPoints(
      origin: resolved.origin,
      destination: resolved.destination,
      waypoints: resolved.waypoints,
    );
    if (path == null || path.points.isEmpty) {
      throw Exception('Unable to generate a route polyline from the share link.');
    }

    final orderedStops = _prepareStops(
      routeId: routeId,
      polylinePoints: path.points,
      suppliedStops: stops,
      startName: startName,
      endName: endName,
      origin: resolved.origin,
      destination: resolved.destination,
    );

    await _fs.saveRouteDefinition(
      routeId: routeId,
      routeName: routeName,
      startName: startName ?? orderedStops.first.name,
      endName: endName ?? orderedStops.last.name,
      direction: direction,
      stops: orderedStops,
      polylinePoints: path.points,
    );

    return ImportedRouteDefinition(
      route: BusRoute(
        id: routeId,
        routeName: routeName,
        startStop: orderedStops.first.id,
        endStop: orderedStops.last.id,
        startName: startName ?? orderedStops.first.name,
        endName: endName ?? orderedStops.last.name,
        direction: direction,
        stops: orderedStops.map((stop) => stop.id).toList(),
        polylinePoints: path.points
            .map((point) => {'lat': point.latitude, 'lng': point.longitude})
            .toList(),
      ),
      stops: orderedStops,
      polylinePoints: path.points,
      sourceUrl: resolved.resolvedUri.toString(),
      provider: path.provider,
    );
  }

  List<BusStop> _prepareStops({
    required String routeId,
    required List<LatLng> polylinePoints,
    required List<BusStop> suppliedStops,
    required LatLng origin,
    required LatLng destination,
    String? startName,
    String? endName,
  }) {
    final manualStops = suppliedStops.isEmpty
        ? [
            BusStop(
              id: '${routeId}_start',
              name: startName ?? 'Start',
              latitude: origin.latitude,
              longitude: origin.longitude,
              routeId: routeId,
              order: 0,
            ),
            BusStop(
              id: '${routeId}_end',
              name: endName ?? 'End',
              latitude: destination.latitude,
              longitude: destination.longitude,
              routeId: routeId,
              order: 1,
            ),
          ]
        : suppliedStops
              .map(
                (stop) => BusStop(
                  id: stop.id,
                  name: stop.name,
                  latitude: stop.latitude,
                  longitude: stop.longitude,
                  routeId: routeId,
                  order: stop.order,
                ),
              )
              .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

    return manualStops
        .asMap()
        .entries
        .map((entry) {
          final stop = entry.value;
          final snapped = _snapStopToPolyline(stop, polylinePoints);
          return BusStop(
            id: stop.id,
            name: stop.name,
            latitude: snapped.latitude,
            longitude: snapped.longitude,
            routeId: routeId,
            order: entry.key,
          );
        })
        .toList();
  }

  LatLng _snapStopToPolyline(BusStop stop, List<LatLng> polylinePoints) {
    if (polylinePoints.isEmpty) {
      return LatLng(stop.latitude, stop.longitude);
    }

    var nearestPoint = polylinePoints.first;
    var minDistance = double.infinity;
    for (final point in polylinePoints) {
      final distance = Geolocator.distanceBetween(
        stop.latitude,
        stop.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = point;
      }
    }
    return nearestPoint;
  }
}
