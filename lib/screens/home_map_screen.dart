import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../services/kml_service.dart';
import '../providers/bus_provider.dart';
import 'favorites_screen.dart';
import 'route_planner_screen.dart';
import 'alert_setup_screen.dart';
import 'lines_screen.dart';
import 'stop_detail_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late final WebViewController _controller;
  final KmlService _kmlService = KmlService();
  bool _isLoading = true;
  List<StopInfo> _stops = [];
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _initController();
    _loadData();
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

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('mybus://stop/')) {
              final stopIdStr = request.url.replaceFirst('mybus://stop/', '');
              final stopId = int.tryParse(stopIdStr);
              if (stopId != null) {
                _showStopDetails(stopId);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    }

    _controller = controller;
  }

  Future<void> _loadData() async {
    // 1. Get User Location (Permission check)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Handle service disabled
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.deniedForever &&
          permission != LocationPermission.denied) {
        _userPosition = await Geolocator.getCurrentPosition();
      }
    } catch (e) {
      print("Error getting location: $e");
    }

    // 2. Load Stops
    _stops = await _kmlService.loadStopsMetadata();

    // 3. Render Map
    _loadHtmlContent();
  }

  void _showStopDetails(int stopId) {
    final stop = _stops.firstWhere(
      (s) => s.id == stopId,
      orElse: () =>
          StopInfo(id: 0, name: 'Desconhecido', lat: 0, lon: 0, lines: []),
    );
    if (stop.id == 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => StopDetailScreen(stop: stop)),
    );
  }

  void _loadHtmlContent() {
    final stopsData = _stops.map((s) => [s.id, s.lon, s.lat]).toList();
    final stopsJson = jsonEncode(stopsData);

    final userLat = _userPosition?.latitude ?? -3.7319;
    final userLon = _userPosition?.longitude ?? -38.5267;

    final htmlContent =
        '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>body, html, #map { margin: 0; padding: 0; height: 100%; width: 100%; }</style>
        <script src="https://cdn.jsdelivr.net/npm/ol@v8.2.0/dist/ol.js"></script>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@v8.2.0/ol.css">
      </head>
      <body>
        <div id="map"></div>
        <script>
          const stopsData = $stopsJson;
          const userCenter = [$userLon, $userLat];

          const map = new ol.Map({
            target: 'map',
            layers: [ new ol.layer.Tile({ source: new ol.source.OSM() }) ],
            view: new ol.View({
              center: ol.proj.fromLonLat(userCenter),
              zoom: 15
            })
          });

          const features = stopsData.map(stop => {
             const f = new ol.Feature({
                 geometry: new ol.geom.Point(ol.proj.fromLonLat([stop[1], stop[2]]))
             });
             f.setId(stop[0]);
             return f;
          });

          const source = new ol.source.Vector({ features: features });
          
          const clusterSource = new ol.source.Cluster({
              distance: 40,
              source: source
          });

          const styleCache = {};
          const clusters = new ol.layer.Vector({
              source: clusterSource,
              style: function (feature) {
                  const size = feature.get('features').length;
                  let style = styleCache[size];
                  if (!style) {
                      if (size > 1) {
                           style = new ol.style.Style({
                               image: new ol.style.Circle({
                                   radius: 10 + Math.min(size, 20),
                                   stroke: new ol.style.Stroke({ color: '#fff' }),
                                   fill: new ol.style.Fill({ color: '#3399CC' })
                               }),
                               text: new ol.style.Text({
                                   text: size.toString(),
                                   fill: new ol.style.Fill({ color: '#fff' })
                               })
                           });
                      } else {
                          style = new ol.style.Style({
                              image: new ol.style.Icon({
                                  anchor: [0.5, 1],
                                  src: 'https://cdn-icons-png.flaticon.com/32/3448/3448339.png',
                                  scale: 1.0
                              })
                          });
                      }
                      styleCache[size] = style;
                  }
                  return style;
              }
          });

          map.addLayer(clusters);
          
          const userFeature = new ol.Feature({
               geometry: new ol.geom.Point(ol.proj.fromLonLat(userCenter))
          });
          userFeature.setStyle(new ol.style.Style({
              image: new ol.style.Circle({
                  radius: 8,
                  fill: new ol.style.Fill({color: 'blue'}),
                  stroke: new ol.style.Stroke({color: 'white', width: 2})
              })
          }));
          const userLayer = new ol.layer.Vector({
             source: new ol.source.Vector({ features: [userFeature] })
          });
          map.addLayer(userLayer);

          map.on('click', function(evt) {
              const feature = map.forEachFeatureAtPixel(evt.pixel, function(feature) {
                  return feature;
              });
              
              if (feature) {
                  const items = feature.get('features');
                  if (items && items.length === 1) {
                      const stopId = items[0].getId();
                      window.location.href = 'mybus://stop/' + stopId;
                  } else if (items && items.length > 1) {
                       const extent = feature.getGeometry().getExtent();
                       map.getView().fit(extent, {padding: [100, 100, 100, 100], duration: 500});
                  }
              }
          });
        </script>
      </body>
      </html>
    ''';

    _controller.loadHtmlString(htmlContent).then((_) {
      if (kIsWeb && mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Ponto'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.star),
            tooltip: 'Favoritos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FavoritesScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Linhas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LinesScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Planejador',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RoutePlannerScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Alertas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AlertSetupScreen(),
                ),
              );
            },
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

// Bottom sheet widget que carrega horários automaticamente
class _StopSchedulesSheet extends StatefulWidget {
  final StopInfo stop;
  const _StopSchedulesSheet({required this.stop});

  @override
  State<_StopSchedulesSheet> createState() => _StopSchedulesSheetState();
}

class _StopSchedulesSheetState extends State<_StopSchedulesSheet> {
  Map<String, List<String>> _schedules = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final now = DateTime.now();
    final dateStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

    Map<String, List<String>> result = {};

    for (String lineCode in widget.stop.lines) {
      final lineId = int.tryParse(lineCode);
      if (lineId == null) continue;

      try {
        final horariosPosto = await provider.getHorarios(lineId, dateStr);
        List<String> allTimes = [];
        for (var posto in horariosPosto) {
          allTimes.addAll(posto.horarios.map((h) => h.horario));
        }

        // Filter upcoming times
        final upcoming = allTimes.where((t) {
          try {
            final parts = t.split(':');
            final min = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            return min >= currentMinutes;
          } catch (e) {
            return false;
          }
        }).toList();

        result[lineCode] = upcoming;
      } catch (e) {
        result[lineCode] = [];
      }
    }

    if (mounted) {
      setState(() {
        _schedules = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parada ${widget.stop.id}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.stop.name != 'Parada ${widget.stop.id}')
                      Text(
                        widget.stop.name,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.stop.lines.length} linha(s)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.stop.lines.length,
                        itemBuilder: (context, index) {
                          final lineCode = widget.stop.lines[index];
                          final schedules = _schedules[lineCode] ?? [];

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text(
                                  lineCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Linha $lineCode',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: schedules.isEmpty
                                  ? const Text(
                                      'Sem mais saídas hoje',
                                      style: TextStyle(color: Colors.orange),
                                    )
                                  : Text(
                                      'Próximas: ${schedules.take(3).join(', ')}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                      ),
                                    ),
                              children: [
                                if (schedules.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Próximos horários:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: schedules
                                              .take(10)
                                              .map(
                                                (time) => Chip(
                                                  label: Text(time),
                                                  backgroundColor:
                                                      Colors.blue[100],
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
