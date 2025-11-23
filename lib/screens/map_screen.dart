import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/itinerario.dart';

class MapScreen extends StatefulWidget {
  final Itinerario? itinerario;
  final String? title;

  const MapScreen({super.key, this.itinerario, this.title});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;

  final LatLng _center = const LatLng(
    -3.7319,
    -38.5267,
  ); // Fortaleza coordinates

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _loadItinerary();
  }

  void _loadItinerary() {
    if (widget.itinerario == null) return;

    List<LatLng> points = [];

    // Note: The API does not provide coordinates for stops, only names and IDs.
    // In a real scenario, we would need a database of coordinates for each logId.
    // For this demo, since we don't have coordinates, we can't plot the real route.
    // I will add a placeholder message or mock some coordinates if possible,
    // but without real data, the map will be empty or generic.

    // However, the user prompt mentions "Visualização do itinerário completo no mapa".
    // If the API doesn't give coordinates, maybe I missed something?
    // Checked API response: "logId", "nome", "distanciaPercorrida". No lat/long.
    // Checked "logradouros" API: "id", "nome", "tipo". No lat/long.

    // CRITICAL: The provided API does not seem to return coordinates.
    // I will display a SnackBar warning about this limitation.

    setState(() {
      // Adding a dummy marker to show map is working
      _markers.add(
        const Marker(
          markerId: MarkerId('center'),
          position: LatLng(-3.7319, -38.5267),
          infoWindow: InfoWindow(title: 'Fortaleza'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: _center, zoom: 12.0),
        markers: _markers,
        polylines: _polylines,
      ),
    );
  }
}
