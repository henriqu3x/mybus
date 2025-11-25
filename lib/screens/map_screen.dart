import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/nominatim_service.dart';

class MapScreen extends StatefulWidget {
// ... (resto da classe MapScreen permanece igual)
  final String? title;

  const MapScreen({super.key, this.title});

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

    _loadStreet();
  }

// ... (o resto da classe permanece igual)

  Future<void> _loadStreet() async {
    if (widget.title == null || widget.title!.isEmpty) {
      setState(() => error = "Nenhuma rua informada");
      return;
    }

    final coords = await NominatimService.getCoordinates(widget.title!);

    if (coords == null) {
      setState(() => error = "Rua não encontrada: ${widget.title}");
      return;
    }

    final lat = coords.latitude;
    final lon = coords.longitude;

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