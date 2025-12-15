import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../providers/bus_provider.dart';
import '../models/horario.dart';
import '../models/itinerario.dart';
import '../models/trip_segment.dart';
import '../models/favorito.dart';
import '../services/favorites_service.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';

class RouteDetailScreen extends StatefulWidget {
  final List<TripSegment> segments;
  final String origin;
  final String destination;
  final double totalDistance;
  final int totalTime;

  const RouteDetailScreen({
    super.key,
    required this.segments,
    required this.origin,
    required this.destination,
    required this.totalDistance,
    required this.totalTime,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  final Map<String, Future<List<HorarioPosto>>> _scheduleCache = {};
  final Map<String, Future<ItinerarioCompleto>> _itineraryCache = {};

  

  @override
  void initState() {
    super.initState();
    _preloadData();
  }

  void _preloadData() {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final today = DateFormat('yyyyMMdd').format(DateTime.now());

    // Preload schedules and itineraries for all segments
    for (var segment in widget.segments) {
      final lineNumber = _extractLineNumber(segment.lineName);
      if (lineNumber != null) {
        _scheduleCache[segment.lineName] = provider.getHorarios(
          lineNumber,
          today,
        );
        _itineraryCache[segment.lineName] = provider.getItinerario(lineNumber);
      }
    }
  }

  int? _extractLineNumber(String lineName) {
    // Extract number from format "051-Grande Circular I"
    final match = RegExp(r'^(\d+)').firstMatch(lineName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Build display segments by merging consecutive segments of the same line
    // base (ignoring _IDA/_VOLTA). This prevents duplicate cards when the bus
    // only changes direction but remains the same physical service.
    final displaySegments = _computeDisplaySegmentsForDisplay(widget.segments);
    // Calculate transfers ignoring same-line direction changes (IDA/VOLTA)
    int transfers = 0;
    for (int i = 0; i < widget.segments.length - 1; i++) {
      final current = widget.segments[i].lineName
          .replaceAll('_IDA', '')
          .replaceAll('_VOLTA', '');
      final next = widget.segments[i + 1].lineName
          .replaceAll('_IDA', '')
          .replaceAll('_VOLTA', '');
      if (current != next) {
        transfers++;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da Rota')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveRouteAsFavorite,
        icon: const Icon(Icons.star),
        label: const Text('Salvar Rota'),
        backgroundColor: Colors.amber,
      ),
      body: Column(
        children: [
          // Header with route summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.origin,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12.0, top: 4, bottom: 4),
                  child: Icon(Icons.more_vert, color: Colors.grey),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.destination,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      icon: Icons.access_time,
                      label: 'Tempo',
                      value: '${widget.totalTime} min',
                    ),
                    _buildSummaryItem(
                      icon: Icons.straighten,
                      label: 'Distância',
                      value:
                          '${(widget.totalDistance / 1000).toStringAsFixed(1)} km',
                    ),
                    _buildSummaryItem(
                      icon: Icons.swap_horiz,
                      label: 'Trocas',
                      value: transfers.toString(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Segment list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: displaySegments.length,
              itemBuilder: (context, index) {
                final entry = displaySegments[index];
                // compute whether next display segment is same base line
                bool isNextSameLine = false;
                if (index < displaySegments.length - 1) {
                  final currentBase = (entry['segment'] as TripSegment)
                      .lineName
                      .replaceAll('_IDA', '')
                      .replaceAll('_VOLTA', '');
                  final nextBase = (displaySegments[index + 1]['segment'] as TripSegment)
                      .lineName
                      .replaceAll('_IDA', '')
                      .replaceAll('_VOLTA', '');
                  if (currentBase == nextBase) isNextSameLine = true;
                }

                return _buildSegmentCard(entry['segment'] as TripSegment,
                    index,
                    lineKeys: entry['lineKeys'] as List<String>,
                    isNextSameLine: isNextSameLine);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSegmentCard(TripSegment segment, int index,
      {List<String>? lineKeys, bool isNextSameLine = false}) {
    // Try to find schedule/itinerary futures using provided lineKeys (original
    // segment names) to ensure we still use cached data when we merged display
    // segments.
    Future<List<HorarioPosto>>? scheduleF;
    Future<ItinerarioCompleto>? itineraryF;

    if (lineKeys != null) {
      for (var key in lineKeys) {
        if (_scheduleCache.containsKey(key)) {
          scheduleF = _scheduleCache[key] as Future<List<HorarioPosto>>;
          break;
        }
      }
      for (var key in lineKeys) {
        if (_itineraryCache.containsKey(key)) {
          itineraryF = _itineraryCache[key] as Future<ItinerarioCompleto>;
          break;
        }
      }
    }

    final itineraryFuture = itineraryF ?? _itineraryCache[segment.lineName] ?? _itineraryCacheFallback(segment);
    final scheduleFuture = scheduleF ?? _scheduleCache[segment.lineName] ?? _scheduleCacheFallback(segment);


    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Segment header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        segment.lineName
                            .replaceAll('_IDA', '')
                            .replaceAll('_VOLTA', ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${(segment.distance / 1000).toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Boarding point
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                    Container(width: 2, height: 40, color: Colors.grey[300]),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Embarque',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        segment.startStreetName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Alighting point
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isNextSameLine
                        ? Colors.orange
                        : Colors.red, // Orange for continuation
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNextSameLine ? 'Continuar no ônibus' : 'Desembarque',
                        style: TextStyle(
                          fontSize: 12,
                          color: isNextSameLine
                              ? Colors.orange[800]
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        segment.endStreetName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isNextSameLine)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            "(Mudança de sentido da linha)",
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Arrival time prediction
            if (scheduleFuture != null && itineraryFuture != null)
              _buildArrivalPrediction(segment, scheduleFuture, itineraryFuture),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalPrediction(
    TripSegment segment,
    Future<List<HorarioPosto>> scheduleFuture,
    Future<ItinerarioCompleto> itineraryFuture,
  ) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([scheduleFuture, itineraryFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Text(
            'Não foi possível carregar horários',
            style: TextStyle(color: Colors.grey),
          );
        }

        final horarios = snapshot.data![0] as List<HorarioPosto>;
        final itinerario = snapshot.data![1] as ItinerarioCompleto;

        if (horarios.isEmpty) {
          return const Text(
            'Sem horários disponíveis hoje',
            style: TextStyle(color: Colors.grey),
          );
        }

        // Calculate distance to boarding point and find matching itinerary
        final match = _calculateDistanceToPoint(
          itinerario,
          segment.startStreetName,
          segment.endStreetName,
        );

        if (match == null) {
          return const Text(
            'Ponto não encontrado no itinerário',
            style: TextStyle(color: Colors.grey),
          );
        }

        // Calculate next arrivals using the correct control point
        final arrivals = _calculateNextArrivals(
          horarios,
          match.distance,
          match
              .pontoInicial, // Use the itinerary's start point to match control point
          maxCount: 5,
        );

        if (arrivals.isEmpty) {
          return const Text(
            'Sem mais ônibus hoje',
            style: TextStyle(color: Colors.grey),
          );
        }

        final now = TimeOfDay.now();
        final currentMinutes = now.hour * 60 + now.minute;
        final nextArrival = arrivals.first;
        final minutesUntilArrival = nextArrival - currentMinutes;

        Color timeColor = Colors.green;
        if (minutesUntilArrival <= 5) {
          timeColor = Colors.red;
        } else if (minutesUntilArrival <= 15) {
          timeColor = Colors.orange;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Next bus countdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: timeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: timeColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: timeColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Próximo ônibus em ',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  Text(
                    '$minutesUntilArrival min',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: timeColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatMinutesToTime(nextArrival),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: timeColor,
                    ),
                  ),
                ],
              ),
            ),

            if (arrivals.length > 1) ...[
              const SizedBox(height: 12),
              const Text(
                'Próximos horários:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: arrivals.skip(1).take(4).map((arrivalMinutes) {
                  return Chip(
                    label: Text(_formatMinutesToTime(arrivalMinutes)),
                    backgroundColor: Colors.grey[200],
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  );
                }).toList(),
              ),
            ],
          ],
        );
      },
    );
  }

  _ItineraryMatch? _calculateDistanceToPoint(
    ItinerarioCompleto itinerarioCompleto,
    String startPointName,
    String endPointName,
  ) {
    // Try both directions
    for (var itinerario in [itinerarioCompleto.ida, itinerarioCompleto.volta]) {
      if (itinerario == null) continue;

      double currentDist = 0;
      double? startDist;
      int? startIndex;
      int? endIndex;

      for (int i = 0; i < itinerario.pontos.length; i++) {
        final ponto = itinerario.pontos[i];

        // Check for start point match
        if (startIndex == null) {
          if (_areNamesSimilar(ponto.nome, startPointName)) {
            startIndex = i;
            startDist = currentDist;
          }
        }

        // Check for end point match
        if (startIndex != null && endIndex == null) {
          if (_areNamesSimilar(ponto.nome, endPointName)) {
            endIndex = i;
          }
        }

        currentDist += ponto.distanciaPercorrida;
      }

      // If start is found, use this itinerary (even if end point is not found)
      // This handles cases where the segment spans across direction changes
      if (startIndex != null) {
        // If end point not found, it might be across direction change
        // In that case, just use the distance to the start point
        if (endIndex == null) {
          // The end point might be in the opposite direction
          // For now, return the start distance (this is better than showing error)
          return _ItineraryMatch(startDist!, itinerario.pontoInicial);
        }

        // Both found and start is before end, this is the correct itinerary
        if (startIndex < endIndex) {
          return _ItineraryMatch(startDist!, itinerario.pontoInicial);
        }
      }
    }
    return null;
  }

  List<int> _calculateNextArrivals(
    List<HorarioPosto> horarios,
    double distanceMeters,
    String pontoInicial, { // Ponto inicial do itinerário correspondente
    int maxCount = 5,
  }) {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final travelMinutes = TimeUtils.calculateTravelTimeMinutes(distanceMeters);

    List<int> arrivalTimes = [];

    // Encontrar o posto de controle que corresponde ao ponto inicial do itinerário
    HorarioPosto? matchingPosto;

    for (var posto in horarios) {
      if (_areNamesSimilar(posto.postoControle, pontoInicial)) {
        matchingPosto = posto;
        break;
      }
    }

    // Fallback: se não encontrar, tenta usar o primeiro se houver apenas um, ou logar erro
    if (matchingPosto == null && horarios.isNotEmpty) {
      // Se só tem um posto, usa ele (melhor que nada)
      if (horarios.length == 1) {
        matchingPosto = horarios.first;
      }
    }

    if (matchingPosto == null) {
      return arrivalTimes;
    }

    for (var h in matchingPosto.horarios) {
      try {
        final parts = h.horario.split(':');
        final departureMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        final arrivalMinutes = departureMinutes + travelMinutes;

        if (arrivalMinutes > currentMinutes) {
          arrivalTimes.add(arrivalMinutes);
        }
      } catch (e) {
        // Ignore parse errors
      }
    }

    arrivalTimes.sort();
    return arrivalTimes.take(maxCount).toList();
  }

  // Build display segments by merging consecutive TripSegments that belong
  // to the same line base (ignoring _IDA/_VOLTA). Each entry is a map with
  // 'segment' (a merged TripSegment) and 'lineKeys' (original line names)
  List<Map<String, dynamic>> _computeDisplaySegmentsForDisplay(List<TripSegment> segments) {
    final List<Map<String, dynamic>> result = [];
    if (segments.isEmpty) return result;

    String currentBase = segments.first.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
    String startStreet = segments.first.startStreetName;
    int startStop = segments.first.startStopId;
    double distance = segments.first.distance;
    String endStreet = segments.first.endStreetName;
    int endStop = segments.first.endStopId;
    List<String> lineKeys = [segments.first.lineName];

    for (int i = 1; i < segments.length; i++) {
      final s = segments[i];
      final base = s.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
      if (base == currentBase) {
        // merge into current
        distance += s.distance;
        endStreet = s.endStreetName;
        endStop = s.endStopId;
        lineKeys.add(s.lineName);
      } else {
        // flush current merged segment
        final merged = TripSegment(
          type: 'BUS',
          lineName: currentBase,
          startStreetName: startStreet,
          endStreetName: endStreet,
          distance: distance,
          startStopId: startStop,
          endStopId: endStop,
        );
        result.add({'segment': merged, 'lineKeys': List<String>.from(lineKeys)});

        // start new
        currentBase = base;
        startStreet = s.startStreetName;
        startStop = s.startStopId;
        distance = s.distance;
        endStreet = s.endStreetName;
        endStop = s.endStopId;
        lineKeys = [s.lineName];
      }
    }

    // flush last
    final merged = TripSegment(
      type: 'BUS',
      lineName: currentBase,
      startStreetName: startStreet,
      endStreetName: endStreet,
      distance: distance,
      startStopId: startStop,
      endStopId: endStop,
    );
    result.add({'segment': merged, 'lineKeys': List<String>.from(lineKeys)});

    return result;
  }

  Future<List<HorarioPosto>>? _scheduleCacheFallback(TripSegment segment) {
    final base = segment.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
    // 1) try to find by base
    for (var key in _scheduleCache.keys) {
      if (key.replaceAll('_IDA', '').replaceAll('_VOLTA', '') == base) {
        return _scheduleCache[key];
      }
    }
    // 2) try to find by line number
    final num = _extractLineNumber(segment.lineName);
    if (num != null) {
      for (var key in _scheduleCache.keys) {
        final kNum = _extractLineNumber(key);
        if (kNum == num) return _scheduleCache[key];
      }
    }
    return null;
  }

  Future<ItinerarioCompleto>? _itineraryCacheFallback(TripSegment segment) {
    final base = segment.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
    for (var key in _itineraryCache.keys) {
      if (key.replaceAll('_IDA', '').replaceAll('_VOLTA', '') == base) {
        return _itineraryCache[key];
      }
    }
    final num = _extractLineNumber(segment.lineName);
    if (num != null) {
      for (var key in _itineraryCache.keys) {
        final kNum = _extractLineNumber(key);
        if (kNum == num) return _itineraryCache[key];
      }
    }
    return null;
    return null;
  }

  bool _areNamesSimilar(String name1, String name2) {
    final n1 = _normalizeName(name1);
    final n2 = _normalizeName(name2);

    // 1. Direct containment check (fast path)
    if (n1.contains(n2) || n2.contains(n1)) return true;

    // 2. Token-based matching only as fallback (slower but more flexible)
    final words1 = n1.split(' ').where((w) => w.length > 2).toSet();
    final words2 = n2.split(' ').where((w) => w.length > 2).toSet();

    if (words1.isEmpty || words2.isEmpty) return false;

    final intersection = words1.intersection(words2);

    // If 60% or more words match, consider it similar
    return intersection.length >= words1.length * 0.6 ||
        intersection.length >= words2.length * 0.6;
  }

  String _normalizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(
          RegExp(r'^\d+-'),
          '',
        ) // Remove numeric prefixes like "01-", "13-"
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(
          RegExp(r'\b(de|da|do|dos|das|e|o|a)\b'),
          '',
        ) // Remove prepositions
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse spaces
        .trim();
  }

  String _formatMinutesToTime(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<void> _saveRouteAsFavorite() async {
    try {
      // Serialize route data to JSON
      final routeData = {
        'origin': widget.origin,
        'destination': widget.destination,
        'totalDistance': widget.totalDistance,
        'totalTime': widget.totalTime,
        'segments': widget.segments
            .map(
              (s) => {
                'type': s.type,
                'lineName': s.lineName,
                'startStreetName': s.startStreetName,
                'endStreetName': s.endStreetName,
                'distance': s.distance,
              },
            )
            .toList(),
      };

      final routeDataJson = jsonEncode(routeData);

      // Create favorite
      final favorito = Favorito(
        tipo: FavoritoType.ROUTE,
        entityId: '${widget.origin}_${widget.destination}',
        displayName: '${widget.origin} → ${widget.destination}',
        routeData: routeDataJson,
      );

      await FavoritesService().addFavorite(favorito);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rota salva nos favoritos!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar rota: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ItineraryMatch {
  final double distance;
  final String pontoInicial;

  _ItineraryMatch(this.distance, this.pontoInicial);
}
