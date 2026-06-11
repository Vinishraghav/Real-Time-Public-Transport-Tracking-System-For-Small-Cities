import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'bus_provider.dart';

import '../theme/app_theme.dart';

class NetworkProvider extends ChangeNotifier {
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  // To avoid spamming alerts on startup
  bool _hasInitialized = false;

  bool get isOnline => _isOnline;

  NetworkProvider() {
    _init();
  }

  Future<void> _init() async {
    final results = await Connectivity().checkConnectivity();
    _updateStatus(results);
    _subscription = Connectivity().onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // If not none, we assume we have connection
    final isConnected = !results.contains(ConnectivityResult.none);
    
    if (_isOnline != isConnected) {
      _isOnline = isConnected;
      
      if (_hasInitialized) {
        _showConnectivitySnackBar(isConnected);
      }
      notifyListeners();
      
      // Control Firestore Streams
      final context = AppGlobals.navigatorKey.currentContext;
      if (context != null) {
        final bp = Provider.of<BusProvider>(context, listen: false);
        if (isConnected) {
          bp.resumeListeners();
        } else {
          bp.pauseListeners();
        }
      }
    }
    
    _hasInitialized = true;
  }

  void _showConnectivitySnackBar(bool isConnected) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(
      // We need a context, but we can't easily get it here without a global navigator key.
      // Easiest solution: We will use a GlobalKey in main.dart
      AppGlobals.navigatorKey.currentContext!,
    );
    
    if (scaffoldMessenger == null) return;
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: AppTheme.surfaceWhite,
            ),
            const SizedBox(width: 12),
            Text(
              isConnected ? 'Back online.' : 'You are offline. Some features may not work.',
              style: const TextStyle(color: AppTheme.surfaceWhite, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: isConnected ? AppTheme.successGreen : AppTheme.alertRed,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class AppGlobals {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
