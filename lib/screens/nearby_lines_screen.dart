import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/logradouro.dart';
import '../models/trip_segment.dart';
import '../providers/bus_provider.dart';
import '../services/kml_service.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';
import 'line_detail_screen.dart';
import 'route_detail_screen.dart';
import 'route_map_screen.dart';
import 'stop_detail_screen.dart';

class NearbyLinesScreen extends StatefulWidget {
  final Position? initialPosition;

  const NearbyLinesScreen({super.key, this.initialPosition});

  @override
  State<NearbyLinesScreen> createState() => _NearbyLinesScreenState();
}

class _NearbyLinesScreenState extends State<NearbyLinesScreen> {
  static const double _radiusMeters = 200;

  final KmlService _kmlService = KmlService();
  Position? _position;
  List<StopInfo> _nearbyStops = [];
  List<int> _nearbyOriginApiIds = [];
  List<_NearbyLine> _nearbyLines = [];
  Logradouro? _destination;
  List<_NearbyRoutePlan> _routePlans = [];
  int _selectedRouteIndex = 0;
  bool _loadingNearby = true;
  bool _calculatingRoute = false;
  bool _hasCalculatedRoute = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScreenData();
    });
  }

  Future<void> _loadScreenData() async {
    final provider = Provider.of<BusProvider>(context, listen: false);
    setState(() {
      _loadingNearby = true;
      _message = null;
    });

    try {
      _position = widget.initialPosition ?? await _getCurrentPosition();
      if (_position == null) {
        setState(() {
          _message = 'Nao foi possivel obter sua localizacao.';
          _loadingNearby = false;
        });
        return;
      }

      await Future.wait([
        provider.fetchLinhas(),
        provider.fetchLogradouros(),
        provider.buildGraph(),
      ]);

      final stops = await _kmlService.findStopsNearLocation(
        _position!.latitude,
        _position!.longitude,
        radiusMeters: _radiusMeters,
      );
      final originApiIds = await _kmlService.getApiIdsForStopIds(
        stops.map((stop) => stop.id),
      );

      if (!mounted) return;
      setState(() {
        _nearbyStops = stops;
        _nearbyOriginApiIds = originApiIds;
        _nearbyLines = _groupStopsByLine(stops);
        _loadingNearby = false;
        if (stops.isEmpty) {
          _message = 'Nenhuma parada encontrada em ate 200 metros.';
        } else if (originApiIds.isEmpty) {
          _message =
              'Encontrei paradas proximas, mas nao consegui vincula-las ao planejador.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Erro ao carregar linhas proximas.';
        _loadingNearby = false;
      });
    }
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  List<_NearbyLine> _groupStopsByLine(List<StopInfo> stops) {
    final byLine = <String, List<StopInfo>>{};

    for (final stop in stops) {
      for (final line in stop.lines) {
        byLine.putIfAbsent(line.trim(), () => []).add(stop);
      }
    }

    final result = byLine.entries
        .map((entry) => _NearbyLine(code: entry.key, stops: entry.value))
        .toList();

    result.sort((a, b) {
      final aNum = int.tryParse(a.code) ?? 999999;
      final bNum = int.tryParse(b.code) ?? 999999;
      final numberCompare = aNum.compareTo(bNum);
      if (numberCompare != 0) return numberCompare;
      return a.code.compareTo(b.code);
    });

    return result;
  }

  Future<void> _calculateNearbyRoute() async {
    if (_destination == null ||
        _nearbyOriginApiIds.isEmpty ||
        _nearbyLines.isEmpty) {
      return;
    }

    setState(() {
      _calculatingRoute = true;
      _hasCalculatedRoute = true;
      _routePlans = [];
      _selectedRouteIndex = 0;
    });

    final provider = Provider.of<BusProvider>(context, listen: false);
    final allowedLineCodes = _nearbyLines.map((line) => line.code).toSet();
    final plans = <_NearbyRoutePlan>[];
    final seen = <String>{};

    for (final originId in _nearbyOriginApiIds) {
      if (originId == _destination!.id) continue;

      final routes = await provider.findRoutes(
        originId,
        _destination!.id,
        allowedFirstLineCodes: allowedLineCodes,
      );

      for (final route in routes) {
        if (route.isEmpty) continue;
        final signature = route.map((edge) => edge.lineName).join('>');
        if (!seen.add('$originId|$signature')) continue;

        plans.add(
          _NearbyRoutePlan(
            originApiId: originId,
            originName: _logradouroNameFor(originId),
            destination: _destination!,
            route: route,
          ),
        );
      }
    }

    plans.sort((a, b) => _scoreRoute(a.route).compareTo(_scoreRoute(b.route)));

    if (!mounted) return;
    setState(() {
      _routePlans = plans.take(3).toList();
      _calculatingRoute = false;
    });
  }

  String _logradouroNameFor(int id) {
    final provider = Provider.of<BusProvider>(context, listen: false);
    for (final logradouro in provider.logradouros) {
      if (logradouro.id == id) return logradouro.nome;
    }
    return 'Parada proxima';
  }

  double _scoreRoute(List<GraphEdge> route) {
    final distance = route.fold<double>(0, (sum, edge) => sum + edge.weight);
    var transfers = 0;
    for (var i = 0; i < route.length - 1; i++) {
      if (_lineBase(route[i].lineName) != _lineBase(route[i + 1].lineName)) {
        transfers++;
      }
    }
    return distance + (transfers * 50000);
  }

  List<TripSegment> _groupRouteSegments(_NearbyRoutePlan plan) {
    final route = plan.route;
    if (route.isEmpty) return [];

    final segments = <TripSegment>[];
    var currentStartStreet = plan.originName;
    var currentStartLogId = plan.originApiId;
    var currentLine = route.first.lineName;
    var currentLineBase = _lineBase(currentLine);
    var currentDistance = 0.0;

    for (var i = 0; i < route.length; i++) {
      final edge = route[i];
      final edgeLineBase = _lineBase(edge.lineName);

      if (edgeLineBase == currentLineBase) {
        if (edge.lineName == currentLine) {
          currentDistance += edge.weight;
        } else {
          final previousEdge = route[i - 1];
          segments.add(
            TripSegment(
              type: 'BUS',
              lineName: currentLine,
              startStreetName: currentStartStreet,
              endStreetName: previousEdge.destination.name,
              distance: currentDistance,
              startStopId: currentStartLogId,
              endStopId: previousEdge.destination.id,
            ),
          );
          currentLine = edge.lineName;
          currentLineBase = edgeLineBase;
          currentStartStreet = previousEdge.destination.name;
          currentStartLogId = previousEdge.destination.id;
          currentDistance = edge.weight;
        }
      } else {
        final previousEdge = route[i - 1];
        segments.add(
          TripSegment(
            type: 'BUS',
            lineName: currentLine,
            startStreetName: currentStartStreet,
            endStreetName: previousEdge.destination.name,
            distance: currentDistance,
            startStopId: currentStartLogId,
            endStopId: previousEdge.destination.id,
          ),
        );
        currentLine = edge.lineName;
        currentLineBase = edgeLineBase;
        currentStartStreet = previousEdge.destination.name;
        currentStartLogId = previousEdge.destination.id;
        currentDistance = edge.weight;
      }
    }

    segments.add(
      TripSegment(
        type: 'BUS',
        lineName: currentLine,
        startStreetName: currentStartStreet,
        endStreetName: plan.destination.nome,
        distance: currentDistance,
        startStopId: currentStartLogId,
        endStopId: plan.destination.id,
      ),
    );

    return segments;
  }

  String _lineBase(String lineName) {
    return lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
  }

  int _transferCount(List<TripSegment> segments) {
    var count = 0;
    for (var i = 0; i < segments.length - 1; i++) {
      if (_lineBase(segments[i].lineName) !=
          _lineBase(segments[i + 1].lineName)) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linhas perto de voce'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadingNearby ? null : _loadScreenData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingNearby
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadScreenData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  if (_message != null) _buildMessage(_message!),
                  _buildNearbyLines(),
                  const SizedBox(height: 20),
                  _buildPlanner(),
                  const SizedBox(height: 16),
                  _buildRouteResults(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.near_me,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_nearbyLines.length} linha(s) em ${_nearbyStops.length} parada(s) num raio de 200 m',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(message, style: TextStyle(color: Colors.orange[800])),
    );
  }

  Widget _buildNearbyLines() {
    if (_nearbyLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Linhas proximas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ..._nearbyLines.map(_buildLineTile),
      ],
    );
  }

  Widget _buildLineTile(_NearbyLine nearbyLine) {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final line = provider.getLineByNumber(nearbyLine.code);

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            nearbyLine.code,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(line?.numeroNome ?? 'Linha ${nearbyLine.code}'),
        subtitle: Text(
          '${nearbyLine.stops.length} parada(s) perto de voce',
        ),
        children: [
          for (final stop in nearbyLine.stops)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text('Parada ${stop.id}'),
              subtitle: Text(stop.name),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StopDetailScreen(stop: stop),
                  ),
                );
              },
            ),
          if (line != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LineDetailScreen(linha: line),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_bus),
                label: const Text('Ver linha'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanner() {
    final provider = Provider.of<BusProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Planejar com essas linhas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Autocomplete<Logradouro>(
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<Logradouro>.empty();
            }
            final query = textEditingValue.text.toLowerCase();
            return provider.logradouros.where(
              (option) => option.nome.toLowerCase().contains(query),
            );
          },
          displayStringForOption: (option) => option.nome,
          onSelected: (selection) {
            setState(() => _destination = selection);
          },
          fieldViewBuilder: (
            context,
            textEditingController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Destino',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _destination != null &&
                    !_calculatingRoute &&
                    _nearbyOriginApiIds.isNotEmpty &&
                    _nearbyLines.isNotEmpty
                ? _calculateNearbyRoute
                : null,
            icon: _calculatingRoute
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route),
            label: Text(
              _calculatingRoute ? 'Calculando...' : 'Encontrar melhor rota',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteResults() {
    if (_calculatingRoute) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCalculatedRoute) {
      return const SizedBox.shrink();
    }

    if (_routePlans.isEmpty) {
      return const Text(
        'Nenhuma rota encontrada usando uma linha proxima como primeiro onibus.',
      );
    }

    final selectedPlan = _routePlans[_selectedRouteIndex];
    final segments = _groupRouteSegments(selectedPlan);
    final totalDistance = segments.fold<double>(
      0,
      (sum, segment) => sum + segment.distance,
    );
    final transfers = _transferCount(segments);
    final totalTime =
        TimeUtils.calculateTravelTimeMinutes(totalDistance) + transfers * 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Melhores opcoes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_routePlans.length > 1)
          ...List.generate(_routePlans.length, (index) {
            final plan = _routePlans[index];
            final planSegments = _groupRouteSegments(plan);
            final distance = planSegments.fold<double>(
              0,
              (sum, segment) => sum + segment.distance,
            );

            return RadioListTile<int>(
              value: index,
              groupValue: _selectedRouteIndex,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRouteIndex = value);
                }
              },
              title: Text('Opcao ${index + 1}'),
              subtitle: Text(
                '${(distance / 1000).toStringAsFixed(1)} km saindo de ${plan.originName}',
              ),
            );
          }),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Primeiro onibus: ${_lineBase(segments.first.lineName)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Origem: ${selectedPlan.originName}'),
                Text('Destino: ${selectedPlan.destination.nome}'),
                Text(
                  'Tempo estimado: $totalTime min - ${(totalDistance / 1000).toStringAsFixed(1)} km',
                ),
                const SizedBox(height: 12),
                for (final segment in segments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Linha ${_lineBase(segment.lineName)}: ${segment.startStreetName} ate ${segment.endStreetName}',
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteMapScreen(
                                segments: segments,
                                originApiId: selectedPlan.originApiId,
                                destinationApiId: selectedPlan.destination.id,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Mapa'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteDetailScreen(
                                segments: segments,
                                origin: selectedPlan.originName,
                                destination: selectedPlan.destination.nome,
                                totalDistance: totalDistance,
                                totalTime: totalTime,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: const Text('Detalhes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NearbyLine {
  final String code;
  final List<StopInfo> stops;

  _NearbyLine({required this.code, required this.stops});
}

class _NearbyRoutePlan {
  final int originApiId;
  final String originName;
  final Logradouro destination;
  final List<GraphEdge> route;

  _NearbyRoutePlan({
    required this.originApiId,
    required this.originName,
    required this.destination,
    required this.route,
  });
}
