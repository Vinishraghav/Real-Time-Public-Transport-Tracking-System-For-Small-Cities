import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final GoogleSignIn _googleSignIn;

  Stream<AppSession?> sessionChanges() async* {
    await for (final user in _auth.authStateChanges()) {
      if (user == null) {
        yield null;
      } else {
        yield await _loadSession(user);
      }
    }
  }

  Future<AppSession> signInDriver({
    required String busNumber,
    required String password,
  }) async {
    final normalizedBusNumber = busNumber.trim().toUpperCase();
    final driverProfile = await _resolveDriverProfile(normalizedBusNumber);
    final email = driverProfile.email;
    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-driver-email',
        message: 'Driver email is not configured in Firestore.',
      );
    }

    final credentials = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (driverProfile.driverDocId != null) {
      await _db.collection('drivers').doc(driverProfile.driverDocId).set({
        'bus_number': normalizedBusNumber,
        'email': email,
        'name': driverProfile.displayName,
        'route_id': driverProfile.routeId,
        'last_login_at': FieldValue.serverTimestamp(),
        'auth_uid': credentials.user!.uid,
      }, SetOptions(merge: true));
    }

    await _ensureUserDocument(
      uid: credentials.user!.uid,
      role: UserRole.driver,
      email: email,
      displayName: driverProfile.displayName,
      routeId: driverProfile.routeId,
      busNumber: normalizedBusNumber,
      driverId: driverProfile.driverDocId,
    );

    return _loadSession(credentials.user!);
  }

  Future<AppSession> signInPassenger({
    required String email,
    required String password,
  }) async {
    final credentials = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensurePassengerProfile(credentials.user!);
    return _loadSession(credentials.user!);
  }

  Future<AppSession> registerPassenger({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credentials = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credentials.user!.updateDisplayName(displayName.trim());
    await _ensureUserDocument(
      uid: credentials.user!.uid,
      role: UserRole.passenger,
      email: email.trim(),
      displayName: displayName.trim().isEmpty
          ? 'Passenger'
          : displayName.trim(),
    );
    return _loadSession(credentials.user!);
  }

  Future<AppSession> signInPassengerWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google Sign-In was cancelled.',
      );
    }

    final authData = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: authData.accessToken,
      idToken: authData.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await _ensurePassengerProfile(result.user!);
    return _loadSession(result.user!);
  }

  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  Future<AppSession?> currentSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _loadSession(user);
  }

  Future<void> updatePreferences({
    required String uid,
    bool? notificationsEnabled,
    bool? darkMode,
    bool? dataSaver,
    String? language,
    String? displayName,
  }) async {
    final payload = <String, dynamic>{
      if (notificationsEnabled != null)
        'notifications_enabled': notificationsEnabled,
      if (darkMode != null) 'theme': darkMode ? 'dark' : 'light',
      if (dataSaver != null) 'data_saver': dataSaver,
      if (language != null) 'language': language,
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (payload.length > 1) {
      await _db
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true));
    }
    await _cacheLocalPreferences(
      uid: uid,
      notificationsEnabled: notificationsEnabled,
      darkMode: darkMode,
      dataSaver: dataSaver,
      language: language,
      displayName: displayName,
    );
  }

  Future<AppSession> _loadSession(User user) async {
    try {
      final userRef = _db.collection('users').doc(user.uid);

      // Add timeout to prevent indefinite blocking
      final userDoc = await userRef.get().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Firestore read timeout', const Duration(seconds: 8));
        },
      );

      if (!userDoc.exists) {
        await _ensurePassengerProfile(user);
      }

      final refreshedDoc = await userRef.get().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Firestore read timeout', const Duration(seconds: 8));
        },
      );
      final data = refreshedDoc.data() ?? <String, dynamic>{};
      final role = (data['role'] as String?) == 'driver'
          ? UserRole.driver
          : UserRole.passenger;
      final localPrefs = await _readLocalPreferences(user.uid);

      return AppSession(
        uid: user.uid,
        email: data['email'] as String? ?? user.email ?? '',
        role: role,
        displayName:
            localPrefs.displayName ??
            data['display_name'] as String? ??
            user.displayName ??
            (role == UserRole.driver ? 'Driver' : 'Passenger'),
        busNumber: data['bus_number'] as String?,
        routeId: data['route_id'] as String?,
        driverId: data['driver_id'] as String?,
        notificationsEnabled:
            localPrefs.notificationsEnabled ??
            data['notifications_enabled'] as bool? ??
            true,
        darkMode:
            localPrefs.darkMode ??
            ((data['theme'] as String? ?? 'light') == 'dark'),
        dataSaver: localPrefs.dataSaver ?? data['data_saver'] as bool? ?? false,
        language: localPrefs.language ?? data['language'] as String? ?? 'English',
      );
    } catch (e) {
      // If any timeout or error occurs, create a minimal session
      return AppSession(
        uid: user.uid,
        email: user.email ?? '',
        role: UserRole.passenger,
        displayName: user.displayName ?? 'Passenger',
        notificationsEnabled: true,
        darkMode: false,
        dataSaver: false,
        language: 'English',
      );
    }
  }

  Future<void> _ensurePassengerProfile(User user) {
    return _ensureUserDocument(
      uid: user.uid,
      role: UserRole.passenger,
      email: user.email ?? '',
      displayName: user.displayName ?? 'Passenger',
    );
  }

  Future<void> _ensureUserDocument({
    required String uid,
    required UserRole role,
    required String email,
    required String displayName,
    String? routeId,
    String? busNumber,
    String? driverId,
  }) async {
    await _db.collection('users').doc(uid).set({
      'email': email,
      'display_name': displayName,
      'role': role.name,
      'route_id': routeId,
      'bus_number': busNumber,
      'driver_id': driverId,
      'notifications_enabled': true,
      'theme': 'light',
      'data_saver': false,
      'language': 'English',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<_DriverProfile> _resolveDriverProfile(String busNumber) async {
    final driverSnap = await _db
        .collection('drivers')
        .where('bus_number', isEqualTo: busNumber)
        .limit(1)
        .get();
    if (driverSnap.docs.isNotEmpty) {
      final doc = driverSnap.docs.first;
      final data = doc.data();
      return _DriverProfile(
        driverDocId: doc.id,
        email: (data['email'] as String? ?? '').trim(),
        displayName: (data['name'] as String? ?? 'Driver').trim(),
        routeId: (data['route_id'] as String?)?.trim(),
      );
    }

    final userSnap = await _db
        .collection('users')
        .where('bus_number', isEqualTo: busNumber)
        .limit(1)
        .get();
    if (userSnap.docs.isNotEmpty) {
      final doc = userSnap.docs.first;
      final data = doc.data();
      return _DriverProfile(
        email: (data['email'] as String? ?? '').trim(),
        displayName: (data['display_name'] as String? ?? 'Driver').trim(),
        routeId: (data['route_id'] as String?)?.trim(),
      );
    }

    final busSnap = await _db
        .collection('buses')
        .where('bus_number', isEqualTo: busNumber)
        .limit(1)
        .get();
    if (busSnap.docs.isNotEmpty) {
      final data = busSnap.docs.first.data();
      return _DriverProfile(
        email: '${busNumber.toLowerCase()}@citybus.live',
        displayName: 'Driver $busNumber',
        routeId: (data['route_id'] as String?)?.trim(),
      );
    }

    throw FirebaseAuthException(
      code: 'driver-not-found',
      message: 'Driver account not found for bus $busNumber.',
    );
  }

  Future<void> _cacheLocalPreferences({
    required String uid,
    bool? notificationsEnabled,
    bool? darkMode,
    bool? dataSaver,
    String? language,
    String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (notificationsEnabled != null) {
      await prefs.setBool('${uid}_notifications_enabled', notificationsEnabled);
    }
    if (darkMode != null) {
      await prefs.setBool('${uid}_dark_mode', darkMode);
    }
    if (dataSaver != null) {
      await prefs.setBool('${uid}_data_saver', dataSaver);
    }
    if (language != null) {
      await prefs.setString('${uid}_language', language);
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      await prefs.setString('${uid}_display_name', displayName.trim());
    }
  }

  Future<_LocalPreferenceCache> _readLocalPreferences(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return _LocalPreferenceCache(
      notificationsEnabled: prefs.getBool('${uid}_notifications_enabled'),
      darkMode: prefs.getBool('${uid}_dark_mode'),
      dataSaver: prefs.getBool('${uid}_data_saver'),
      language: prefs.getString('${uid}_language'),
      displayName: prefs.getString('${uid}_display_name'),
    );
  }
}

class _LocalPreferenceCache {
  const _LocalPreferenceCache({
    this.notificationsEnabled,
    this.darkMode,
    this.dataSaver,
    this.language,
    this.displayName,
  });

  final bool? notificationsEnabled;
  final bool? darkMode;
  final bool? dataSaver;
  final String? language;
  final String? displayName;
}

class _DriverProfile {
  const _DriverProfile({
    this.driverDocId,
    required this.email,
    required this.displayName,
    this.routeId,
  });

  final String? driverDocId;
  final String email;
  final String displayName;
  final String? routeId;
}
