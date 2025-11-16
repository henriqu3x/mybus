import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../models/itinerary.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Itinerary? _selectedItinerary;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(-3.7319, -38.5267), // Fortaleza coordinates
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    final provider = context.read<ApiProvider>();
    // For demonstration, load the first line's itinerary
    if (provider.lines != null && provider.lines!.isNotEmpty) {
      await provider.fetchItinerary(provider.lines!.first.id);
      final itinerary = provider.itinerary;
      if (itinerary != null) {
        setState(() {
          _selectedItinerary = itinerary['ida'] ?? itinerary['volta'];
        });
        _updateMapMarkers(_selectedItinerary!);
        _updateMapPolylines(_selectedItinerary!);
      }
    }
  }

  void _updateMapMarkers(Itinerary itinerary) {
    // For now, just show a marker at Fortaleza center since we don't have coordinates
    final markers = {
      const Marker(
        markerId: MarkerId('fortaleza_center'),
        position: LatLng(-3.7319, -38.5267),
        infoWindow: InfoWindow(
          title: 'Centro de Fortaleza',
          snippet: 'Ponto inicial da rota',
        ),
      ),
    };

    setState(() {
      _markers = markers;
    });
  }

  void _updateMapPolylines(Itinerary itinerary) {
    // For now, just show a simple line from center to a nearby point
    final polylinePoints = [
      const LatLng(-3.7319, -38.5267), // Fortaleza center
      const LatLng(-3.7320, -38.5270), // Nearby point
    ];

    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Colors.blue,
      width: 5,
      points: polylinePoints,
    );

    setState(() {
      _polylines = {polyline};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Itinerários'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMenuItemSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'select_line',
                child: Text('Selecionar Linha'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Limpar Mapa'),
              ),
            ],
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: _initialPosition,
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (controller) {
          _mapController = controller;
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnRoute,
        child: const Icon(Icons.center_focus_strong),
        tooltip: 'Centralizar na rota',
      ),
    );
  }

  void _onMenuItemSelected(String value) {
    switch (value) {
      case 'select_line':
        _showLineSelectionDialog();
        break;
      case 'clear':
        setState(() {
          _markers = {};
          _polylines = {};
          _selectedItinerary = null;
        });
        break;
    }
  }

  void _showLineSelectionDialog() {
    final lines = context.read<ApiProvider>().lines;

    if (lines == null || lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma linha disponível')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecionar Linha'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      line.id.toString(),
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.blue,
                  ),
                  title: Text(line.name),
                  subtitle: Text('${line.numeroNome} - ${line.tipoLinha}'),
                  onTap: () async {
                    Navigator.pop(context);
                    await context.read<ApiProvider>().fetchItinerary(line.id);
                    final itinerary = context.read<ApiProvider>().itinerary;
                    if (itinerary != null) {
                      setState(() {
                        _selectedItinerary = itinerary['ida'] ?? itinerary['volta'];
                      });
                      _updateMapMarkers(_selectedItinerary!);
                      _updateMapPolylines(_selectedItinerary!);
                      _centerOnRoute();
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _centerOnRoute() {
    if (_selectedItinerary == null || _selectedItinerary!.points.isEmpty) return;

    final bounds = _calculateBounds(_selectedItinerary!.points);
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  LatLngBounds _calculateBounds(List<ItineraryPoint> points) {
    // Since we don't have coordinates, just return a small bounds around Fortaleza center
    return LatLngBounds(
      southwest: const LatLng(-3.7320, -38.5270),
      northeast: const LatLng(-3.7318, -38.5265),
    );
  }
}
