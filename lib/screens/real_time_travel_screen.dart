import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/geofence_manager.dart';
import '../services/kml_service.dart';
import '../services/persistence_service.dart';

class RealTimeTravelScreen extends StatefulWidget {
  final String lineName;
  final StopInfo destinationStop;
  final bool enableNotifications;
  final bool enableBackground;

  const RealTimeTravelScreen({
    super.key,
    required this.lineName,
    required this.destinationStop,
    this.enableNotifications = true,
    this.enableBackground = true,
  });

  @override
  State<RealTimeTravelScreen> createState() => _RealTimeTravelScreenState();
}

class _RealTimeTravelScreenState extends State<RealTimeTravelScreen> {
  late final WebViewController _controller;

  final KmlService _kmlService = KmlService();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;

  final List<List<double>> _route = [];
  List<StopInfo> _orderedStops = [];

  bool _tripInitialized = false;
  bool _geofenceStarted = false;
  bool _loading = true;

  int _destinationIndex = -1;
  int _currentStopIndex = 0;
  int? _remainingStops;
  double? _etaMinutes;
  final List<double> _speedSamples = [];
  static const int _speedWindow = 6;

  @override
  void initState() {
    super.initState();
    _initController();
    _loadRoute();
    _startLocationStream();
  }

  void _initController() {
    if (kIsWeb) return;
    final params = const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
  }

  Future<void> _loadRoute() async {
    final segments =
        await _kmlService.getCoordinatesForLines([widget.lineName]);

    for (final seg in segments) {
      for (final c in seg) {
        _route.add([c[0], c[1]]);
      }
    }

    final code = widget.lineName.split(' - ').first.trim();
    final stops = await _kmlService.getStopsForLine(code);

    final indexed = stops.map((s) => MapEntry(s, _closestIndex(s))).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    _orderedStops = indexed.map((e) => e.key).toList();
    _destinationIndex = _orderedStops.indexWhere(
      (s) => s.id == widget.destinationStop.id,
    );

    _loadHtml();

    if (widget.enableBackground && _destinationIndex >= 0) {
      await GeofenceManager.instance.initialize();
      _tripInitialized = true;
      if (!_geofenceStarted) {
        _geofenceStarted = true;
        await GeofenceManager.instance.startTrip(
          _orderedStops,
          _destinationIndex,
        );
      }
    }
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

  Future<void> _startLocationStream() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    if (_positionStream != null) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      _currentPosition = pos;
      _updateEta(pos);

      _updateStopsLogic(pos);
      _updateUserInMap(pos);
    });
  }

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

    if (_remainingStops != safe && mounted) {
      setState(() => _remainingStops = safe);
    }
  }

  void _updateEta(Position pos) {
    if (_destinationIndex < 0 || _destinationIndex >= _orderedStops.length) {
      if (_etaMinutes != null && mounted) {
        setState(() => _etaMinutes = null);
      }
      return;
    }

    final dest = _orderedStops[_destinationIndex];
    final distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      dest.lat,
      dest.lon,
    );

    final speed = pos.speed;
    if (speed.isFinite && speed > 0.5) {
      _speedSamples.add(speed);
      if (_speedSamples.length > _speedWindow) {
        _speedSamples.removeAt(0);
      }
    }

    if (_speedSamples.isEmpty || distance <= 0) {
      if (_etaMinutes != null && mounted) {
        setState(() => _etaMinutes = null);
      }
      return;
    }

    final avgSpeed = _speedSamples.reduce((a, b) => a + b) /
        _speedSamples.length;
    final minutes = (distance / avgSpeed) / 60.0;
    final clamped = minutes.isFinite && minutes >= 0 ? minutes : 0.0;

    if (mounted) {
      setState(() => _etaMinutes = clamped);
    }
  }

  void _updateUserInMap(Position pos) {
    if (kIsWeb) return;
    _controller.runJavaScript('''
      if (window.userFeature && window.map) {
        const c = ol.proj.fromLonLat([${pos.longitude}, ${pos.latitude}]);
        userFeature.getGeometry().setCoordinates(c);
        map.getView().animate({ center: c, duration: 500 });
      }
    ''');
  }

  void _loadHtml() {
    if (kIsWeb) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final routeJson = jsonEncode(_route);
    final stopsJson =
        jsonEncode(_orderedStops.map((s) => [s.lon, s.lat]).toList());
    final destLon = widget.destinationStop.lon;
    final destLat = widget.destinationStop.lat;

    final lat = _currentPosition?.latitude ??
        (_route.isNotEmpty ? _route.first[1] : widget.destinationStop.lat);
    final lon = _currentPosition?.longitude ??
        (_route.isNotEmpty ? _route.first[0] : widget.destinationStop.lon);

    _controller.loadHtmlString('''
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
const dest = [$destLon, $destLat];

const map = new ol.Map({
  target:'map',
  layers:[ new ol.layer.Tile({ source:new ol.source.OSM() }) ],
  view:new ol.View({
    center: ol.proj.fromLonLat([$lon,$lat]),
    zoom:15
  })
});

const routeFeature = new ol.Feature({
  geometry:new ol.geom.LineString(route).transform('EPSG:4326','EPSG:3857')
});
routeFeature.setStyle(new ol.style.Style({
  stroke:new ol.style.Stroke({ color:'#1976D2', width:6 })
}));

map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features:[routeFeature] })
}));

const stops = $stopsJson;
const stopFeatures = stops.map(s => {
  return new ol.Feature({
    geometry: new ol.geom.Point(ol.proj.fromLonLat([s[0], s[1]]))
  });
});

const stopStyle = new ol.style.Style({
  image: new ol.style.Circle({
    radius: 5,
    fill: new ol.style.Fill({ color: '#E0E0E0' }),
    stroke: new ol.style.Stroke({ color: '#9E9E9E', width: 1 })
  })
});

map.addLayer(new ol.layer.Vector({
  source: new ol.source.Vector({ features: stopFeatures }),
  style: stopStyle
}));

const destFeature = new ol.Feature({
  geometry: new ol.geom.Point(ol.proj.fromLonLat(dest))
});
const destStyle = new ol.style.Style({
  image: new ol.style.Icon({
    src: 'data:image/svg+xml;utf8,' + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 24 24"><path fill="#D32F2F" d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5z"/></svg>'
    ),
    anchor: [0.5, 1],
    scale: 1
  })
});
destFeature.setStyle(destStyle);
map.addLayer(new ol.layer.Vector({
  source: new ol.source.Vector({ features: [destFeature] })
}));

window.userFeature = new ol.Feature({
  geometry:new ol.geom.Point(ol.proj.fromLonLat([$lon,$lat]))
});

const userStyle = new ol.style.Style({
  image: new ol.style.Circle({
    radius: 8,
    fill: new ol.style.Fill({ color: '#0D47A1' }),
    stroke: new ol.style.Stroke({ color: '#FFFFFF', width: 2 })
  })
});
userFeature.setStyle(userStyle);

map.addLayer(new ol.layer.Vector({
  source:new ol.source.Vector({ features:[userFeature] })
}));
</script>
</body>
</html>
''');

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _endTrip() async {
    await _positionStream?.cancel();
    _positionStream = null;

    if (_tripInitialized) {
      await GeofenceManager.instance.stopTrip();
      _tripInitialized = false;
    }
    _geofenceStarted = false;
  }

  Future<bool> _confirmEndTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viagem'),
        content: const Text(
          'Deseja realmente encerrar a viagem em tempo real?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nao'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _onClosePressed() async {
    final confirmed = await _confirmEndTrip();
    if (!confirmed) return;
    await _endTrip();
    await PersistenceService().clearActiveTrip();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _endTrip();
    super.dispose();
  }

  Widget _buildStatusCard() {
    if (_remainingStops == null) return const SizedBox.shrink();
    final text = _remainingStops == 0
        ? 'Voce chegou ao destino'
        : 'Faltam $_remainingStops paradas'
            '${_etaMinutes == null ? '\nCalculando...' : '\nChegada em ~${_etaMinutes!.ceil()} min'}';
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.lineName),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _onClosePressed,
            ),
          ],
        ),
        body: Stack(
          children: [
            const Center(
              child: Text(
                'Visualizacao em tempo real indisponivel na versao web.',
                textAlign: TextAlign.center,
              ),
            ),
            _buildStatusCard(),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lineName),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onClosePressed,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
          _buildStatusCard(),
        ],
      ),
    );
  }
}
