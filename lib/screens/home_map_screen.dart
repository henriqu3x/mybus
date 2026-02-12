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
import 'real_time_selection_screen.dart';
import 'real_time_travel_screen.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';
import '../services/persistence_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';

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
  StreamSubscription<Position>? _positionStream;

  bool _hasActiveTrip = false;
  bool _hasCenteredMap = false;
  Map<String, dynamic>? _currentTripData;

  @override
  void initState() {
    super.initState();
    _initController();
    _checkActiveTrip(autoNav: false);
    _loadData();

    // Safety timeout: Force loading to finish after 8 seconds
    // This prevents the screen from being stuck cleanly if WebView callbacks fail
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        debugPrint("HomeMapScreen: Loading timed out, forcing display.");
        setState(() => _isLoading = false);
      }
    });
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

  Future<void> _checkActiveTrip({bool autoNav = false}) async {
    final trip = await PersistenceService().getActiveTrip();
    if (mounted) {
      setState(() {
        _hasActiveTrip = trip != null;
        _currentTripData = trip;
      });

      if (trip != null && autoNav) {
        _navigateToTrip();
      }
    }
  }

  Future<void> _loadData() async {
    // Start location stream in background (fire-and-forget) to avoid blocking map load
    _startLocationStream();

    _stops = await _kmlService.loadStopsMetadata();
    _loadHtmlContent();
  }

  Future<void> _startLocationStream() async {
    // 1. Check Service
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint("Location services disabled");
      return;
    }

    // 2. Check/Request Permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint("Location permission denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint("Location permission permanently denied");
      return;
    }

    // 3. Get Initial Position
    try {
      _userPosition = await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint("Error getting current position: $e");
    }

    // 4. Start Stream
    _stopLocationStream(); // Ensure clean slate
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          (Position position) {
            if (mounted) {
              _userPosition = position; // Update local state
              _updateUserMarkerInJS(position);
            }
          },
          onError: (e) {
            debugPrint("Location stream error: $e");
          },
        );
  }

  void _stopLocationStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _navigateToTrip() async {
    if (_currentTripData == null) return;

    // Stop Home stream to avoid conflict with RealTimeTravelScreen's foreground service
    _stopLocationStream();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RealTimeTravelScreen(
          lineName: _currentTripData!['lineName'],
          destinationStop: _currentTripData!['destination'],
          enableNotifications:
              _currentTripData!['enableNotifications'] == true,
          enableBackground:
              _currentTripData!['enableBackground'] == true,
        ),
      ),
    );

    // Restart Home stream when returning
    _checkActiveTrip(autoNav: false);
    _startLocationStream();
  }

  void _updateUserMarkerInJS(Position position) {
    // Only center the map on the first valid position update
    final shouldCenter = !_hasCenteredMap;
    if (shouldCenter) {
      _hasCenteredMap = true;
    }

    final jsCode =
        '''
    if (window.userFeature) {
      const newCoord = ol.proj.fromLonLat([${position.longitude}, ${position.latitude}]);
      
      // 1. Move o marcador
      window.userFeature.getGeometry().setCoordinates(newCoord);
      
      // 2. CENTRALIZA A TELA (Apenas na primeira vez)
      if ($shouldCenter) {
        map.getView().animate({
          center: newCoord,
          duration: 800
        });
      }
    }
  ''';
    _controller.runJavaScript(jsCode);
  }

  void _centerMapOnUser() {
    if (_userPosition == null) return;

    final js =
        '''
    {
      const view = map.getView();
      const c = ol.proj.fromLonLat([${_userPosition!.longitude}, ${_userPosition!.latitude}]);

      // força encerramento de interações ativas
      map.getInteractions().forEach(i => {
        if (i.getActive && i.getActive()) {
          i.setActive(false);
          i.setActive(true);
        }
      });

      view.animate({
        center: c,
        duration: 800
      });
    }
  ''';

    _controller.runJavaScript(js);
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
          
          window.userFeature = new ol.Feature({ 
              geometry: new ol.geom.Point(ol.proj.fromLonLat(userCenter))
          });

          window.userFeature.setStyle(new ol.style.Style({
              image: new ol.style.Circle({
                  radius: 10,
                  fill: new ol.style.Fill({color: 'blue'}),
                  stroke: new ol.style.Stroke({color: 'white', width: 3})
              })
          }));
          const userLayer = new ol.layer.Vector({
              source: new ol.source.Vector({ features: [window.userFeature] })
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
                  // AJUSTE AQUI: Adicionamos o maxZoom
                  map.getView().fit(extent, {
                      padding: [100, 100, 100, 100], 
                      duration: 500,
                      maxZoom: 17 // Altere este número para o nível de zoom que você achar ideal
                  });
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus_rounded, size: 28),
            const SizedBox(width: 12),
            const Text('No Ponto'),
          ],
        ),
        actions: [
          // 1. LINHAS
          IconButton(
            icon: const Icon(Icons.list_rounded),
            tooltip: 'Linhas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LinesScreen()),
              );
            },
            // 1. Linhas (Direto no App Bar)
          ),
          IconButton(
            icon: const Icon(Icons.location_on_rounded),
            tooltip: 'Viagem em Tempo Real',
            onPressed: () {
              _stopLocationStream();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RealTimeSelectionScreen(),
                ),
              ).then((_) {
                _checkActiveTrip(autoNav: false);
                _startLocationStream();
              });
            },
          ),
          // 2. viagem em tempo real (Direto no App Bar)
          IconButton(
            icon: const Icon(Icons.map_rounded),
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
          // 4. Menu Dropdown (Apenas Favoritos e Alertas)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'favorites') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FavoritesScreen(),
                  ),
                );
              } else if (value == 'alerts') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AlertSetupScreen(),
                  ),
                );
              } else if (value == 'terms') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsScreen(),
                  ),
                );
              } else if (value == 'privacy') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyScreen(),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'favorites',
                child: Row(
                  children: [
                    Icon(Icons.star_rounded),
                    SizedBox(width: 12),
                    Text('Favoritos'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'alerts',
                child: Row(
                  children: [
                    Icon(Icons.notifications_rounded),
                    SizedBox(width: 12),
                    Text('Alertas'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
               const PopupMenuItem<String>(
                value: 'terms',
                child: Row(
                  children: [
                    Icon(Icons.description_rounded),
                    SizedBox(width: 12),
                    Text('Termos de Uso'),
                  ],
                ),
              ),
               const PopupMenuItem<String>(
                value: 'privacy',
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_rounded),
                    SizedBox(width: 12),
                    Text('Políticas de Privacidade'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(
            controller: _controller,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          Positioned(
            right: 16,
            bottom: _hasActiveTrip
                ? 16
                : 16, // Adjust if trip button is present
            child: FloatingActionButton(
              heroTag: 'centerUser',
              onPressed: _centerMapOnUser,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: Icon(
                Icons.my_location,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _hasActiveTrip
          ? FloatingActionButton.extended(
              onPressed: _navigateToTrip,
              label: const Text('Retomar Viagem'),
              icon: const Icon(Icons.directions_bus),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel(); // Para o GPS
    super.dispose();
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.bus_alert_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parada ${widget.stop.id}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              if (widget.stop.name !=
                                  'Parada ${widget.stop.id}')
                                Text(
                                  widget.stop.name,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.stop.lines.length} linha(s) disponível(is)',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                      ),
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
                              horizontal: 12,
                              vertical: 6,
                            ),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    lineCode,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                              ),
                              title: Text(
                                'Linha $lineCode',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: schedules.isEmpty
                                  ? Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.tertiary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Sem mais saídas hoje',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.tertiary,
                                              ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Próximas: ${schedules.take(3).join(', ')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.secondary,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                              children: [
                                if (schedules.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Próximos horários:',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: schedules
                                              .take(10)
                                              .map(
                                                (time) => Chip(
                                                  label: Text(
                                                    time,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelMedium,
                                                  ),
                                                  backgroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer,
                                                  side: BorderSide.none,
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
