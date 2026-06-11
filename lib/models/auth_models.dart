enum UserRole { driver, passenger }

class AppSession {
  const AppSession({
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName,
    this.busNumber,
    this.routeId,
    this.driverId,
    this.notificationsEnabled = true,
    this.darkMode = false,
    this.dataSaver = false,
    this.language = 'English',
  });

  final String uid;
  final String email;
  final UserRole role;
  final String displayName;
  final String? busNumber;
  final String? routeId;
  final String? driverId;
  final bool notificationsEnabled;
  final bool darkMode;
  final bool dataSaver;
  final String language;

  bool get isDriver => role == UserRole.driver;

  AppSession copyWith({
    String? uid,
    String? email,
    UserRole? role,
    String? displayName,
    String? busNumber,
    String? routeId,
    String? driverId,
    bool? notificationsEnabled,
    bool? darkMode,
    bool? dataSaver,
    String? language,
  }) {
    return AppSession(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      busNumber: busNumber ?? this.busNumber,
      routeId: routeId ?? this.routeId,
      driverId: driverId ?? this.driverId,
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled,
      darkMode: darkMode ?? this.darkMode,
      dataSaver: dataSaver ?? this.dataSaver,
      language: language ?? this.language,
    );
  }
}
