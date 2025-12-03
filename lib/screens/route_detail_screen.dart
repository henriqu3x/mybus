import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bus_provider.dart';
import '../models/horario.dart';
import '../models/itinerario.dart';
import '../models/trip_segment.dart';
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
        _scheduleCache[segment.lineName] = provider.getHorarios(lineNumber, today);
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
    final transfers = widget.segments.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Rota'),
      ),
      body: Column(
        children: [
          // Header with route summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
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
                      value: '${(widget.totalDistance / 1000).toStringAsFixed(1)} km',
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
              itemCount: widget.segments.length,
              itemBuilder: (context, index) {
                return _buildSegmentCard(widget.segments[index], index);
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentCard(TripSegment segment, int index) {
    final scheduleFuture = _scheduleCache[segment.lineName];
    final itineraryFuture = _itineraryCache[segment.lineName];

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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_bus, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        segment.lineName,
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
                    Container(
                      width: 2,
                      height: 40,
                      color: Colors.grey[300],
                    ),
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
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Desembarque',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
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
                    ],
                  ),
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            // Arrival time prediction
            if (scheduleFuture != null && itineraryFuture != null)
              _buildArrivalPrediction(
                segment,
                scheduleFuture,
                itineraryFuture,
              ),
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
          match.pontoInicial, // Use the itinerary's start point to match control point
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
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
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
        if (startIndex == null && 
           (ponto.nome.contains(startPointName) || startPointName.contains(ponto.nome))) {
          startIndex = i;
          startDist = currentDist;
        }
        
        // Check for end point match
        if (endIndex == null && 
           (ponto.nome.contains(endPointName) || endPointName.contains(ponto.nome))) {
          endIndex = i;
        }

        currentDist += ponto.distanciaPercorrida;
      }

      // If both found and start is before end, this is the correct itinerary
      if (startIndex != null && endIndex != null && startIndex < endIndex) {
        return _ItineraryMatch(startDist!, itinerario.pontoInicial);
      }
    }
    return null;
  }

  List<int> _calculateNextArrivals(
    List<HorarioPosto> horarios,
    double distanceMeters,
    String pontoInicial, // Ponto inicial do itinerário correspondente
    {int maxCount = 5}
  ) {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final travelMinutes = TimeUtils.calculateTravelTimeMinutes(distanceMeters);

    List<int> arrivalTimes = [];

    // Encontrar o posto de controle que corresponde ao ponto inicial do itinerário
    HorarioPosto? matchingPosto;
    
    for (var posto in horarios) {
      // Verificar correspondência entre posto de controle e ponto inicial do itinerário
      if (posto.postoControle.toLowerCase() == pontoInicial.toLowerCase() ||
          posto.postoControle.toLowerCase().contains(pontoInicial.toLowerCase()) ||
          pontoInicial.toLowerCase().contains(posto.postoControle.toLowerCase())) {
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
    
    if (matchingPosto == null) return arrivalTimes;

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

  String _formatMinutesToTime(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

class _ItineraryMatch {
  final double distance;
  final String pontoInicial;
  
  _ItineraryMatch(this.distance, this.pontoInicial);
}

