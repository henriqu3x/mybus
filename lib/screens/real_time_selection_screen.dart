import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/kml_service.dart';
import '../services/persistence_service.dart';
import 'real_time_travel_screen.dart';

class RealTimeSelectionScreen extends StatefulWidget {
  const RealTimeSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RealTimeSelectionScreen> createState() => _RealTimeSelectionScreenState();
}

class _RealTimeSelectionScreenState extends State<RealTimeSelectionScreen> {
  final KmlService _kmlService = KmlService();
  final MapController _mapController = MapController();
  
  // Data
  List<String> _allLineNames = [];
  List<StopInfo> _stops = [];
  
  // Selection
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
      if (mounted) {
        setState(() {
          _allLineNames = lines;
          _isLoadingLines = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLines = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar linhas: $e')),
        );
      }
    }
  }

  Future<void> _loadStopsForLine(String lineName) async {
    setState(() {
      _isLoadingStops = true;
      _selectedLine = lineName;
      _selectedStop = null; 
      _showMap = true;
    });
    
    // Extract the line code/number if needed, or pass the full name if KmlService expects it.
    // Our updated KmlService.getStopsForLine expects the code usually stored in 'lines' list of StopInfo.
    // KmlService.getAllFullLineNames returns "Code - Name - Direction".
    // We need to extract just the code to find matches in stops.lines which usually just has codes.
    String lineCode = lineName.split(' - ').first.trim();
    
    try {
      final stops = await _kmlService.getStopsForLine(lineName);
      if (mounted) {
        setState(() {
          _stops = stops;
          _isLoadingStops = false;
        });
         // Center map on the first stop if available
        if (_stops.isNotEmpty) {
           // Small delay to ensure map is built
           Future.delayed(const Duration(milliseconds: 500), () {
             _mapController.move(LatLng(_stops.first.lat, _stops.first.lon), 13);
           });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStops = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar paradas: $e')),
        );
      }
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
    if (_selectedLine != null && _selectedStop != null) {
      // Create separate async operation to save persistence
      PersistenceService().saveActiveTrip(_selectedLine!, _selectedStop!);
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Localização em Segundo Plano'),
          content: const Text(
            'Para notificá-lo quando estiver chegando, o app precisa acessar sua localização mesmo quando minimizado.\n\nDeseja permitir esse recurso?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateToTravel(false); // User declined
              },
              child: const Text('Não, apenas usar mapa'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateToTravel(true); // User accepted
              },
              child: const Text('Sim, ativar notificações'),
            ),
          ],
        ),
      );
    }
  }

  void _navigateToTravel(bool enableBackground) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RealTimeTravelScreen(
          lineName: _selectedLine!, 
          destinationStop: _selectedStop!,
          enableBackground: enableBackground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Viagem'),
        // backgroundColor: Colors.blue[800],
        // foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. Bus Selection Area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Qual ônibus você pegou?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_isLoadingLines)
                  const LinearProgressIndicator()
                else
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return _allLineNames.where((String option) {
                        return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      _loadStopsForLine(selection);
                    },
                    fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: textController,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Ex: 042 - Antônio Bezerra',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          
          const Divider(),
          
          // 2. Map Area for Stop Selection
          Expanded(
            child: Stack(
              children: [
                if (_showMap)
                  FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(-3.7319, -38.5267), // Fortaleza Center
                      initialZoom: 12,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mybus',
                      ),
                      MarkerLayer(
                        markers: _stops.map((stop) {
                          final isSelected = _selectedStop?.id == stop.id;
                          return Marker(
                            point: LatLng(stop.lat, stop.lon),
                            width: 30,
                            height: 30,
                            child: GestureDetector(
                              onTap: () => _onStopTapped(stop),
                              child: Icon(
                                Icons.location_on,
                                color: isSelected ? Colors.red : Colors.blue,
                                size: 30,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  
                // Instructions or Loading Overlay
                if (!_showMap)
                   const Center(
                     child: Text(
                       'Selecione um ônibus acima para ver as paradas.',
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
                  
                // Hint Overlay
                if (_showMap && !_isLoadingStops && _stops.isNotEmpty)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 8,
                            color: Colors.black.withOpacity(0.2),
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Toque na parada onde deseja descer',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
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
