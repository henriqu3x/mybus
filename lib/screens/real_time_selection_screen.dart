import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/kml_service.dart';
import '../services/notification_service.dart';
import '../services/persistence_service.dart';
import 'real_time_travel_screen.dart';

enum _NotificationMode { disabled, background }

class RealTimeSelectionScreen extends StatefulWidget {
  const RealTimeSelectionScreen({super.key});

  @override
  State<RealTimeSelectionScreen> createState() =>
      _RealTimeSelectionScreenState();
}

class _RealTimeSelectionScreenState extends State<RealTimeSelectionScreen> {
  static const String _askedAlwaysPermissionKey =
      'rt_trip_asked_always_permission_once';
  final KmlService _kmlService = KmlService();
  final MapController _mapController = MapController();
  final NotificationService _notificationService = NotificationService();

  List<String> _allLineNames = [];
  List<StopInfo> _stops = [];

  String? _selectedLine;
  StopInfo? _selectedStop;

  bool _isLoadingLines = true;
  bool _isLoadingStops = false;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    setState(() => _isLoadingLines = true);
    try {
      final lines = await _kmlService.getAllFullLineNames();
      if (!mounted) return;

      setState(() {
        _allLineNames = lines;
        _isLoadingLines = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingLines = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar linhas: $e')),
      );
    }
  }

  Future<void> _loadStopsForLine(String lineName) async {
    setState(() {
      _isLoadingStops = true;
      _selectedLine = lineName;
      _selectedStop = null;
      _showMap = true;
    });

    final String lineCode = lineName.split(' - ').first.trim();

    try {
      final stops = await _kmlService.getStopsForLine(lineCode);

      if (!mounted) return;

      setState(() {
        _stops = stops;
        _isLoadingStops = false;
      });

      if (_stops.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _mapController.move(
            LatLng(_stops.first.lat, _stops.first.lon),
            13,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingStops = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar paradas: $e')),
      );
    }
  }

  void _onStopTapped(StopInfo stop) {
    setState(() => _selectedStop = stop);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(stop.name),
        content: const Text('Deseja descer nesta parada?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startTravel();
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _startTravel() {
    if (_selectedLine == null || _selectedStop == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Notificacoes de viagem'),
        content: const Text(
          'Deseja ativar notificacoes de aproximacao da sua parada?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToTravel(
                enableNotifications: false,
                enableBackground: false,
              );
            },
            child: const Text('Nao, apenas usar mapa'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final mode = await _resolveNotificationMode();
              if (!mounted) return;

              if (mode == _NotificationMode.disabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Sem permissao de localizacao em segundo plano. Seguindo sem notificacoes.',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Notificacoes ativas via geofence em segundo plano.',
                    ),
                  ),
                );
              }

              _navigateToTravel(
                enableNotifications: mode == _NotificationMode.background,
                enableBackground: mode == _NotificationMode.background,
              );
            },
            child: const Text('Sim, ativar notificacoes'),
          ),
        ],
      ),
    );
  }

  Future<_NotificationMode> _resolveNotificationMode() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return _NotificationMode.disabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return _NotificationMode.disabled;
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return _NotificationMode.disabled;
    }

    await _notificationService.init();
    final notifGranted = await _notificationService.requestPermissions();
    if (!notifGranted) return _NotificationMode.disabled;

    // Try asking for background location only once.
    // After the first attempt, we do not ask again automatically.
    if (permission != LocationPermission.always) {
      final prefs = await SharedPreferences.getInstance();
      final askedAlways =
          prefs.getBool(_askedAlwaysPermissionKey) == true;

      if (!askedAlways) {
        await prefs.setBool(_askedAlwaysPermissionKey, true);
        permission = await Geolocator.requestPermission();
      }
    }

    if (permission == LocationPermission.always) {
      return _NotificationMode.background;
    }
    return _NotificationMode.disabled;
  }

  void _navigateToTravel({
    required bool enableNotifications,
    required bool enableBackground,
  }) {
    PersistenceService().saveActiveTrip(
      _selectedLine!,
      _selectedStop!,
      enableNotifications: enableNotifications,
      enableBackground: enableBackground,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RealTimeTravelScreen(
          lineName: _selectedLine!,
          destinationStop: _selectedStop!,
          enableNotifications: enableNotifications,
          enableBackground: enableBackground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova Viagem')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Qual onibus voce pegou?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_isLoadingLines)
                  const LinearProgressIndicator()
                else
                  Autocomplete<String>(
                    optionsBuilder: (value) {
                      if (value.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return _allLineNames.where(
                        (o) =>
                            o.toLowerCase().contains(value.text.toLowerCase()),
                      );
                    },
                    onSelected: _loadStopsForLine,
                    fieldViewBuilder: (
                      context,
                      controller,
                      focusNode,
                      _,
                    ) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Ex: 042 - Antonio Bezerra',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Stack(
              children: [
                if (_showMap)
                  FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(-3.7319, -38.5267),
                      initialZoom: 12,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mybus',
                      ),
                      MarkerLayer(
                        markers: _stops.map((stop) {
                          final selected = _selectedStop?.id == stop.id;
                          return Marker(
                            point: LatLng(stop.lat, stop.lon),
                            width: 30,
                            height: 30,
                            child: GestureDetector(
                              onTap: () => _onStopTapped(stop),
                              child: Icon(
                                Icons.location_on,
                                size: 30,
                                color: selected ? Colors.red : Colors.blue,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                if (!_showMap)
                  const Center(
                    child: Text(
                      'Selecione um onibus acima para ver as paradas.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (_isLoadingStops)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
