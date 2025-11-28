import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/nominatim_service.dart';

class MapScreen extends StatefulWidget {
// ... (resto da classe MapScreen permanece igual)
  final String? title;
  final double? latitude;
  final double? longitude;

  const MapScreen({
    super.key,
    this.title,
    this.latitude,
    this.longitude,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? mapUrl;
  String? error;

  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    
    controller = WebViewController();
    
    // ✅ CORREÇÃO FINAL PARA WEB: 
    // Combina todas as chamadas específicas de Mobile em um só bloco.
    // Isso previne erros UnimplementedError na Web para setJavaScriptMode e setBackgroundColor.
    if (!kIsWeb) {
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // setBackgroundColor também é específico de Mobile (Android/iOS)
        ..setBackgroundColor(const Color(0x00000000)); 
    }

    _loadMap();
  }

// ... (o resto da classe permanece igual)

  Future<void> _loadMap() async {
    // If coordinates are provided, use them directly
    if (widget.latitude != null && widget.longitude != null) {
      _loadMapWithCoordinates(widget.latitude!, widget.longitude!);
      return;
    }

    // Otherwise, try to geocode the title
    if (widget.title == null || widget.title!.isEmpty) {
      setState(() => error = "Nenhuma localização informada");
      return;
    }

    final coords = await NominatimService.getCoordinates(widget.title!);

    if (coords == null) {
      setState(() => error = "Localização não encontrada: ${widget.title}");
      return;
    }

    _loadMapWithCoordinates(coords.latitude, coords.longitude);
  }

  void _loadMapWithCoordinates(double lat, double lon) {
    const delta = 0.0015;

    final url =
        "https://www.openstreetmap.org/export/embed.html?"
        "bbox=${lon - delta},${lat - delta},${lon + delta},${lat + delta}"
        "&layer=mapnik&marker=$lat,$lon";

    setState(() => mapUrl = url);

    controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? "Mapa")),
      body: error != null
          ? Center(child: Text(error!))
          : mapUrl == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(
                  controller: controller,
                ),
    );
  }
}