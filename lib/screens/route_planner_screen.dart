import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bus_provider.dart';
import '../models/logradouro.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';

// --- CLASSE AUXILIAR PARA REPRESENTAR UM TRECHO DE VIAGEM LEGÍVEL ---
class TripSegment {
  final String type; // 'BUS'
  final String lineName;
  final String startStreetName;
  final String endStreetName;
  final double distance;
  
  TripSegment({
    required this.type,
    required this.lineName,
    required this.startStreetName,
    required this.endStreetName,
    required this.distance,
  });
}
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

  void _calculateRoute() {
    if (_origin == null || _destination == null) return;

    setState(() {
      _calculating = true;
      _route = null;
      _hasCalculated = true;
    });

    // O cálculo do grafo é demorado, então é feito após o frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      final route = provider.findRoute(_origin!.id, _destination!.id);

      setState(() {
        _route = route;
        _calculating = false;
      });
    });
  }

  // --- FUNÇÃO CENTRAL: AGRUPAMENTO DAS ARESTAS EM SEGMENTOS LEGÍVEIS ---
  List<TripSegment> _groupRouteSegments(List<GraphEdge> route) {
    if (route.isEmpty) return [];

    final List<TripSegment> segments = [];
    
    // O ponto de partida é a ORIGEM selecionada
    String currentStartStreet = _origin!.nome; 
    String currentLine = route.first.lineName;
    double currentDistance = 0;
    
    // Itera pelas arestas para agrupar
    for (int i = 0; i < route.length; i++) {
      final edge = route[i];
      
      // Se a linha for a mesma, apenas acumula distância
      if (edge.lineName == currentLine) {
        currentDistance += edge.weight;
      } else {
        // MUDANÇA DE LINHA: Finaliza o segmento anterior
        
        // O ponto de desembarque é o destino da ARESTA ANTERIOR (onde a troca ocorre)
        final previousEdge = route[i - 1];
        
        segments.add(TripSegment(
          type: 'BUS',
          lineName: currentLine,
          startStreetName: currentStartStreet,
          endStreetName: previousEdge.destination.name, 
          distance: currentDistance,
        ));
        
        // INICIA NOVO SEGMENTO
        currentLine = edge.lineName;
        currentStartStreet = previousEdge.destination.name; // Novo ponto de embarque
        currentDistance = edge.weight; // Zera e começa a nova distância
      }
    }

    // Adiciona o último segmento, que termina no destino final
    segments.add(TripSegment(
      type: 'BUS',
      lineName: currentLine,
      startStreetName: currentStartStreet,
      endStreetName: _destination!.nome, // Ponto final
      distance: currentDistance,
    ));

    return segments;
  }

  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planejador de Rotas')),
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
                      displayStringForOption: (Logradouro option) => option.nome,
                      onSelected: (Logradouro selection) {
                        setState(() => _origin = selection);
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
                      displayStringForOption: (Logradouro option) => option.nome,
                      onSelected: (Logradouro selection) {
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
    double totalDistance = segmentedRoute.fold(0.0, (sum, seg) => sum + seg.distance);
    // Número de trocas é o número de segmentos menos 1
    int transfers = segmentedRoute.length - 1; 
    
    // Adiciona tempo para trocas (e.g., 10 minutos por troca)
    int totalTime = TimeUtils.calculateTravelTimeMinutes(totalDistance) + (transfers * 10);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.green[50],
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Passo a Passo:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Expanded(
          // Usa os segmentos agrupados no ListView
          child: ListView.builder(
            itemCount: segmentedRoute.length + 1, // +1 para a etapa final
            itemBuilder: (context, index) {
              if (index < segmentedRoute.length) {
                final segment = segmentedRoute[index];
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.directions_bus, color: Colors.blue),
                    title: Text(
                      'Pegue a **Linha ${segment.lineName}**',
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
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              } else {
                // Etapa final (Chegada)
                return ListTile(
                  leading: const Icon(Icons.flag, color: Colors.green),
                  title: const Text('Chegada'),
                  subtitle: Text('Você chegou ao seu destino: **${_destination!.nome}**'),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}