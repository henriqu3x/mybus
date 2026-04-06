import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/linha.dart';
import '../models/itinerario.dart';
import '../models/horario.dart';
import '../providers/bus_provider.dart';
import '../services/kml_service.dart';
import '../utils/time_utils.dart';
import 'map_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

class LineDetailScreen extends StatefulWidget {
  final Linha linha;

  const LineDetailScreen({super.key, required this.linha});

  @override
  State<LineDetailScreen> createState() => _LineDetailScreenState();
}

class _LineDetailScreenState extends State<LineDetailScreen>
    with SingleTickerProviderStateMixin {
  static const String _mapHtmlBaseUrl =
      'https://appassets.androidplatform.net/';
  late TabController _tabController;
  late WebViewController _webControllerIda;
  late WebViewController _webControllerVolta;
  Timer? _timer;
  Future<ItinerarioCompleto>? _itineraryFuture;
  Future<List<HorarioPosto>>? _scheduleFuture;
  final KmlService _kmlService = KmlService();
  

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Initialize futures once
    final provider = Provider.of<BusProvider>(context, listen: false);
    _itineraryFuture = provider.getItinerario(widget.linha.numero);
    
    String today = DateFormat('yyyyMMdd').format(DateTime.now());
    _scheduleFuture = provider.getHorarios(widget.linha.numero, today);

    _initWebControllers();

    // Timer apenas para atualizar horários (aba 0 e 1)
    // Se estiver na aba do mapa (2), não faz setState para evitar recarregar
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _tabController.index != 2) {
        setState(() {});
      }
    });
  }

  

  void _initWebControllers() {
    _webControllerIda = _createWebViewController();
    _webControllerVolta = _createWebViewController();
  }

  WebViewController _createWebViewController() {
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
            // No need to call setState here as it can cause infinite reloading
          },
        ),
      );
    }

    return controller;
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
        // backgroundColor: Colors.blue[800],
        // foregroundColor: Colors.white,
        bottom: TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[400],
          controller: _tabController,
          tabs: const [
            Tab(text: 'Itinerário'),
            Tab(text: 'Horários'),
            Tab(text: 'Rota'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildItineraryTab(), _buildScheduleTab(), _buildMapTab()],
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

                  String estimatedArrivalLabel = '--'; // Ex: "12 min"
                  String intervalLabel = '';           // Ex: "10:15 - 10:20"
                  Color timeColor = Colors.black;

                  if (allDepartureMinutes.isNotEmpty) {
                    int travelMinutes = TimeUtils.calculateTravelTimeMinutes(distance);
                    int? bestArrivalMins;

                    for (var depMins in allDepartureMinutes) {
                      int arrivalMins = depMins + travelMinutes;
                      if (arrivalMins > currentMinutes) {
                        bestArrivalMins = arrivalMins;
                        break;
                      }
                    }

                    if (bestArrivalMins != null) {
                      int remaining = bestArrivalMins - currentMinutes;
                      estimatedArrivalLabel = '$remaining min';
                      
                      // FORMATANDO O INTERVALO (Usando sua TimeUtils)
                      final h = (bestArrivalMins ~/ 60) % 24;
                      final m = bestArrivalMins % 60;
                      final baseTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                      
                      // Pega o intervalo (ex: "10:15 - 10:20")
                      intervalLabel = TimeUtils.getTimeInterval(baseTime, 0);

                      // Cores baseadas no tempo de espera
                      if (remaining <= 5) timeColor = Colors.red;
                      else if (remaining <= 15) timeColor = Colors.orange;
                      else timeColor = Colors.green;
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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        estimatedArrivalLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: timeColor,
                        ),
                      ),
                      if (intervalLabel.isNotEmpty)
                        Text(
                          intervalLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
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

  // Variáveis para a nova funcionalidade de Horários por Ponto
  String _scheduleMode = 'Terminal'; // 'Terminal' ou 'Ponto'
  String _selectedScheduleDirection = 'Ida';
  Ponto? _selectedSchedulePonto;
  List<String> _calculatedStopTimes = [];

  void _calculateStopTimes() async {
    if (_selectedSchedulePonto == null) return;
    
    // Obter o itinerário completo se ainda não tiver
    final itinerario = await _itineraryFuture;
    if (itinerario == null) return;

    final currentItinerario = _selectedScheduleDirection == 'Ida' 
        ? itinerario.ida 
        : itinerario.volta;
    
    if (currentItinerario == null) return;

    // Calcular distância até o ponto selecionado
    double totalDist = 0;
    bool found = false;
    for (var ponto in currentItinerario.pontos) {
      if (ponto.logId == _selectedSchedulePonto!.logId) {
        found = true;
        break;
      }
      totalDist += ponto.distanciaPercorrida;
    }

    if (!found) {
       totalDist = 0;
       for (var ponto in currentItinerario.pontos) {
        if (ponto.nome == _selectedSchedulePonto!.nome) {
          found = true;
          break;
        }
        totalDist += ponto.distanciaPercorrida;
       }
    }

    if (!found) return;

    // Tempo de viagem estimado em minutos
    int travelMinutes = TimeUtils.calculateTravelTimeMinutes(totalDist);

    // Obter horários
    final horarios = await _scheduleFuture;
    if (horarios == null || horarios.isEmpty) {
      setState(() => _calculatedStopTimes = []);
      return;
    }

    // Encontrar posto de controle correspondente
    HorarioPosto? matchingPosto;
      for (var posto in horarios) {
      if (posto.postoControle.toLowerCase() == currentItinerario.pontoInicial.toLowerCase() ||
          posto.postoControle.toLowerCase().contains(currentItinerario.pontoInicial.toLowerCase()) ||
          currentItinerario.pontoInicial.toLowerCase().contains(posto.postoControle.toLowerCase())) {
        matchingPosto = posto;
        break;
      }
    }
    
    if (matchingPosto == null && horarios.length == 1) {
      matchingPosto = horarios.first;
    }

    List<int> arrivalMinutesList = [];

    if (matchingPosto != null) {
      for (var h in matchingPosto.horarios) {
        try {
          final parts = h.horario.split(':');
          final departureMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          arrivalMinutesList.add(departureMinutes + travelMinutes);
        } catch (e) {
          // ignore
        }
      }
    }

    arrivalMinutesList.sort();
    
    // Formatar para exibição HH:mm - HH:mm (intervalo de +/- 2 min)
    final formatted = arrivalMinutesList.map((minutes) {
      final startMinutes = minutes - 2;
      final endMinutes = minutes + 2;

      final hStart = (startMinutes ~/ 60) % 24;
      final mStart = startMinutes % 60;
      
      final hEnd = (endMinutes ~/ 60) % 24;
      final mEnd = endMinutes % 60;

      final startStr = '${hStart.toString().padLeft(2, '0')}:${mStart.toString().padLeft(2, '0')}';
      final endStr = '${hEnd.toString().padLeft(2, '0')}:${mEnd.toString().padLeft(2, '0')}';
      
      return '$startStr - $endStr';
    }).toList();

    setState(() {
      _calculatedStopTimes = formatted;
    });
  }

  Widget _buildScheduleTab() {
    return Column(
      children: [
        // Toggle entre Terminal e Ponto
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scheduleMode == 'Terminal' ? Colors.blue : Colors.grey[300],
                    foregroundColor: _scheduleMode == 'Terminal' ? Colors.white : Colors.black,
                  ),
                  onPressed: () => setState(() => _scheduleMode = 'Terminal'),
                  child: const Text('Saídas do Terminal'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                     backgroundColor: _scheduleMode == 'Ponto' ? Colors.blue : Colors.grey[300],
                     foregroundColor: _scheduleMode == 'Ponto' ? Colors.white : Colors.black,
                  ),
                  onPressed: () => setState(() { 
                    _scheduleMode = 'Ponto';
                    // Reset selection if needed, or keep previous state
                  }),
                  child: const Text('Chegadas no Ponto'),
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: _scheduleMode == 'Terminal' 
              ? _buildTerminalSchedule() 
              : _buildStopSchedule(),
        ),
      ],
    );
  }

  Widget _buildTerminalSchedule() {
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
              initiallyExpanded: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: posto.horarios
                        .map(
                          (h) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: h.acessivel == 'sim' 
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: h.acessivel == 'sim'
                                    ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  h.horario, 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: h.acessivel == 'sim'
                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (h.acessivel == 'sim') ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.accessible,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ]
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStopSchedule() {
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
        
        // Determinar pontos disponíveis com base na direção
        final pontos = _selectedScheduleDirection == 'Ida' 
            ? itinerario.ida?.pontos 
            : itinerario.volta?.pontos;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seletor de Direção
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Ida'),
                      value: 'Ida',
                      groupValue: _selectedScheduleDirection,
                      onChanged: itinerario.ida != null ? (val) {
                         setState(() {
                           _selectedScheduleDirection = val!;
                           _selectedSchedulePonto = null;
                           _calculatedStopTimes = [];
                         });
                      } : null,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Volta'),
                      value: 'Volta',
                      groupValue: _selectedScheduleDirection,
                      onChanged: itinerario.volta != null ? (val) {
                         setState(() {
                           _selectedScheduleDirection = val!;
                           _selectedSchedulePonto = null;
                           _calculatedStopTimes = [];
                         });
                      } : null,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 10),
              
              // Dropdown de Pontos
              DropdownButtonFormField<Ponto>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Selecione o Ponto',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                value: _selectedSchedulePonto,
                items: pontos?.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.nome, 
                      overflow: TextOverflow.ellipsis
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedSchedulePonto = val);
                  _calculateStopTimes();
                },
              ),

              const SizedBox(height: 20),
              
              if (_selectedSchedulePonto != null) ...[
                 Row(
                   children: [
                     const Icon(Icons.access_time_filled, color: Colors.blue),
                     const SizedBox(width: 8),
                     Expanded(
                       child: Text(
                         'Estimativa de chegada em: ${_selectedSchedulePonto!.nome}',
                         style: const TextStyle(fontWeight: FontWeight.bold),
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 10),
                 if (_calculatedStopTimes.isEmpty)
                   const Text('Nenhum horário estimado encontrado.')
                 else
                   Expanded(
                     child: GridView.builder(
                       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                         crossAxisCount: 3, // Reduzido para caber texto maior
                         childAspectRatio: 2.2,
                         crossAxisSpacing: 8,
                         mainAxisSpacing: 8,
                       ),
                       itemCount: _calculatedStopTimes.length,
                       itemBuilder: (context, index) {
                         final time = _calculatedStopTimes[index];
                         // Highlight times close to now? Optional.
                         return Container(
                           alignment: Alignment.center,
                           decoration: BoxDecoration(
                             border: Border.all(color: Colors.grey),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Text(
                             time,
                             style: const TextStyle(fontSize: 13), // Fonte um pouco menor
                           ),
                         );
                       },
                     ),
                   )
              ] else 
                const Expanded(
                  child: Center(
                    child: Text(
                      'Selecione um ponto para ver a previsão de horários.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildMapTab() {
    return FutureBuilder<ItinerarioCompleto>(
      future: _itineraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar mapa: ${snapshot.error}'));
        }

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
                    _buildMapContent(direction: 'Ida', controller: _webControllerIda),
                    _buildMapContent(direction: 'Volta', controller: _webControllerVolta),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapContent({required String direction, required WebViewController controller}) {
    return FutureBuilder<List<List<double>>>(
      future: _loadRouteCoordinates(direction: direction),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar rota: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhuma rota encontrada'));
        }

        final route = snapshot.data!;
        _loadHtmlContent(route, direction, controller);
        
        return WebViewWidget(
          controller: controller,
          // ESTA É A PARTE PRINCIPAL:
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        );
      },
    );
  }

  Future<List<List<double>>> _loadRouteCoordinates({required String direction}) async {
    // Extract line codes for IDA or VOLTA
    // KML format: "numero - rota - Ida/Volta" com possibilidade de "/1" ou "/2" no rota
    final baseLine = widget.linha.numero;
    final nomeRota = widget.linha.nome;
    
    // Tentar formatos:
    // 1. Com zero à esquerda e sem sufixo: "070 - Cuca Barra/Parangaba - Ida"
    // 2. Com zero à esquerda e com sufixo: "070 - Cuca Barra/Parangaba/1 - Ida"
    // 3. Sem zero e sem sufixo: "70 - Cuca Barra/Parangaba - Ida"
    // 4. Sem zero e com sufixo: "70 - Cuca Barra/Parangaba/1 - Ida"
    
    final lineFormats = [
      '${baseLine.toString().padLeft(3, '0')} - $nomeRota/1 - $direction',
      '${baseLine.toString().padLeft(3, '0')} - $nomeRota - $direction',
      '${baseLine.toString().padLeft(2, '0')} - $nomeRota/1 - $direction',
      '${baseLine.toString().padLeft(2, '0')} - $nomeRota - $direction',
      '$baseLine - $nomeRota - $direction',
    ];


    for (var lineName in lineFormats) {
      try {
        final routes = await _kmlService.getCoordinatesForLines([lineName]);
        if (routes.isNotEmpty && routes[0].isNotEmpty) {
          return routes[0];
        }
      } catch (e) {
      }
    }
    
    return [];
  }

  void _loadHtmlContent(List<List<double>> route, String direction, WebViewController controller) {
    final html = _buildMapHtml(route, direction);
    controller.loadHtmlString(html, baseUrl: _mapHtmlBaseUrl);
  }

  String _buildMapHtml(List<List<double>> route, String direction) {
    final color = direction == 'Ida' ? '#0000FF' : '#FF4500';
    final coordsJson = jsonEncode(route);

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="origin">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@8.2.0/ol.css" />
  <script src="https://cdn.jsdelivr.net/npm/ol@8.2.0/dist/ol.js"></script>
  <style>
    /* touch-action: none impede o scroll da página, focando o gesto no OpenLayers */
    html, body { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; touch-action: none; }
    #map { height: 100%; width: 100%; }
    .info { padding: 8px; background: rgba(255,255,255,0.8); }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    const coords = $coordsJson;
    
    const features = [];
    if (coords && coords.length > 0) {
      const transformedCoords = coords.map(c => ol.proj.transform([c[0], c[1]], 'EPSG:4326', 'EPSG:3857'));
      features.push(new ol.Feature({
        geometry: new ol.geom.LineString(transformedCoords),
        name: '$direction'
      }));
    }
    
    const vectorSource = new ol.source.Vector({ features: features });
    const vectorLayer = new ol.layer.Vector({
      source: vectorSource,
      style: new ol.style.Style({
        stroke: new ol.style.Stroke({
          color: '$color',
          width: 4
        })
      })
    });

    const map = new ol.Map({
      target: 'map',
      layers: [
        new ol.layer.Tile({
          source: new ol.source.OSM()
        }),
        vectorLayer
      ],
      view: new ol.View({
        center: ol.proj.transform([-38.52, -3.73], 'EPSG:4326', 'EPSG:3857'),
        zoom: 11
      })
    });

    // Fit to route
    if (features.length > 0) {
      const extent = ol.extent.createEmpty();
      features.forEach(f => ol.extent.extend(extent, f.getGeometry().getExtent()));
      map.getView().fit(extent, { padding: [50, 50, 50, 50] });
    }
  </script>
</body>
</html>
    ''';
  }
}
