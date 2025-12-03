import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/linha.dart';
import '../models/itinerario.dart';
import '../models/horario.dart';
import '../models/bus_stop.dart';
import '../providers/bus_provider.dart';
import '../utils/time_utils.dart';
import '../services/stop_service.dart';
import '../services/itinerary_stop_mapper.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
<<<<<<< HEAD
<<<<<<< HEAD
    
    // Initialize stop service asynchronously
    _initializeStopService();
    
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
=======
=======
>>>>>>> parent of 07d42ee (upd versão 1.5)
    // Fetch data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BusProvider>(
        context,
        listen: false,
      ).getItinerario(widget.linha.numero);
      String today = DateFormat('yyyyMMdd').format(DateTime.now());
      Provider.of<BusProvider>(
        context,
        listen: false,
      ).getHorarios(widget.linha.numero, today);
<<<<<<< HEAD
>>>>>>> parent of 07d42ee (upd versão 1.5)
    });
  }

  Future<void> _initializeStopService() async {
    await StopService().loadStops();
  }

=======
    });
  }

>>>>>>> parent of 07d42ee (upd versão 1.5)
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
    return Consumer<BusProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<ItinerarioCompleto>(
          future: provider.getItinerario(widget.linha.numero),
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
<<<<<<< HEAD
<<<<<<< HEAD
              Expanded(
                child: TabBarView(
                  children: [
                    _buildItineraryList(itinerario.ida, 'Ida'),
                    _buildItineraryList(itinerario.volta, 'Volta'),
                  ],
                ),
              ),
            ],
          ),
=======
            );
          },
>>>>>>> parent of 07d42ee (upd versão 1.5)
=======
            );
          },
>>>>>>> parent of 07d42ee (upd versão 1.5)
        );
      },
    );
  }

  Widget _buildItineraryList(Itinerario? itinerario, String direction) {
    if (itinerario == null || itinerario.pontos.isEmpty) {
      return const Center(child: Text('Não disponível'));
    }

    return Consumer<BusProvider>(
      builder: (context, provider, child) {
        String today = DateFormat('yyyyMMdd').format(DateTime.now());

        return FutureBuilder<List<HorarioPosto>>(
          future: provider.getHorarios(widget.linha.numero, today),
          builder: (context, snapshot) {
            String? nextDepartureTime;

            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              // Find the next departure time from the control point
              // We assume the first control point matches the start of the itinerary (simplification)
              // In a real app, we'd match the 'postoControle' name with 'pontoInicial'

              final now = TimeOfDay.now();
              final currentMinutes = now.hour * 60 + now.minute;

              // Flatten all schedules to find the absolute next departure
              // Or better, find the schedule for the relevant direction.
              // Since the API doesn't explicitly link direction to schedule, we'll take the first schedule list found
              // that has a departure after now.

              for (var posto in snapshot.data!) {
                for (var h in posto.horarios) {
                  try {
                    final parts = h.horario.split(':');
                    final hMinutes =
                        int.parse(parts[0]) * 60 + int.parse(parts[1]);

                    if (hMinutes > currentMinutes) {
                      nextDepartureTime = h.horario;
                      break;
                    }
                  } catch (e) {
                    // ignore parse error
                  }
                }
                if (nextDepartureTime != null) break;
              }
            }

            // Pre-calculate cumulative distances
            List<double> cumulativeDistances = [];
            double totalDist = 0;
            for (var ponto in itinerario.pontos) {
              totalDist += ponto.distanciaPercorrida;
              cumulativeDistances.add(totalDist);
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
<<<<<<< HEAD
<<<<<<< HEAD
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

                  // Get stops for this street
                  final mapper = ItineraryStopMapper();
                  final stopsForStreet = mapper.groupStopsByStreet(
                    itinerario,
                    widget.linha.numero.toString(),
                    direction,
                  )[ponto] ?? [];

                  return ExpansionTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(ponto.nome),
                    subtitle: Text(
                      '${ponto.distanciaPercorrida}m do anterior',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, size: 16),
=======
                      if (nextDepartureTime != null)
>>>>>>> parent of 07d42ee (upd versão 1.5)
=======
                      if (nextDepartureTime != null)
>>>>>>> parent of 07d42ee (upd versão 1.5)
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
<<<<<<< HEAD
<<<<<<< HEAD
                      ],
                    ),
                    children: stopsForStreet.isEmpty
                        ? [const ListTile(title: Text('Nenhuma parada disponível'))]
                        : stopsForStreet.map((stop) {
                            return ListTile(
                              leading: const Icon(Icons.location_on, size: 20),
                              title: Text(stop.formattedStreetName),
                              subtitle: Text('Parada ID: ${stop.stopId}'),
                              trailing: const Icon(Icons.map, size: 20),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MapScreen(
                                      title: '${stop.formattedStreetName} - Parada ${stop.stopId}',
                                      latitude: stop.latitude,
                                      longitude: stop.longitude,
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
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
=======
=======
>>>>>>> parent of 07d42ee (upd versão 1.5)
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: itinerario.pontos.length,
                    itemBuilder: (context, index) {
                      final ponto = itinerario.pontos[index];
                      final distance = cumulativeDistances[index];

                      String estimatedArrival = '--:--';
                      if (nextDepartureTime != null) {
                        int travelMinutes =
                            TimeUtils.calculateTravelTimeMinutes(distance);
                        estimatedArrival = TimeUtils.addMinutesToTime(
                          nextDepartureTime!,
                          travelMinutes,
                        );
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
<<<<<<< HEAD
>>>>>>> parent of 07d42ee (upd versão 1.5)
=======
>>>>>>> parent of 07d42ee (upd versão 1.5)
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildScheduleTab() {
    return Consumer<BusProvider>(
      builder: (context, provider, child) {
        String today = DateFormat('yyyyMMdd').format(DateTime.now());
        return FutureBuilder<List<HorarioPosto>>(
          future: provider.getHorarios(widget.linha.numero, today),
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
      },
    );
  }
}
