import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kml_service.dart';
import 'stop_detail_screen.dart';

class StopWalkingMapScreen extends StatefulWidget {
  final Position userPosition;
  final StopInfo stop;

  const StopWalkingMapScreen({
    super.key,
    required this.userPosition,
    required this.stop,
  });

  @override
  State<StopWalkingMapScreen> createState() => _StopWalkingMapScreenState();
}

class _StopWalkingMapScreenState extends State<StopWalkingMapScreen> {
  static const String _mapHtmlBaseUrl =
      'https://appassets.androidplatform.net/';

  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initController();
    _loadHtmlContent();
  }

  void _initController() {
    final params = WebViewPlatform.instance == null
        ? const PlatformWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params);

    if (!kIsWeb) {
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0x00000000));
      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      );
    }

    _controller = controller;
  }

  void _loadHtmlContent() {
    final user = {
      'lon': widget.userPosition.longitude,
      'lat': widget.userPosition.latitude,
      'name': 'Voce',
    };
    final stop = {
      'lon': widget.stop.lon,
      'lat': widget.stop.lat,
      'name': 'Parada ${widget.stop.id}',
      'address': widget.stop.name,
    };

    final userJson = jsonEncode(user);
    final stopJson = jsonEncode(stop);

    final htmlContent =
        '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="referrer" content="origin">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@v8.2.0/ol.css">
        <style>
          body, html, #map { margin: 0; padding: 0; height: 100%; width: 100%; }
          .ol-popup {
            position: absolute;
            background-color: white;
            box-shadow: 0 1px 4px rgba(0,0,0,0.2);
            padding: 12px;
            border-radius: 8px;
            border: 1px solid #cccccc;
            bottom: 12px;
            left: -50px;
            min-width: 180px;
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
          const user = $userJson;
          const stop = $stopJson;

          const map = new ol.Map({
            target: 'map',
            layers: [
              new ol.layer.Tile({
                source: new ol.source.OSM()
              })
            ],
            view: new ol.View({
              center: ol.proj.fromLonLat([user.lon, user.lat]),
              zoom: 17
            })
          });

          const source = new ol.source.Vector();

          const walkingLine = new ol.Feature({
            geometry: new ol.geom.LineString([
              [user.lon, user.lat],
              [stop.lon, stop.lat]
            ]).transform('EPSG:4326', 'EPSG:3857'),
            name: 'Caminhada ate a parada'
          });

          walkingLine.setStyle(new ol.style.Style({
            stroke: new ol.style.Stroke({
              color: '#666666',
              width: 3,
              lineDash: [8, 8]
            })
          }));
          source.addFeature(walkingLine);

          function addCircleMarker(item, color, radius) {
            const point = new ol.geom.Point([item.lon, item.lat]);
            point.transform('EPSG:4326', 'EPSG:3857');
            const marker = new ol.Feature({
              geometry: point,
              name: item.address ? item.name + '<br>' + item.address : item.name
            });

            marker.setStyle(new ol.style.Style({
              image: new ol.style.Circle({
                radius: radius,
                fill: new ol.style.Fill({ color: color }),
                stroke: new ol.style.Stroke({ color: 'white', width: 3 })
              })
            }));
            source.addFeature(marker);
          }

          function addStopMarker(item) {
            const point = new ol.geom.Point([item.lon, item.lat]);
            point.transform('EPSG:4326', 'EPSG:3857');
            const marker = new ol.Feature({
              geometry: point,
              name: item.address ? item.name + '<br>' + item.address : item.name
            });

            marker.setStyle(new ol.style.Style({
              image: new ol.style.Icon({
                anchor: [0.5, 1],
                src: 'https://cdn-icons-png.flaticon.com/32/3448/3448339.png',
                scale: 1.0
              })
            }));
            source.addFeature(marker);
          }

          addCircleMarker(user, '#1E88E5', 9);
          addStopMarker(stop);

          const layer = new ol.layer.Vector({ source: source });
          map.addLayer(layer);

          map.getView().fit(source.getExtent(), {
            padding: [80, 60, 80, 60],
            duration: 800,
            maxZoom: 18
          });

          const popup = document.getElementById('popup');
          const popupOverlay = new ol.Overlay({
            element: popup,
            positioning: 'bottom-center',
            stopEvent: false
          });
          map.addOverlay(popupOverlay);

          map.on('click', function(evt) {
            const features = map.getFeaturesAtPixel(evt.pixel);
            if (features && features.length > 0) {
              const name = features[0].get('name');
              if (name) {
                popup.innerHTML = '<div><strong>' + name + '</strong></div>';
                popupOverlay.setPosition(evt.coordinate);
                popup.style.display = 'block';
              }
            } else {
              popup.style.display = 'none';
            }
          });
        </script>
      </body>
      </html>
    ''';

    _controller.loadHtmlString(
      htmlContent,
      baseUrl: _mapHtmlBaseUrl,
    ).then((_) {
      if (kIsWeb && mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parada ${widget.stop.id}'),
        actions: [
          IconButton(
            tooltip: 'Detalhes da parada',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StopDetailScreen(stop: widget.stop),
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
