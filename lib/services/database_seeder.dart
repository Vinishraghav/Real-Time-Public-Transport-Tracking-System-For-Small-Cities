import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firestore_service.dart';
import 'route_engine_service.dart';
import '../models/bus_models.dart';

class DatabaseSeeder {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirestoreService _fs = FirestoreService();
  static final RouteEngineService _re = RouteEngineService();

  static Future<void> seedFirestore() async {
    debugPrint('STARTING seedFirestore()');
    try {
      // 1. Check if 'stops' collection is empty
      debugPrint('Checking stops collection...');
      final stopsSnap = await _db.collection('stops').limit(1).get();
      debugPrint('Stops count: ${stopsSnap.docs.length}');
      
      if (stopsSnap.docs.isNotEmpty) {
        debugPrint('Firestore already has data. Skipping seeding.');
        return;
      }

      debugPrint('No stops found. Starting Firestore Seeding...');

      // 2. Define Real Bus Stops (Mandatory list)
      final List<Map<String, dynamic>> rawStopsData = [
        {'id': 'stop_senjerimalai', 'name': 'Senjerimalai', 'lat': 10.8265, 'lng': 77.1932},
        {'id': 'stop_sri_eshwar', 'name': 'Sri Eshwar College', 'lat': 10.8242, 'lng': 77.0601},
        {'id': 'stop_kinathukadavu', 'name': 'Kinathukadavu', 'lat': 10.8174, 'lng': 77.0189},
      ];

      final List<BusStop> stops = rawStopsData.asMap().entries.map((entry) {
        final i = entry.key;
        final data = entry.value;
        return BusStop(
          id: data['id'],
          name: data['name'],
          latitude: data['lat'],
          longitude: data['lng'],
          order: i,
        );
      }).toList();

      // 3. Create Forward Route
      debugPrint('Creating Forward Route...');
      final forwardRouteId = 'route_cbe_f';
      final forwardPath = await _re.fetchRoutePath(stops);
      debugPrint('Forward Path points: ${forwardPath?.points.length ?? 0}');
      final forwardPoints = forwardPath?.points ?? stops.map((s) => LatLng(s.latitude, s.longitude)).toList();

      debugPrint('Saving Forward Route definition...');
      await _fs.saveRouteDefinition(
        routeId: forwardRouteId,
        routeName: 'Senjerimalai - Kinathukadavu (Forward)',
        startName: stops.first.name,
        endName: stops.last.name,
        direction: 'Forward',
        stops: stops,
        polylinePoints: forwardPoints,
      );

      // 4. Create Return Route
      debugPrint('Creating Return Route...');
      final returnRouteId = 'route_cbe_r';
      final returnStops = stops.reversed.toList().asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        return BusStop(
          id: s.id,
          name: s.name,
          latitude: s.latitude,
          longitude: s.longitude,
          order: i,
        );
      }).toList();

      final returnPath = await _re.fetchRoutePath(returnStops);
      debugPrint('Return Path points: ${returnPath?.points.length ?? 0}');
      final returnPoints = returnPath?.points ?? returnStops.map((s) => LatLng(s.latitude, s.longitude)).toList();

      debugPrint('Saving Return Route definition...');
      await _fs.saveRouteDefinition(
        routeId: returnRouteId,
        routeName: 'Kinathukadavu - Senjerimalai (Return)',
        startName: returnStops.first.name,
        endName: returnStops.last.name,
        direction: 'Return',
        stops: returnStops,
        polylinePoints: returnPoints,
      );

      // 5. Create Sample Bus (TN38AB1234)
      debugPrint('Creating Sample Bus...');
      await _db.collection('buses').doc('BUS_001').set({
        'bus_number': 'TN38AB1234',
        'forward_route_id': forwardRouteId,
        'return_route_id': returnRouteId,
        'current_route_id': forwardRouteId,
        'route_id': forwardRouteId,
        'trip_status': 'notStarted',
        'status': 'active',
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint('Firestore Seeding Completed Successfully!');
    } catch (e, stack) {
      debugPrint('Error Seeding Firestore: $e');
      debugPrint('Stack trace: $stack');
    }
  }
}
