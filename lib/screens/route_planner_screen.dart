import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bus_provider.dart';
import '../models/logradouro.dart';
import '../models/trip_segment.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';
import 'route_detail_screen.dart';
import 'route_map_screen.dart';

// --------------------------------------------------------------------

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  Logradouro? _origin;
  Logradouro? _destination;
  List<GraphEdge>? _route;
  bool _calculating = false;
  bool _hasCalculated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BusProvider>(context, listen: false).fetchLogradouros();
      // Trigger graph build if not ready
      Provider.of<BusProvider>(context, listen: false).buildGraph();
    });
  }

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) return;

    setState(() {
      _calculating = true;
      _route = null;
      _hasCalculated = true;
    });

    final provider = Provider.of<BusProvider>(context, listen: false);
    // findRoute is now async because it fetches schedules
    final route = await provider.findRoute(_origin!.id, _destination!.id);

    if (!mounted) return;

    setState(() {
      _route = route;
      _calculating = false;
    });
  }

  // --- FUNÇÃO CENTRAL: AGRUPAMENTO DAS ARESTAS EM SEGMENTOS LEGÍVEIS ---
  List<TripSegment> _groupRouteSegments(List<GraphEdge> route) {
    if (route.isEmpty) return [];

    final List<TripSegment> segments = [];

    // O ponto de partida é a ORIGEM selecionada
    String currentStartStreet = _origin!.nome;
    int currentStartLogId = _origin!.id; // NOVO: ID de partida
    String currentLine = route.first.lineName;
    String currentLineBase = _normalizeLineName(currentLine); // Remove _IDA/_VOLTA
    double currentDistance = 0;

    // Itera pelas arestas para agrupar
    for (int i = 0; i < route.length; i++) {
      final edge = route[i];
      final edgeLineBase = _normalizeLineName(edge.lineName);

      // Se a linha for a mesma (ignorando IDA/VOLTA), mas a direção mudou,
      // devemos encerrar o segmento e iniciar outro para representar a mudança
      // de sentido (ex.: mesma linha, de Ida para Volta).
      if (edgeLineBase == currentLineBase) {
        if (edge.lineName == currentLine) {
          // mesma linha e mesma direção: acumula
          currentDistance += edge.weight;
        } else {
          // mesma linha, DIREÇÃO DIFERENTE -> tratar como troca lógica de segmento
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

          // Inicia novo segmento com a nova direção
          currentLine = edge.lineName;
          currentLineBase = edgeLineBase;
          currentStartStreet = previousEdge.destination.name;
          currentStartLogId = previousEdge.destination.id;
          currentDistance = edge.weight;
        }
      } else {
        // MUDANÇA DE LINHA REAL: Finaliza o segmento anterior
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

        // INICIA NOVO SEGMENTO
        currentLine = edge.lineName;
        currentLineBase = edgeLineBase;
        currentStartStreet = previousEdge.destination.name;
        currentStartLogId = previousEdge.destination.id;
        currentDistance = edge.weight;
      }
    }

    // Adiciona o último segmento, que termina no destino final
    segments.add(
      TripSegment(
        type: 'BUS',
        lineName: currentLine,
        startStreetName: currentStartStreet,
        endStreetName: _destination!.nome, // Ponto final
        distance: currentDistance,
        startStopId: currentStartLogId, // NOVO
        endStopId: _destination!.id, // NOVO
      ),
    );

    return segments;
  }

  /// Normaliza o nome da linha removendo sufixos de direção (_IDA, _VOLTA)
  String _normalizeLineName(String lineName) {
    return lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
  }

  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planejador de Rotas'),
      backgroundColor: Colors.blue[800],
      foregroundColor: Colors.white,),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Consumer<BusProvider>(
              builder: (context, provider, child) {
                if (provider.logradouros.isEmpty && !provider.isGraphBuilding) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.isGraphBuilding) {
                  return Card(
                    color: Colors.orangeAccent,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Construindo rede de transporte... Isso pode levar um momento.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Campo de Origem
                    Autocomplete<Logradouro>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<Logradouro>.empty();
                        }
                        return provider.logradouros.where((Logradouro option) {
                          return option.nome.toLowerCase().contains(
                            textEditingValue.text.toLowerCase(),
                          );
                        });
                      },
                      displayStringForOption: (Logradouro option) =>
                          option.nome,
                      onSelected: (Logradouro selection) {
                        setState(() => _origin = selection);
                      },
                      fieldViewBuilder:
                          (
                            context,
                            textEditingController,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Origem',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.my_location),
                              ),
                            );
                          },
                    ),
                    const SizedBox(height: 16),
                    // Campo de Destino
                    Autocomplete<Logradouro>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<Logradouro>.empty();
                        }
                        return provider.logradouros.where((Logradouro option) {
                          return option.nome.toLowerCase().contains(
                            textEditingValue.text.toLowerCase(),
                          );
                        });
                      },
                      displayStringForOption: (Logradouro option) =>
                          option.nome,
                      onSelected: (Logradouro selection) {
                        setState(() => _destination = selection);
                      },
                      fieldViewBuilder:
                          (
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
                                prefixIcon: Icon(Icons.location_on),
                              ),
                            );
                          },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  (_origin != null && _destination != null && !_calculating)
                  ? _calculateRoute
                  : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _calculating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Calcular Rota'),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildRouteResult()),
          ],
        ),
      ),
    );
  }

  // --- NOVO MÉTODO: EXIBIÇÃO CLARA DOS RESULTADOS AGRUPADOS ---
  Widget _buildRouteResult() {
    if (_calculating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCalculated) {
      return const Center(
        child: Text('Selecione origem e destino e clique em Calcular.'),
      );
    }

    if (_route == null || _route!.isEmpty) {
      return const Center(
        child: Text('Nenhuma rota encontrada entre estes pontos.'),
      );
    }

    // 1. Agrupa as arestas em segmentos legíveis
    final segmentedRoute = _groupRouteSegments(_route!);

    // 2. Calcula Métricas com base nos Segmentos
    double totalDistance = segmentedRoute.fold(
      0.0,
      (sum, seg) => sum + seg.distance,
    );

    // Número de trocas ignorando mudança de sentido na mesma linha
    int transfers = 0;
    for (int i = 0; i < segmentedRoute.length - 1; i++) {
      final current = segmentedRoute[i].lineName
          .replaceAll('_IDA', '')
          .replaceAll('_VOLTA', '');
      final next = segmentedRoute[i + 1].lineName
          .replaceAll('_IDA', '')
          .replaceAll('_VOLTA', '');
      if (current != next) {
        transfers++;
      }
    }

    // Adiciona tempo para trocas (e.g., 10 minutos por troca REAL)
    int totalTime =
        TimeUtils.calculateTravelTimeMinutes(totalDistance) + (transfers * 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card de Resumo
        Card(
          color: Colors.green[50],
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RouteDetailScreen(
                    segments: segmentedRoute,
                    origin: _origin!.nome,
                    destination: _destination!.nome,
                    totalDistance: totalDistance,
                    totalTime: totalTime,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text(
                            'Tempo Estimado',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '$totalTime min',
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Text(
                            'Distância',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${(totalDistance / 1000).toStringAsFixed(1)} km',
                            style: const TextStyle(fontSize: 20),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trocas de ônibus: $transfers',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toque para ver horários detalhados',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Botão de Visualizar no Mapa
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RouteMapScreen(
                    segments: segmentedRoute,
                    origin: _origin!.nome,
                    destination: _destination!.nome,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map),
            label: const Text('Visualizar no Mapa'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          'Passo a Passo:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        // Lista de Segmentos (mesclados por linha base para evitar duplicatas)
        Expanded(
          child: Builder(
            builder: (context) {
              final displaySegments = _mergeSegmentsByLineBase(segmentedRoute);
              return ListView.separated(
                itemCount: displaySegments.length,
                separatorBuilder: (context, index) {
                  // Mostrar indicador de transferência após cada segmento (exceto o último)
                  if (index < displaySegments.length - 1) {
                final currentSegment = displaySegments[index];
                final nextSegment = displaySegments[index + 1];

                // Verificar se é mudança de sentido na mesma linha (não mostrar como transferência)
                final currentLineBase = currentSegment.lineName
                    .replaceAll('_IDA', '')
                    .replaceAll('_VOLTA', '');
                final nextLineBase = nextSegment.lineName
                    .replaceAll('_IDA', '')
                    .replaceAll('_VOLTA', '');

                // Se for a mesma linha mudando de sentido, não mostrar indicador de transferência
                if (currentLineBase == nextLineBase) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_downward,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.blue,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.repeat,
                                  color: Colors.blue[700],
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Continua na mesma linha',
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Caso contrário, mostrar indicador normal de transferência
                final transferLocation = currentSegment.endStreetName;
                final isTerminalTransfer = transferLocation
                    .toLowerCase()
                    .contains('terminal');

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_downward,
                        color: Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isTerminalTransfer
                                ? Colors.green[100]
                                : Colors.orange[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isTerminalTransfer
                                  ? Colors.green
                                  : Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isTerminalTransfer
                                    ? Icons.check_circle
                                    : Icons.attach_money,
                                color: isTerminalTransfer
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isTerminalTransfer
                                    ? 'Transferência Gratuita'
                                    : 'Troca de Ônibus',
                                style: TextStyle(
                                  color: isTerminalTransfer
                                      ? Colors.green[900]
                                      : Colors.orange[900],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            itemBuilder: (context, index) {
              // Item Builder Logic
              final displaySegments = _mergeSegmentsByLineBase(segmentedRoute);
              final segment = displaySegments[index];
              final isLastSegment = index == displaySegments.length - 1;

              return Column(
                children: [
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.directions_bus,
                        color: Colors.blue,
                      ),
                      title: Text(
                        'Pegue a Linha ${segment.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '')}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Embarque: **${segment.startStreetName}**'),
                          Text('Desembarque: **${segment.endStreetName}**'),
                          Text(
                            'Trajeto: ${(segment.distance / 1000).toStringAsFixed(1)} km',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Mostrar chegada após o último segmento
                  if (isLastSegment)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward,
                            color: Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ListTile(
                              leading: const Icon(
                                Icons.flag,
                                color: Colors.green,
                              ),
                              title: const Text('Chegada'),
                              subtitle: Text(
                                'Você chegou ao seu destino: **${_destination!.nome}**',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          );
            }
          ),
        ),
      ],
    );
  }

  /// Mescla segmentos consecutivos da mesma linha base (ignorando _IDA/_VOLTA)
  /// Isso evita exibir múltiplos cards para a mesma linha quando há mudança de sentido
  List<TripSegment> _mergeSegmentsByLineBase(List<TripSegment> segments) {
    if (segments.isEmpty) return [];

    final List<TripSegment> result = [];
    String currentBase = segments.first.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');
    String startStreet = segments.first.startStreetName;
    int startStop = segments.first.startStopId;
    double distance = segments.first.distance;
    String endStreet = segments.first.endStreetName;
    int endStop = segments.first.endStopId;

    for (int i = 1; i < segments.length; i++) {
      final s = segments[i];
      final base = s.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '');

      if (base == currentBase) {
        // Mescla: mesma linha, apenas atualiza o final
        distance += s.distance;
        endStreet = s.endStreetName;
        endStop = s.endStopId;
      } else {
        // Linha diferente: flush do segmento atual e começa novo
        result.add(
          TripSegment(
            type: 'BUS',
            lineName: currentBase,
            startStreetName: startStreet,
            endStreetName: endStreet,
            distance: distance,
            startStopId: startStop,
            endStopId: endStop,
          ),
        );

        currentBase = base;
        startStreet = s.startStreetName;
        startStop = s.startStopId;
        distance = s.distance;
        endStreet = s.endStreetName;
        endStop = s.endStopId;
      }
    }

    // Flush do último segmento
    result.add(
      TripSegment(
        type: 'BUS',
        lineName: currentBase,
        startStreetName: startStreet,
        endStreetName: endStreet,
        distance: distance,
        startStopId: startStop,
        endStopId: endStop,
      ),
    );

    return result;
  }
}
