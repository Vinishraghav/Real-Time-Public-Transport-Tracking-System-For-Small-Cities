import 'package:cloud_firestore/cloud_firestore.dart';

enum RideStatus { waiting, boarded, completed, cancelled }

class RideRequest {
  const RideRequest({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.routeId,
    required this.busId,
    required this.destinationStopId,
    required this.destinationStopName,
    required this.status,
    required this.createdAt,
    this.passengerLatitude,
    this.passengerLongitude,
    this.distanceToDestinationMeters,
    this.distanceToBusMeters,
    this.lastTrackedAt,
  });

  final String id;
  final String passengerId;
  final String passengerName;
  final String routeId;
  final String busId;
  final String destinationStopId;
  final String destinationStopName;
  final RideStatus status;
  final DateTime createdAt;
  final double? passengerLatitude;
  final double? passengerLongitude;
  final double? distanceToDestinationMeters;
  final double? distanceToBusMeters;
  final DateTime? lastTrackedAt;

  factory RideRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return RideRequest(
      id: doc.id,
      passengerId: data['passenger_id'] as String? ?? '',
      passengerName: data['passenger_name'] as String? ?? 'Passenger',
      routeId: data['route_id'] as String? ?? '',
      busId: data['bus_id'] as String? ?? '',
      destinationStopId: data['destination_stop_id'] as String? ?? '',
      destinationStopName: data['destination_stop_name'] as String? ?? '',
      status: _parseStatus(data['status'] as String?),
      createdAt:
          (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      passengerLatitude: (data['passenger_latitude'] as num?)?.toDouble(),
      passengerLongitude: (data['passenger_longitude'] as num?)?.toDouble(),
      distanceToDestinationMeters:
          (data['distance_to_destination_meters'] as num?)?.toDouble(),
      distanceToBusMeters: (data['distance_to_bus_meters'] as num?)?.toDouble(),
      lastTrackedAt: (data['last_tracked_at'] as Timestamp?)?.toDate(),
    );
  }

  static RideStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'boarded':
        return RideStatus.boarded;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
        return RideStatus.cancelled;
      default:
        return RideStatus.waiting;
    }
  }
}
