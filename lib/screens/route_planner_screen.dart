import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bus_provider.dart';
import '../models/logradouro.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      final route = provider.findRoute(_origin!.id, _destination!.id);

      setState(() {
        _route = route;
        _calculating = false;
      });
    });
  }

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
                if (provider.logradouros.isEmpty) {
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
                    Autocomplete<Logradouro>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
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
                    Autocomplete<Logradouro>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
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

  Widget _buildRouteResult() {
    if (_calculating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCalculated) {
      return const Center(
        child: Text('Selecione origem e destino e clique em Calcular.'),
      );
    }

    if (_route == null) {
      return const Center(
        child: Text('Nenhuma rota encontrada entre estes pontos.'),
      );
    }

    if (_route!.isEmpty) {
      return const Center(child: Text('Origem e destino são o mesmo local.'));
    }

    double totalDistance = 0;
    int transfers = 0;
    String? currentLine;

    for (var edge in _route!) {
      totalDistance += edge.weight;
      if (currentLine != null && edge.lineName != currentLine) {
        transfers++;
      }
      currentLine = edge.lineName;
    }

    // Adjust distance to remove penalties from the visual display if they were added to weight
    // Note: In our graph implementation, the weight in the edge is the DISTANCE.
    // The penalty is added in the Dijkstra calculation but NOT stored in the edge weight.
    // So totalDistance here is the actual physical distance.

    int totalTime = TimeUtils.calculateTravelTimeMinutes(totalDistance);
    // Add time for transfers (e.g., 10 mins per transfer)
    totalTime += (transfers * 10);

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
          child: ListView.builder(
            itemCount: _route!.length,
            itemBuilder: (context, index) {
              final edge = _route![index];
              return ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text('Pegue a linha ${edge.lineName}'),
                subtitle: Text(
                  'Vá até ${edge.destination.name} (${edge.weight}m)',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
