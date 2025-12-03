import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/linha.dart';
import '../models/itinerario.dart';
import '../models/horario.dart';
import '../providers/bus_provider.dart';
import '../utils/time_utils.dart';
import 'map_screen.dart';

class LineDetailScreen extends StatefulWidget {
  final Linha linha;

  const LineDetailScreen({super.key, required this.linha});

  @override
  State<LineDetailScreen> createState() => _LineDetailScreenState();
}

class _LineDetailScreenState extends State<LineDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _timer;
  Future<ItinerarioCompleto>? _itineraryFuture;
  Future<List<HorarioPosto>>? _scheduleFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize futures once
    final provider = Provider.of<BusProvider>(context, listen: false);
    _itineraryFuture = provider.getItinerario(widget.linha.numero);
    
    String today = DateFormat('yyyyMMdd').format(DateTime.now());
    _scheduleFuture = provider.getHorarios(widget.linha.numero, today);

    // Update every 30 seconds to keep the countdown fresh
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.linha.numeroNome),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Itinerário'),
            Tab(text: 'Horários'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildItineraryTab(), _buildScheduleTab()],
      ),
    );
  }

  Widget _buildItineraryTab() {
    return FutureBuilder<ItinerarioCompleto>(
      future: _itineraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar itinerário'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Nenhum itinerário encontrado'));
        }

        final itinerario = snapshot.data!;

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(text: 'Ida'),
                  Tab(text: 'Volta'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildItineraryList(itinerario.ida),
                    _buildItineraryList(itinerario.volta),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItineraryList(Itinerario? itinerario) {
    if (itinerario == null || itinerario.pontos.isEmpty) {
      return const Center(child: Text('Não disponível'));
    }

    return FutureBuilder<List<HorarioPosto>>(
      future: _scheduleFuture,
      builder: (context, snapshot) {
        String? nextDepartureTime;
        List<int> allDepartureMinutes = [];

        final now = TimeOfDay.now();
        final currentMinutes = now.hour * 60 + now.minute;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          // Collect departure times only for the matching control point
          HorarioPosto? matchingPosto;
          
          // Find the control point that matches the itinerary start point
          for (var posto in snapshot.data!) {
            if (posto.postoControle.toLowerCase() == itinerario.pontoInicial.toLowerCase() ||
                posto.postoControle.toLowerCase().contains(itinerario.pontoInicial.toLowerCase()) ||
                itinerario.pontoInicial.toLowerCase().contains(posto.postoControle.toLowerCase())) {
              matchingPosto = posto;
              break;
            }
          }
          
          // Fallback: if only one control point exists, use it
          if (matchingPosto == null && snapshot.data!.length == 1) {
            matchingPosto = snapshot.data!.first;
          }

          if (matchingPosto != null) {
            for (var h in matchingPosto.horarios) {
              try {
                final parts = h.horario.split(':');
                final hMinutes =
                    int.parse(parts[0]) * 60 + int.parse(parts[1]);
                allDepartureMinutes.add(hMinutes);
              } catch (e) {
                // ignore parse error
              }
            }
          }
          // Sort to ensure chronological order
          allDepartureMinutes.sort();

          // Find next departure from terminal for the header
          for (var mins in allDepartureMinutes) {
            if (mins > currentMinutes) {
              final h = mins ~/ 60;
              final m = mins % 60;
              nextDepartureTime =
                  '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
              break;
            }
          }
        }

        // Pre-calculate cumulative distances
        List<double> cumulativeDistances = [];
        double totalDist = 0;
        for (var ponto in itinerario.pontos) {
          cumulativeDistances.add(totalDist);
          totalDist += ponto.distanciaPercorrida;
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                    'Ponto Inicial: ${itinerario.pontoInicial}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (nextDepartureTime != null)
                    Text(
                      'Próxima saída: $nextDepartureTime',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    const Text(
                      'Sem próximas saídas hoje',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: itinerario.pontos.length,
                itemBuilder: (context, index) {
                  final ponto = itinerario.pontos[index];
                  final distance = cumulativeDistances[index];

                  String estimatedArrival = '--';
                  Color timeColor = Colors.black;

                  if (allDepartureMinutes.isNotEmpty) {
                    int travelMinutes =
                        TimeUtils.calculateTravelTimeMinutes(distance);
                    
                    // Find the earliest departure that reaches this stop in the future
                    int? bestArrivalMinutes;
                    
                    for (var depMins in allDepartureMinutes) {
                       int arrivalMins = depMins + travelMinutes;
                       if (arrivalMins > currentMinutes) {
                         bestArrivalMinutes = arrivalMins;
                         break; // Found the earliest valid bus
                       }
                    }

                    if (bestArrivalMinutes != null) {
                      int remaining = bestArrivalMinutes - currentMinutes;
                      estimatedArrival = '$remaining min';
                      if (remaining <= 5) {
                        timeColor = Colors.red;
                      } else if (remaining <= 15) {
                        timeColor = Colors.orange;
                      } else {
                        timeColor = Colors.green;
                      }
                    }
                  }

                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(ponto.nome),
                    subtitle: Text(
                      '${ponto.distanciaPercorrida}m do anterior',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.access_time, size: 16),
                        Text(
                          estimatedArrival,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: timeColor,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              MapScreen(title: ponto.nome),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScheduleTab() {
    return FutureBuilder<List<HorarioPosto>>(
      future: _scheduleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar horários'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('Nenhum horário encontrado para hoje'),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final posto = snapshot.data![index];
            return ExpansionTile(
              title: Text(posto.postoControle),
              children: [
                Wrap(
                  spacing: 8.0,
                  children: posto.horarios
                      .map(
                        (h) => Chip(
                          label: Text(h.horario),
                          backgroundColor: h.acessivel == 'sim'
                              ? Colors.blue[100]
                              : Colors.grey[200],
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
