import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kml_service.dart';
import '../services/notification_service.dart';
import '../services/persistence_service.dart';

class RealTimeTravelScreen extends StatefulWidget {
  final String lineName;
  final StopInfo destinationStop;

  const RealTimeTravelScreen({
    super.key,
    required this.lineName,
    required this.destinationStop,
  });

  @override
  State<RealTimeTravelScreen> createState() => _RealTimeTravelScreenState();
}

class _RealTimeTravelScreenState extends State<RealTimeTravelScreen> {
  late final WebViewController _controller;

  final KmlService _kmlService = KmlService();
  final NotificationService _notificationService = NotificationService();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;

  List<List<double>> _route = [];
  List<StopInfo> _orderedStops = [];

  int _destinationIndex = -1;
  int _currentStopIndex = 0;
  int? _remainingStops;
  int? _lastNotified;

  bool _loading = true;

  /* ================= INIT ================= */

  @override
  void initState() {
    super.initState();
    _initController();
    _loadRoute();
    _startLocationStream();
  }

  void _initController() {
    late final PlatformWebViewControllerCreationParams params;

    params = const PlatformWebViewControllerCreationParams();

    final controller =
        WebViewController.fromPlatformCreationParams(params);

    if (!kIsWeb) {
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
    }

    _controller = controller;
  }

  /* ================= DATA ================= */

  Future<void> _loadRoute() async {
    final segments =
        await _kmlService.getCoordinatesForLines([widget.lineName]);

    for (final seg in segments) {
      for (final c in seg) {
        _route.add([c[0], c[1]]); // lon, lat
      }
    }

    final code = widget.lineName.split(' - ').first.trim();
    final stops = await _kmlService.getStopsForLine(code);

    final indexed =
        stops.map((s) => MapEntry(s, _closestIndex(s))).toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    _orderedStops = indexed.map((e) => e.key).toList();
    _destinationIndex = _orderedStops
        .indexWhere((s) => s.id == widget.destinationStop.id);

    _loadHtml();
  }

  int _closestIndex(StopInfo stop) {
    double min = double.infinity;
    int idx = 0;

    for (int i = 0; i < _route.length; i++) {
      final dx = _route[i][1] - stop.lat;
      final dy = _route[i][0] - stop.lon;
      final d = dx * dx + dy * dy;
      if (d < min) {
        min = d;
        idx = i;
      }
    }
    return idx;
  }

  /* ================= GPS ================= */

  Future<void> _startLocationStream() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _currentPosition = pos;
      _updateStopsLogic(pos);
      _updateUserInMap(pos);
    });
  }

  /* ================= LOGIC ================= */

  void _updateStopsLogic(Position pos) {
    double min = double.infinity;
    int closest = _currentStopIndex;

    for (int i = _currentStopIndex; i < _orderedStops.length; i++) {
      final s = _orderedStops[i];
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        s.lat,
        s.lon,
      );
      if (d < min) {
        min = d;
        closest = i;
      }
    }

    _currentStopIndex = closest;
    final remaining = _destinationIndex - closest;
    final safe = remaining < 0 ? 0 : remaining;

    setState(() => _remainingStops = safe);

    if (safe <= 3 && safe > 0 && _lastNotified != safe) {
      _lastNotified = safe;
      _notificationService.showImmediateNotification(
        id: safe,
        title: 'Viagem em andamento',
        body: 'Faltam $safe paradas para o seu destino.',
      );
    }

    if (safe == 0 && min < 250) {
      _notificationService.showImmediateNotification(
        id: 0,
        title: 'Chegando!',
        body: 'Prepare-se para descer.',
      );
    }
  }

  /* ================= JS ================= */

  void _updateUserInMap(Position pos) {
    final js = '''
      if (window.userFeature) {
        const c = ol.proj.fromLonLat([${pos.longitude}, ${pos.latitude}]);
        userFeature.getGeometry().setCoordinates(c);
        map.getView().animate({ center: c, duration: 600 });
      }
    ''';
    _controller.runJavaScript(js);
  }

  /* ================= HTML ================= */

  void _loadHtml() {
    final routeJson = jsonEncode(_route);
    final stopsList = _orderedStops.map((s) => [s.lon, s.lat]).toList();
    final stopsJson = jsonEncode(stopsList);
    final dest = widget.destinationStop;

    double initialLat = dest.lat;
    double initialLon = dest.lon;

    if (_currentPosition != null) {
      initialLat = _currentPosition!.latitude;
      initialLon = _currentPosition!.longitude;
    } else if (_route.isNotEmpty) {
      initialLon = _route.first[0];
      initialLat = _route.first[1];
    }

    final html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/ol@v8.2.0/dist/ol.js"></script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@v8.2.0/ol.css">
<style>html,body,#map{margin:0;height:100%;}</style>
</head>
<body>
<div id="map"></div>
<script>
const route = $routeJson;
const stops = $stopsJson;

const map = new ol.Map({
  target:'map',
  layers:[ new ol.layer.Tile({ source:new ol.source.OSM() }) ],
  view:new ol.View({ zoom:15 })
});

// Route Line
const routeFeature = new ol.Feature({
  geometry: new ol.geom.LineString(route).transform('EPSG:4326','EPSG:3857')
});
routeFeature.setStyle(new ol.style.Style({
  stroke: new ol.style.Stroke({ color:'#1976D2', width:6 })
}));
map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features:[routeFeature] })
}));

// Stops Markers (Grey dots)
const stopFeatures = stops.map(coord => {
  const f = new ol.Feature({
    geometry: new ol.geom.Point(ol.proj.fromLonLat(coord))
  });
  f.setStyle(new ol.style.Style({
    image: new ol.style.Circle({
      radius: 4,
      fill: new ol.style.Fill({color:'#757575'}),
      stroke: new ol.style.Stroke({color:'#fff', width:1})
    })
  }));
  return f;
});
map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features: stopFeatures })
}));

// User Marker (Blue Person Icon)
window.userFeature = new ol.Feature({
  geometry:new ol.geom.Point(ol.proj.fromLonLat([$initialLon,$initialLat]))
});
userFeature.setStyle(new ol.style.Style({
  image:new ol.style.Icon({
    anchor: [0.5, 0.5],
    src: 'https://cdn-icons-png.flaticon.com/512/456/456212.png',
    color: '#1E88E5',
    scale: 0.05
  })
}));
map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features:[userFeature] })
}));

// Destination Marker
const destFeature = new ol.Feature({
  geometry:new ol.geom.Point(ol.proj.fromLonLat([${dest.lon},${dest.lat}]))
});
destFeature.setStyle(new ol.style.Style({
  image:new ol.style.Icon({
    anchor: [0.5, 1],
    src:'https://cdn-icons-png.flaticon.com/64/684/684908.png',
    scale:0.4
  })
}));
map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features:[destFeature] })
}));

map.getView().setCenter(ol.proj.fromLonLat([$initialLon,$initialLat]));
</script>
</body>
</html>
''';

    _controller.loadHtmlString(html);
    setState(() => _loading = false);
  }

  /* ================= UI ================= */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lineName),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmCancel,
          )
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_remainingStops != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _remainingStops == 0
                        ? 'Você chegou ao destino'
                        : 'Faltam $_remainingStops paradas',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }

  /* ================= CANCEL ================= */

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar viagem?'),
        content: const Text('Isso encerrará o acompanhamento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _positionStream?.cancel();
      await PersistenceService().clearActiveTrip();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
