import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/kml_service.dart';
import '../services/notification_service.dart';
import '../services/persistence_service.dart';

class RealTimeTravelScreen extends StatefulWidget {
  final String lineName;
  final StopInfo destinationStop;

  const RealTimeTravelScreen({
    Key? key,
    required this.lineName,
    required this.destinationStop,
  }) : super(key: key);

  @override
  State<RealTimeTravelScreen> createState() => _RealTimeTravelScreenState();
}

class _RealTimeTravelScreenState extends State<RealTimeTravelScreen> {
  final MapController _mapController = MapController();
  final KmlService _kmlService = KmlService();
  final NotificationService _notificationService = NotificationService();

  StreamSubscription<Position>? _positionStream;

  LatLng? _currentPosition;
  bool _mapReady = false;

  List<LatLng> _routePoints = [];
  List<StopInfo> _sortedStops = [];

  int _lastStopIndex = 0;
  int _destinationIndex = -1;
  int? _remainingStops;
  int? _lastNotifiedRemaining;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    _loadRouteAndStops();
  }

  /* =======================
     GPS EM TEMPO REAL
     ======================= */
  Future<void> _startLocationTracking() async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      final settings = kIsWeb
          ? const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 5,
            )
          : AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 5,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'Acompanhando viagem',
                notificationText:
                    'Você será avisado ao se aproximar da sua parada.',
                enableWakeLock: true,
              ),
            );

      _positionStream = Geolocator.getPositionStream(locationSettings: settings)
          .listen((pos) {
            setState(() {
              _currentPosition = LatLng(pos.latitude, pos.longitude);
              _loading = false;
            });

            if (_mapReady) {
              _mapController.move(
                _currentPosition!,
                _mapController.camera.zoom,
              );
            }

            _checkProximity();
          });

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _currentPosition == null) {
        _currentPosition = LatLng(last.latitude, last.longitude);
      }
    } catch (_) {}
  }

  /* =======================
     DADOS DA LINHA
     ======================= */
  Future<void> _loadRouteAndStops() async {
    try {
      final routes = await _kmlService.getCoordinatesForLines([
        widget.lineName,
      ]);

      for (final segment in routes) {
        for (final c in segment) {
          _routePoints.add(LatLng(c[1], c[0]));
        }
      }

      final code = widget.lineName.split(' - ').first.trim();
      final stops = await _kmlService.getStopsForLine(code);

      final indexed =
          stops.map((s) => MapEntry(s, _closestIndex(_routePoints, s))).toList()
            ..sort((a, b) => a.value.compareTo(b.value));

      _sortedStops = indexed.map((e) => e.key).toList();
      _destinationIndex = _sortedStops.indexWhere(
        (s) => s.id == widget.destinationStop.id,
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  int _closestIndex(List<LatLng> path, StopInfo stop) {
    double min = double.infinity;
    int idx = 0;
    for (int i = 0; i < path.length; i++) {
      final d =
          pow(path[i].latitude - stop.lat, 2) +
          pow(path[i].longitude - stop.lon, 2);
      if (d < min) {
        min = d.toDouble();
        idx = i;
      }
    }
    return idx;
  }

  /* =======================
     LÓGICA DE PROXIMIDADE
     ======================= */
  void _checkProximity() {
    if (_currentPosition == null ||
        _sortedStops.isEmpty ||
        _destinationIndex == -1)
      return;

    final dist = const Distance();
    double min = double.infinity;
    int closest = _lastStopIndex;

    for (int i = _lastStopIndex; i < _sortedStops.length; i++) {
      final stop = _sortedStops[i];
      final d = dist.as(
        LengthUnit.Meter,
        _currentPosition!,
        LatLng(stop.lat, stop.lon),
      );
      if (d < min) {
        min = d;
        closest = i;
      }
    }

    _lastStopIndex = closest;

    final remaining = _destinationIndex - closest;
    setState(() {
      _remainingStops = remaining < 0 ? 0 : remaining;
    });

    if (_remainingStops! <= 3 && _remainingStops! > 0) {
      if (_lastNotifiedRemaining != _remainingStops) {
        _lastNotifiedRemaining = _remainingStops;
        _notifyRemaining(_remainingStops!);
      }
    }

    if (_remainingStops == 0 && min < 300) {
      _notifyArrival();
    }
  }

  /* =======================
     NOTIFICAÇÕES
     ======================= */
  Future<void> _notifyRemaining(int remaining) async {
    await _notificationService.showImmediateNotification(
      id: remaining,
      title: 'Acompanhamento de viagem',
      body: remaining == 1
          ? 'Falta 1 parada para o seu destino.'
          : 'Faltam $remaining paradas para o seu destino.',
    );
  }

  Future<void> _notifyArrival() async {
    await _notificationService.showImmediateNotification(
      id: 0,
      title: 'Chegando!',
      body: 'Prepare-se para descer.',
    );
  }

  /* =======================
     CANCELAR VIAGEM
     ======================= */
  Future<void> _cancelTrip() async {
    await _positionStream?.cancel();
    await PersistenceService().clearActiveTrip();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  /* =======================
     UI
     ======================= */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Em viagem - ${widget.lineName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmCancelTrip,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentPosition ?? const LatLng(-3.7319, -38.5267),
                    initialZoom: 15,
                    onMapReady: () => _mapReady = true,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mybus',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: Colors.blue,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              size: 40,
                              color: Colors.blue,
                            ),
                          ),
                        Marker(
                          point: LatLng(
                            widget.destinationStop.lat,
                            widget.destinationStop.lon,
                          ),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.flag, color: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _remainingStops == null
                            ? 'Calculando paradas...'
                            : _remainingStops == 0
                            ? 'Você chegou ao seu destino!'
                            : 'Faltam $_remainingStops paradas',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmCancelTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viagem?'),
        content: const Text(
          'Isso encerrará o acompanhamento em tempo real e apagará a viagem salva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _cancelTrip();
    }
  }
}
