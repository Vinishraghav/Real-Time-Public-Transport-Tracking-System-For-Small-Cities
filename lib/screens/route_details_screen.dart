import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../models/bus_models.dart';
import '../providers/bus_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class RouteDetailsScreen extends StatefulWidget {
  final String routeId;
  const RouteDetailsScreen({super.key, required this.routeId});

  @override
  State<RouteDetailsScreen> createState() => _RouteDetailsScreenState();
}

class _RouteDetailsScreenState extends State<RouteDetailsScreen> {
  BusRoute? _route;
  List<BusStop> _stops = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final bp = context.read<BusProvider>();
    try {
      _route = bp.allRoutes.firstWhere(
        (r) => r.id == widget.routeId,
        orElse: () => const BusRoute(id: '', routeName: '', startStop: '', endStop: '', stops: []),
      );
      if (_route != null && _route!.id.isNotEmpty) {
        _stops = _route!.stops
            .map((sid) {
              try { return bp.allStops.firstWhere((s) => s.id == sid); }
              catch(_) { return null; }
            })
            .whereType<BusStop>()
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
      );
    }
    if (_route == null || _route!.id.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          const Text('Route not found', style: TextStyle(fontSize: 18, color: AppTheme.textMuted)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: () => context.pop(), child: const Text('Go Back')),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Consumer2<BusProvider, LocationProvider>(
        builder: (context, bp, lp, _) {
          // Find any live bus on this route
          LiveBus? liveBus;
          String? eta;
          double? distKm;
          try {
            liveBus = bp.liveBuses.firstWhere(
              (b) =>
                  b.tripStatus == TripStatus.active &&
                  bp.routeIdForBus(b.busId) == widget.routeId,
            );
          } catch (_) {}

          if (liveBus != null && lp.currentPosition != null) {
            final dist = Geolocator.distanceBetween(
              lp.currentPosition!.latitude, lp.currentPosition!.longitude,
              liveBus.latitude, liveBus.longitude,
            );
            distKm = dist / 1000;
            final destStop = _stops.isNotEmpty ? _stops.last : null;
            if (destStop != null) {
              eta = bp.computeEta(liveBus, destStop);
            }
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.surfaceWhite),
                  onPressed: () => context.pop(),
                ),
                backgroundColor: AppTheme.primaryBlue,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.primaryBlue, Color(0xFF1D3557)],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _chip('Route: ${_route!.routeName}'),
                            const SizedBox(height: 16),
                            Text(
                              '${_stop(bp, _route!.startStop)} → ${_stop(bp, _route!.endStop)}',
                              style: const TextStyle(color: AppTheme.surfaceWhite, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1),
                            ),
                            const SizedBox(height: 20),
                            Row(children: [
                              if (eta != null) _infoChip(Icons.access_time_rounded, 'ETA: $eta'),
                              if (distKm != null) ...[
                                const SizedBox(width: 12),
                                _infoChip(Icons.location_on_rounded, '${distKm.toStringAsFixed(1)} km away'),
                              ],
                              if (liveBus != null) ...[
                                const SizedBox(width: 12),
                                _statusChip(liveBus.tripStatus),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _stops.isEmpty
                  ? SliverFillRemaining(
                      child: Center(child: Text('No stops configured for this route.', style: TextStyle(color: AppTheme.textMuted))),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final stop = _stops[i];
                            final isFirst = i == 0;
                            final isLast  = i == _stops.length - 1;
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Column(children: [
                                      Container(
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          color: isFirst ? AppTheme.successGreen : isLast ? AppTheme.alertRed : AppTheme.primaryBlue,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.surfaceWhite, width: 4),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                                        ),
                                      ),
                                      if (!isLast)
                                        Expanded(
                                          child: Container(
                                            width: 3,
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                    ]),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 24),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceWhite,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5))],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(stop.name,
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                                            ),
                                            if (isFirst)
                                              _label('Origin', AppTheme.successGreen)
                                            else if (isLast)
                                              _label('Destination', AppTheme.alertRed),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: _stops.length,
                        ),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }

  String _stop(BusProvider bp, String stopId) {
    try { return bp.allStops.firstWhere((s) => s.id == stopId).name; }
    catch (_) { return stopId; }
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.surfaceWhite.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.surfaceWhite.withValues(alpha: 0.5)),
    ),
    child: Text(text, style: const TextStyle(color: AppTheme.surfaceWhite, fontSize: 14, fontWeight: FontWeight.bold)),
  );

  Widget _infoChip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: AppTheme.surfaceWhite.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Icon(icon, color: AppTheme.surfaceWhite, size: 16),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: AppTheme.surfaceWhite, fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );

  Widget _statusChip(TripStatus s) {
    final c = s == TripStatus.active ? AppTheme.successGreen : AppTheme.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16)),
      child: Text(s.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _label(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}
