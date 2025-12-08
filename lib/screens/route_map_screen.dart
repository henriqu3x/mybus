import 'dart:convert';
import 'package:flutter/foundation.dart'; // Import necessário para kIsWeb
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/trip_segment.dart'; // Assumindo que este caminho está correto
import '../services/kml_service.dart'; // Assumindo que este caminho está correto

class RouteMapScreen extends StatefulWidget {
  final List<TripSegment> segments;

  const RouteMapScreen({super.key, required this.segments});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  // Inicializamos com late, mas vamos usar o construtor padrão
  late final WebViewController _controller;
  final KmlService _kmlService = KmlService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initController();
    _loadMapData();
  }

  void _initController() {
    late final PlatformWebViewControllerCreationParams params;
    
    if (WebViewPlatform.instance == null) {
      params = const PlatformWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

    if (!kIsWeb) {
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
      
      // Only set navigation delegate on non-web platforms to avoid unimplemented errors
      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      );
    }

    _controller = controller;
  }

  Future<void> _loadMapData() async {
    // Filtrar apenas segmentos de ônibus
    print("DEBUG: Segments count: ${widget.segments.length}");
    final busSegments = widget.segments
        .where((s) => s.type == 'BUS')
        .map((s) {
          // Convert from graph format to KML format
          // Graph: "421-Lagoa/Parangaba/Montese/Centro_IDA"
          // KML: "421 - Lagoa/Parangaba/Montese/Centro - Ida"
          String lineName = s.lineName;
          String direction = '';
          
          // Extract direction
          if (lineName.endsWith('_IDA')) {
            direction = ' - Ida';
            lineName = lineName.substring(0, lineName.length - 4);
          } else if (lineName.endsWith('_VOLTA')) {
            direction = ' - Volta';
            lineName = lineName.substring(0, lineName.length - 6);
          }
          
          // Replace first dash with " - " (e.g., "421-Description" -> "421 - Description")
          int firstDash = lineName.indexOf('-');
          if (firstDash != -1) {
            lineName = lineName.substring(0, firstDash) + ' - ' + lineName.substring(firstDash + 1);
          }
          
          return lineName + direction;
        })
        .toList();
        
    print("DEBUG: Bus Segments to find: $busSegments");

    // Buscar coordenadas no KML
    // Retorna List<List<List<double>>> -> Lista de Rotas -> Lista de Coordenadas [lon, lat]
    final routesCoordinates = await _kmlService.getCoordinatesForLines(busSegments);
    
    print("DEBUG: Found ${routesCoordinates.length} route paths");

    _loadHtmlContent(routesCoordinates);
  }

  void _loadHtmlContent(List<List<List<double>>> routes) {
    // Converter rotas para JSON para injetar no JS
    final routesJson = jsonEncode(routes);

    final htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>OpenLayers Map</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@v8.2.0/ol.css">
        <style>
          body, html { margin: 0; padding: 0; height: 100%; width: 100%; }
          #map { height: 100%; width: 100%; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/ol@v8.2.0/dist/ol.js"></script>
      </head>
      <body>
        <div id="map"></div>
        <script>
          // Dados das rotas injetados pelo Dart
          const routesData = $routesJson;

          // Coordenada central inicial (Fortaleza aprox)
          const defaultCenter = [-38.5267, -3.7319]; 

          const map = new ol.Map({
            target: 'map',
            layers: [
              new ol.layer.Tile({
                source: new ol.source.OSM()
              })
            ],
            view: new ol.View({
              center: ol.proj.fromLonLat(defaultCenter),
              zoom: 12
            })
          });

          // Style para as linhas
          const styles = [
            new ol.style.Style({
              stroke: new ol.style.Stroke({
                color: 'blue',
                width: 4
              })
            }),
             new ol.style.Style({
              stroke: new ol.style.Stroke({
                color: 'rgba(0, 0, 255, 0.1)', // Outline para melhor visibilidade em fundos claros
                width: 6
              })
            })
          ];

          // Adicionar rotas
          const vectorSource = new ol.source.Vector();
          
          if (routesData && routesData.length > 0) {
            routesData.forEach((routeCoords) => {
              // routeCoords é [[lon, lat], [lon, lat], ...]
              const lineString = new ol.geom.LineString(routeCoords);
              // Transformar de WGS 84 (4326) para Web Mercator (3857) - padrão do OpenLayers
              lineString.transform('EPSG:4326', 'EPSG:3857'); 
              
              const feature = new ol.Feature({
                geometry: lineString,
                name: 'Bus Route'
              });
              
              vectorSource.addFeature(feature);
            });

            const vectorLayer = new ol.layer.Vector({
              source: vectorSource,
              style: styles
            });
            
            map.addLayer(vectorLayer);

            // Ajustar zoom para caber todas as rotas
            const extent = vectorSource.getExtent();
            map.getView().fit(extent, {
              padding: [50, 50, 50, 50],
              duration: 1000
            });
          }
        </script>
      </body>
      </html>
    ''';

    // Carrega o conteúdo HTML no WebView
    _controller.loadHtmlString(htmlContent).then((_) {
      // On Web, we don't have a NavigationDelegate, so we assume load finishes quickly
      // or simply hide the spinner after the string is loaded.
      if (kIsWeb && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualização da Rota'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Exibe o WebView com o mapa OpenLayers injetado
          WebViewWidget(controller: _controller),
          
          // Exibe o indicador de carregamento enquanto _isLoading for true
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}