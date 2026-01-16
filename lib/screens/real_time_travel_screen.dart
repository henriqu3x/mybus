import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/kml_service.dart';
import '../services/notification_service.dart';
import '../services/persistence_service.dart';

import 'package:flutter/foundation.dart';

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
  final KmlService _kmlService = KmlService();
  final MapController _mapController = MapController();
  final NotificationService _notificationService = NotificationService();

  StreamSubscription<Position>? _positionStream;
  LatLng? _currentPosition;
  bool _isMapReady = false;

  // Route Data
  List<LatLng> _routePoints = [];
  List<StopInfo> _sortedStops = [];
  int? _lastNotifiedRemaining;
  int _lastStopIndex = 0; // <--- ADICIONE ESTA LINHA

  int _destinationIndex = -1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _loadRouteAndStops();
  }

  Future<void> _startTracking() async {
    try {
      // 1. Verificação básica de serviço (Ignora erro se falhar no Web/F12)
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .catchError((_) => true);
      if (!serviceEnabled && !kIsWeb) {
        if (mounted) _showLocationServiceDialog();
        return;
      }

      // 2. Permissões
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // 3. Configurações Híbridas (Android + Web/F12)
      final locationSettings = kIsWeb
          ? const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            )
          : AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0, // Mude para 0 para testar, depois volte para 5
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: "Monitorando sua viagem",
                notificationText:
                    "O No Ponto avisará quando chegar na sua parada.",
                enableWakeLock: true,
              ),
            );

      // --- O PULO DO GATO ESTÁ AQUI ---

      // Primeiro: Iniciamos o Stream (Ouvinte).
      // Assim, qualquer sinal que vier (do F12 ou do Android) já será capturado.
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen((Position position) {
            if (mounted) {
              debugPrint(
                "SINAL RECEBIDO: ${position.latitude}, ${position.longitude}",
              );
              setState(() {
                _currentPosition = LatLng(
                  position.latitude,
                  position.longitude,
                );
                _isLoading = false; // O sinal chegou, para o loading!
              });

              if (_isMapReady) {
                _mapController.move(
                  _currentPosition!,
                  _mapController.camera.zoom,
                );
                if (_routePoints.isNotEmpty) _checkProximity();
              }
            }
          }, onError: (e) => debugPrint('Erro no Stream: $e'));

      // Segundo: Tentamos pegar a última posição conhecida apenas para o mapa não abrir no meio do mar
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted && _currentPosition == null) {
        setState(
          () => _currentPosition = LatLng(
            lastKnown.latitude,
            lastKnown.longitude,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro fatal no tracking: $e');
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Localização Desativada'),
        content: const Text(
          'Para acompanhar sua viagem, ative o GPS do seu dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
              // Opcional: tentar iniciar o tracking novamente após voltar?
              // Geralmente o usuário tem que reabrir a tela ou clicar em um botão "Tentar Novamente" se fizermos um.
            },
            child: const Text('Abrir Configurações'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Permissão de localização necessária para o rastreamento.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showPermissionPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permissão Necessária'),
        content: const Text(
          'A permissão de localização foi negada permanentemente. '
          'Vá nas configurações do app e permita o acesso à localização.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Abrir Configurações'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRouteAndStops() async {
    // Yield execution to ensure UI stable
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // 1. Get Route Coordinates
      final allRoutesCoords = await _kmlService.getCoordinatesForLines([
        widget.lineName,
      ]);

      List<LatLng> fullRoute = [];
      if (allRoutesCoords.isNotEmpty) {
        for (var segment in allRoutesCoords) {
          for (var coord in segment) {
            fullRoute.add(LatLng(coord[1], coord[0]));
          }
        }
      }

      // 2. Get Stops
      String lineCode = widget.lineName.split(' - ').first.trim();
      final stops = await _kmlService.getStopsForLine(lineCode);

      // 3. Sort Stops
      final stopsWithIndex = stops.map((stop) {
        final closest = _findClosestIndex(
          fullRoute,
          LatLng(stop.lat, stop.lon),
        );
        return MapEntry(stop, closest);
      }).toList();

      stopsWithIndex.sort((a, b) => a.value.compareTo(b.value));
      final sortedStops = stopsWithIndex.map((e) => e.key).toList();

      // 4. Find Destination Index
      final destIndex = sortedStops.indexWhere(
        (s) => s.id == widget.destinationStop.id,
      );

      if (mounted) {
        setState(() {
          _routePoints = fullRoute;
          _sortedStops = sortedStops;
          _destinationIndex = destIndex;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading route data: $e');
      if (mounted) setState(() => _isLoading = false);
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelTrip() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Viagem?'),
        content: const Text('Isso encerrará o acompanhamento em tempo real.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              _stopTripAndLeave();
            },
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );
  }

  // Helper: Find closest point index on polyline
  int _findClosestIndex(List<LatLng> path, LatLng point) {
    if (path.isEmpty) return 0;
    double minDst = double.infinity;
    int minIdx = 0;

    for (int i = 0; i < path.length; i++) {
      final p = path[i];
      // Simple Euclidean distance is sufficient for sorting
      final dst =
          pow(p.latitude - point.latitude, 2) +
          pow(p.longitude - point.longitude, 2);
      if (dst < minDst) {
        minDst = dst as double;
        minIdx = i;
      }
    }
    return minIdx;
  }

  void _checkProximity() {
    if (_currentPosition == null ||
        _sortedStops.isEmpty ||
        _destinationIndex == -1)
      return;

    int closestIndex = _lastStopIndex;
    double minDistance = double.infinity;
    const distanceCalc = Distance();

    // Procuramos apenas a partir da última parada conhecida até o final
    // Isso evita que o GPS "pule" para trás ou para rotas de volta
    for (int i = _lastStopIndex; i < _sortedStops.length; i++) {
      final stop = _sortedStops[i];
      final dist = distanceCalc.as(
        LengthUnit.Meter,
        _currentPosition!,
        LatLng(stop.lat, stop.lon),
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    _lastStopIndex = closestIndex; // Atualiza o progresso
    // Check strict proximity to specific stop to avoid "jumping" too early if simply between stops?
    // For "Stops Remaining", simple index diff is usually good enough.

    // Calculate remaining stops
    // If we are at index 5, and dest is 10. Remaining = 5.

    // We only care if we are *before* the destination
    if (closestIndex > _destinationIndex) return; // Passed it?

    int remaining = _destinationIndex - closestIndex;

    // Trigger alerts for 3, 2, 1
    if (remaining <= 3 && remaining > 0) {
      if (_lastNotifiedRemaining != remaining) {
        _sendProgressiveNotification(remaining);
        _lastNotifiedRemaining = remaining;
      }
    }
    // Immediate close proximity to destination (e.g. < 100m)
    else if (remaining == 0) {
      if (minDistance < 300 && _lastNotifiedRemaining != 0) {
        _sendArrivalNotification();
        _lastNotifiedRemaining = 0;
      }
    }
  }

  Future<void> _sendProgressiveNotification(int remaining) async {
    String bodyText = 'Faltam $remaining paradas para o seu destino.';
    if (remaining == 1) bodyText = 'Falta 1 parada para o seu destino.';

    await _notificationService.showImmediateNotification(
      id: remaining, // unique ID per count
      title: 'Acompanhamento de Viagem',
      body: bodyText,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bodyText), // O estilo virá automaticamente do AppTheme!
          backgroundColor: Colors
              .blueAccent, // Se quiser mudar apenas esta snackbar específica
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sendArrivalNotification() async {
    await _notificationService.showImmediateNotification(
      id: 0,
      title: 'Chegando!',
      body: 'Prepare-se para descer na próxima parada.',
    );

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // Força o usuário a interagir com o botão
        builder: (_) => AlertDialog(
          title: const Text('Chegando!'),
          content: Text(
            'Você está muito próximo de ${widget.destinationStop.name}. '
            '\nDeseja encerrar o acompanhamento?',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // 1. Para o rastreamento
                _positionStream?.cancel();

                // 2. Limpa a persistência
                await PersistenceService().clearActiveTrip();

                // 3. Fecha o diálogo e a tela de viagem
                if (mounted) {
                  Navigator.pop(context); // Fecha o Dialog
                  Navigator.pop(context); // Volta para a tela anterior
                }
              },
              child: const Text('Sim, encerrar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    // Do NOT clear persistence here automatically.
    // PersistenceService().clearActiveTrip();
    super.dispose();
  }

  Future<void> _stopTripAndLeave() async {
    // 1. Cancela a escuta do GPS
    await _positionStream?.cancel();
    _positionStream = null;

    // 2. Limpa dados salvos (se for uma regra de negócio sua)
    await PersistenceService().clearActiveTrip();

    // 3. Sai da tela
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && (_sortedStops.isEmpty || _routePoints.isEmpty)) {
      return Scaffold(
        appBar: AppBar(title: Text('Erro - ${widget.lineName}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Não foi possível carregar os dados da viagem.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rota encontrada: ${_routePoints.isNotEmpty ? "Sim" : "Não"}',
                ),
                Text('Paradas encontradas: ${_sortedStops.length}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Em Viagem - ${widget.lineName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancelar Viagem',
            onPressed: _cancelTrip,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentPosition ?? const LatLng(-3.7319, -38.5267),
                    initialZoom: 15,
                    onMapReady: () {
                      _isMapReady = true;
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mybus',
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_routePoints.isNotEmpty)
                          Polyline(
                            points: _routePoints,
                            color: Colors.blue,
                            strokeWidth: 4,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Marcadores das paradas
                        ..._sortedStops.map(
                          (stop) => Marker(
                            point: LatLng(stop.lat, stop.lon),
                            width: 12,
                            height: 12,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        // Marcador do Destino
                        Marker(
                          point: LatLng(
                            widget.destinationStop.lat,
                            widget.destinationStop.lon,
                          ),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.flag,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                        // Marcador do Usuário
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blueAccent,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Botão para Recentralizar (Opcional)
                Positioned(
                  right: 20,
                  bottom: 160,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () {
                      if (_currentPosition != null) {
                        _mapController.move(_currentPosition!, 15);
                      }
                    },
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),

                // PAINEL INFORMATIVO FLUTUANTE
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_bus,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Destino: ${widget.destinationStop.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          _currentPosition == null
                              ? const Text("Aguardando sinal do GPS...")
                              : Text(
                                  _destinationIndex - _lastStopIndex <= 0
                                      ? "Você chegou ao seu destino!"
                                      : "Faltam ${_destinationIndex - _lastStopIndex} paradas",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
