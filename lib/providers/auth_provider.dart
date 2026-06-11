import 'dart:async';

import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService})
    : _authService = authService ?? AuthService() {
    _subscription = _authService.sessionChanges().listen((session) {
      _session = session;
      _isInitialized = true;
      _error = null;
      notifyListeners();
    });
  }

  final AuthService _authService;
  StreamSubscription<AppSession?>? _subscription;

  AppSession? _session;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  AppSession? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  ThemeMode get themeMode =>
      _session?.darkMode == true ? ThemeMode.dark : ThemeMode.light;
  Locale get locale =>
      (_session?.language ?? 'English').toLowerCase().startsWith('tamil')
      ? const Locale('ta')
      : const Locale('en');

  Future<void> refreshSession() async {
    _session = await _authService.currentSession();
    _isInitialized = true;
    notifyListeners();
  }

  Future<bool> signInDriver({
    required String busNumber,
    required String password,
  }) async {
    return _runGuarded(() async {
      _session = await _authService.signInDriver(
        busNumber: busNumber,
        password: password,
      );
    });
  }

  Future<bool> signInPassenger({
    required String email,
    required String password,
  }) async {
    return _runGuarded(() async {
      _session = await _authService.signInPassenger(
        email: email,
        password: password,
      );
    });
  }

  Future<bool> registerPassenger({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return _runGuarded(() async {
      _session = await _authService.registerPassenger(
        email: email,
        password: password,
        displayName: displayName,
      );
    });
  }

  Future<bool> signInWithGoogle() async {
    return _runGuarded(() async {
      _session = await _authService.signInPassengerWithGoogle();
    });
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _authService.signOut();
      _session = null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updatePreferences({
    bool? notificationsEnabled,
    bool? darkMode,
    bool? dataSaver,
    String? language,
    String? displayName,
  }) async {
    final session = _session;
    if (session == null) return;

    await _authService.updatePreferences(
      uid: session.uid,
      notificationsEnabled: notificationsEnabled,
      darkMode: darkMode,
      dataSaver: dataSaver,
      language: language,
      displayName: displayName,
    );

    _session = session.copyWith(
      notificationsEnabled:
          notificationsEnabled ?? session.notificationsEnabled,
      darkMode: darkMode ?? session.darkMode,
      dataSaver: dataSaver ?? session.dataSaver,
      language: language ?? session.language,
      displayName: displayName ?? session.displayName,
    );
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> _runGuarded(Future<void> Function() action) async {
    _setLoading(true);
    _error = null;
    try {
      await action();
      return true;
    } on Exception catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
