import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // Import necessário para kIsWeb
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/trip_segment.dart';
import '../services/kml_service.dart';

class RouteMapScreen extends StatefulWidget {
  final List<TripSegment> segments;
  final String origin;
  final String destination;

  const RouteMapScreen({
    super.key,
    required this.segments,
    required this.origin,
    required this.destination,
  });

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
    try {
      // 1. Construir mapa de linhas em formato KML -> segmento
      final lineToSegmentMap = <String, TripSegment>{};
      final lineNamesKml = <String>[];

      for (var segment in widget.segments.where((s) => s.type == 'BUS')) {
        String lineName = segment.lineName;
        String direction = '';

        if (lineName.endsWith('_IDA')) {
          direction = ' - Ida';
          lineName = lineName.substring(0, lineName.length - 4);
        } else if (lineName.endsWith('_VOLTA')) {
          direction = ' - Volta';
          lineName = lineName.substring(0, lineName.length - 6);
        }

        int firstDash = lineName.indexOf('-');
        if (firstDash != -1) {
          lineName =
              lineName.substring(0, firstDash) +
              ' - ' +
              lineName.substring(firstDash + 1);
        }

        final kmlName = lineName + direction;
        lineNamesKml.add(kmlName);
        lineToSegmentMap[kmlName] = segment;
      }

      // 2. Buscar rotas do KML
      final routesData = await _kmlService.getCoordinatesForLines(lineNamesKml);
      final routeMap = <String, List<List<double>>>{};
      for (int i = 0; i < lineNamesKml.length && i < routesData.length; i++) {
        routeMap[lineNamesKml[i]] = routesData[i];
      }

      // 3. Extrair números de linhas para cada segmento
      final List<String> busLineNumbersPerSegment = [];
      for (var segment in widget.segments.where((s) => s.type == 'BUS')) {
        final match = RegExp(r'^(\d+)').firstMatch(segment.lineName);
        final lineNum = match?.group(1) ?? '';
        if (lineNum.isNotEmpty) {
          busLineNumbersPerSegment.add(lineNum);
        }
      }

      // 4. Processar cada segmento: cortar rotas e coletar dados
      final List<Map<String, dynamic>> processedRoutes = [];
      final List<Map<String, dynamic>> walkingPaths = [];
      final List<Map<String, dynamic>> originStopsData = [];
      final List<Map<String, dynamic>> destinationStopsData = [];
      final colors = ['#0000FF', '#FF4500', '#008000', '#800080'];

      StopInfo? previousEndStop; // parada de desembarque do ônibus anterior
      List<List<double>>? previousRouteCoords; // coordenadas da rota anterior

      for (int idx = 0; idx < widget.segments.length; idx++) {
        final segment = widget.segments[idx];
        if (segment.type != 'BUS') continue;

        final kmlName = lineNamesKml[idx];
        final routeCoords = routeMap[kmlName];
        if (routeCoords == null || routeCoords.isEmpty) continue;

        // Extrair número da linha deste segmento
        final lineNum = busLineNumbersPerSegment.isNotEmpty && idx < busLineNumbersPerSegment.length
            ? busLineNumbersPerSegment[idx]
            : '';

        // Determinar parada de embarque
        StopInfo? boardingStop;
        int boardingIndex = 0;
        
        if (idx == 0) {
          // Primeiro segmento: buscar parada de origem para esta linha específica
          final stopsForThisLine = await _kmlService.findStopsOnStreet(
            widget.origin,
            [lineNum],
          );
          boardingStop = stopsForThisLine.isNotEmpty ? stopsForThisLine.first : null;
          if (boardingStop != null) {
            boardingIndex = _findClosestInRoute(routeCoords, boardingStop.lat, boardingStop.lon)['index'];
            // Adicionar ponto de origem aos dados do mapa
            originStopsData.add({
              'lat': boardingStop.lat,
              'lon': boardingStop.lon,
              'name': boardingStop.name,
            });
          }
        } else if (previousRouteCoords != null) {
          // Próximos segmentos: começar a ~200m do fim da rota anterior
          boardingIndex = _findPointAtDistanceFromEnd(previousRouteCoords, 200);
          if (boardingIndex < routeCoords.length) {
            final nearestInCurrent = _findClosestInRoute(
              routeCoords,
              previousRouteCoords[boardingIndex][1],
              previousRouteCoords[boardingIndex][0],
            );
            boardingIndex = nearestInCurrent['index'];
          }
        }

        // Determinar parada de desembarque
        StopInfo? alightingStop;
        int alightingIndex = routeCoords.length - 1;
        
        if (idx == widget.segments.length - 1) {
          // Último segmento: buscar parada de destino para esta linha específica
          final stopsForThisLine = await _kmlService.findStopsOnStreet(
            widget.destination,
            [lineNum],
          );
          alightingStop = stopsForThisLine.isNotEmpty ? stopsForThisLine.first : null;
          if (alightingStop != null) {
            final result = _findClosestInRoute(routeCoords, alightingStop.lat, alightingStop.lon);
            alightingIndex = result['index'];
            // Adicionar ponto de destino aos dados do mapa
            destinationStopsData.add({
              'lat': alightingStop.lat,
              'lon': alightingStop.lon,
              'name': alightingStop.name,
            });
          }
        } else {
          // Segmentos intermediários: usar fim da rota
          alightingIndex = routeCoords.length - 1;
          alightingStop = null;
        }

        // Cortar rota conforme índices encontrados
        List<List<double>> processedCoords = routeCoords;
        if (boardingIndex < alightingIndex) {
          processedCoords = _sliceRoute(routeCoords, boardingIndex, alightingIndex);
        }

        // Adicionar rota processada
        if (processedCoords.isNotEmpty) {
          processedRoutes.add({
            'coordinates': processedCoords,
            'color': colors[idx % colors.length],
            'label': 'Linha $lineNum',
          });
        }

        // Adicionar linha de caminhada se há troca de ônibus
        if (previousRouteCoords != null && previousRouteCoords.isNotEmpty) {
          final prevLastCoord = previousRouteCoords.last;
          final currentFirstCoord = processedCoords.isNotEmpty ? processedCoords.first : routeCoords.first;
          walkingPaths.add({
            'from': prevLastCoord,
            'to': currentFirstCoord,
          });
        }

        previousEndStop = alightingStop;
        previousRouteCoords = routeCoords;
      }

      _loadHtmlContent(processedRoutes, originStopsData, destinationStopsData, walkingPaths);
    } catch (e) {
      print('Erro ao carregar dados do mapa: $e');
      _loadHtmlContent([], [], [], []);
    }
  }

  // Calcula distância Haversine entre dois pontos em metros
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // Raio da Terra em metros
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // Encontra o índice que está a ~distanceMeters metros antes do fim da rota
  int _findPointAtDistanceFromEnd(
      List<List<double>> routeCoordinates, double distanceMeters) {
    if (routeCoordinates.length < 2) return 0;

    double accumulatedDistance = 0;
    // Começar do fim e ir para trás
    for (int i = routeCoordinates.length - 1; i > 0; i--) {
      final currentLat = routeCoordinates[i][1];
      final currentLon = routeCoordinates[i][0];
      final prevLat = routeCoordinates[i - 1][1];
      final prevLon = routeCoordinates[i - 1][0];

      final segmentDistance = _haversineDistance(prevLat, prevLon, currentLat, currentLon);
      accumulatedDistance += segmentDistance;

      if (accumulatedDistance >= distanceMeters) {
        return i - 1;
      }
    }

    return 0;
  }

  Map<String, dynamic> _findClosestInRoute(
    List<List<double>> routeCoordinates,
    double targetLat,
    double targetLon,
  ) {
    if (routeCoordinates.isEmpty) return {'index': 0, 'distance': double.infinity};

    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < routeCoordinates.length; i++) {
      final coord = routeCoordinates[i];
      final lon = coord[0];
      final lat = coord[1];

      final distance = sqrt((lat - targetLat) * (lat - targetLat) +
              (lon - targetLon) * (lon - targetLon));

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return {'index': closestIndex, 'distance': minDistance};
  }

  List<List<double>> _sliceRoute(
    List<List<double>> routeCoordinates,
    int startIndex,
    int endIndex,
  ) {
    if (routeCoordinates.isEmpty) return [];

    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    final clampedStart = start.clamp(0, routeCoordinates.length - 1);
    final clampedEnd = end.clamp(0, routeCoordinates.length - 1);

    return routeCoordinates.sublist(clampedStart, clampedEnd + 1);
  }

  void _loadHtmlContent(
      List<Map<String, dynamic>> routesWithTheme,
      List<dynamic> originStops,
      List<dynamic> destinationStops,
      List<Map<String, dynamic>> walkingPaths) {
    // Converter rotas e paradas para JSON para injetar no JS
    final routesJson = jsonEncode(routesWithTheme);

    // Converter originStops e destinationStops para formato correto
    final originStopsJson = jsonEncode(
      (originStops as List<dynamic>).map((stop) {
        if (stop is Map<String, dynamic>) {
          return {
            'lat': stop['lat'],
            'lon': stop['lon'],
            'name': stop['name'],
            'type': 'origin',
          };
        }
        return null;
      }).where((s) => s != null).toList(),
    );

    final destinationStopsJson = jsonEncode(
      (destinationStops as List<dynamic>).map((stop) {
        if (stop is Map<String, dynamic>) {
          return {
            'lat': stop['lat'],
            'lon': stop['lon'],
            'name': stop['name'],
            'type': 'destination',
          };
        }
        return null;
      }).where((s) => s != null).toList(),
    );

    final walkingPathsJson = jsonEncode(walkingPaths);

    final htmlContent =
        '''
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
          .ol-popup {
            position: absolute;
            background-color: white;
            box-shadow: 0 1px 4px rgba(0,0,0,0.2);
            padding: 15px;
            border-radius: 10px;
            border: 1px solid #cccccc;
            bottom: 12px;
            left: -50px;
            min-width: 200px;
          }
          .ol-popup:after {
            top: 100%;
            border: solid transparent;
            content: " ";
            height: 0;
            width: 0;
            position: absolute;
            pointer-events: none;
            border-top-color: white;
            border-width: 10px;
            left: 48px;
            margin-left: -10px;
          }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/ol@v8.2.0/dist/ol.js"></script>
      </head>
      <body>
        <div id="map"></div>
        <div id="popup" class="ol-popup" style="display:none;"></div>
        <script>
          // Dados das rotas injetados pelo Dart
          const routesData = $routesJson;
          const originStopsData = $originStopsJson;
          const destinationStopsData = $destinationStopsJson;
          const walkingPathsData = $walkingPathsJson;
          
          console.log('RouteMapScreen (JS): routes, originStops, destinationStops, walkingPaths', 
            routesData, originStopsData, destinationStopsData, walkingPathsData);

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

          // Adicionar rotas de ônibus
          const vectorSource = new ol.source.Vector();
          
          if (routesData && routesData.length > 0) {
            routesData.forEach((routeItem) => {
              const routeCoords = routeItem.coordinates;
              const routeColor = routeItem.color || 'blue';

              const lineString = new ol.geom.LineString(routeCoords);
              lineString.transform('EPSG:4326', 'EPSG:3857'); 
              
              const feature = new ol.Feature({
                geometry: lineString,
                name: 'Bus Route'
              });

              const style = new ol.style.Style({
                stroke: new ol.style.Stroke({
                  color: routeColor,
                  width: 5
                })
              });
              
              feature.setStyle(style);
              vectorSource.addFeature(feature);
            });
          }

          // Adicionar linhas de caminhada (tracejadas, cinza)
          if (walkingPathsData && walkingPathsData.length > 0) {
            walkingPathsData.forEach((pathItem) => {
              const lineString = new ol.geom.LineString([pathItem.from, pathItem.to]);
              lineString.transform('EPSG:4326', 'EPSG:3857');
              
              const feature = new ol.Feature({
                geometry: lineString,
                name: 'Walking Path'
              });

              const style = new ol.style.Style({
                stroke: new ol.style.Stroke({
                  color: '#999999',
                  width: 2,
                  lineDash: [5, 5]
                })
              });
              
              feature.setStyle(style);
              vectorSource.addFeature(feature);
            });
          }

          // Adicionar paradas de origem (verde)
          if (originStopsData && originStopsData.length > 0) {
            originStopsData.forEach((stop) => {
              const point = new ol.geom.Point([stop.lon, stop.lat]);
              point.transform('EPSG:4326', 'EPSG:3857');
              
              const feature = new ol.Feature({
                geometry: point,
                name: stop.name,
                type: 'origin'
              });

              const style = new ol.style.Style({
                image: new ol.style.Circle({
                  radius: 8,
                  fill: new ol.style.Fill({ color: '#00AA00' }),
                  stroke: new ol.style.Stroke({ color: 'white', width: 2 })
                })
              });
              
              feature.setStyle(style);
              vectorSource.addFeature(feature);
            });
          }

          // Adicionar paradas de destino (vermelho)
          if (destinationStopsData && destinationStopsData.length > 0) {
            destinationStopsData.forEach((stop) => {
              const point = new ol.geom.Point([stop.lon, stop.lat]);
              point.transform('EPSG:4326', 'EPSG:3857');
              
              const feature = new ol.Feature({
                geometry: point,
                name: stop.name,
                type: 'destination'
              });

              const style = new ol.style.Style({
                image: new ol.style.Circle({
                  radius: 8,
                  fill: new ol.style.Fill({ color: '#AA0000' }),
                  stroke: new ol.style.Stroke({ color: 'white', width: 2 })
                })
              });
              
              feature.setStyle(style);
              vectorSource.addFeature(feature);
            });
          }

          const vectorLayer = new ol.layer.Vector({
            source: vectorSource
          });
          
          map.addLayer(vectorLayer);

          // Ajustar zoom para caber todas as rotas
          const extent = vectorSource.getExtent();
          map.getView().fit(extent, {
            padding: [50, 50, 50, 50],
            duration: 1000
          });

          // Popup ao clicar em elementos
          const popup = document.getElementById('popup');
          let popupOverlay = new ol.Overlay({
            element: popup,
            positioning: 'bottom-center',
            stopEvent: false
          });
          map.addOverlay(popupOverlay);

          map.on('click', function(evt) {
            const features = map.getFeaturesAtPixel(evt.pixel);
            if (features && features.length > 0) {
              const feature = features[0];
              const name = feature.get('name');
              if (name) {
                popup.innerHTML = '<div><strong>' + name + '</strong></div>';
                popupOverlay.setPosition(evt.coordinate);
                popup.style.display = 'block';
              }
            } else {
              popup.style.display = 'none';
            }
          });

          map.on('pointermove', function(evt) {
            const pixel = map.getEventPixel(evt.originalEvent);
            const features = map.getFeaturesAtPixel(pixel);
            map.getTarget().style.cursor = features && features.length > 0 ? 'pointer' : '';
          });
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
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
