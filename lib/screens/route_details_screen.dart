import 'package:flutter/material.dart';
import '../models/route_suggestion.dart';
import '../models/line.dart';
import 'itinerary_details_screen.dart';

class RouteDetailsScreen extends StatelessWidget {
  final RouteSuggestion routeSuggestion;

  const RouteDetailsScreen({super.key, required this.routeSuggestion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Rota'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título da rota
            Text(
              routeSuggestion.description,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Número de conexões
            Text(
              routeSuggestion.connections == 0
                  ? 'Rota direta'
                  : '${routeSuggestion.connections} conexão${routeSuggestion.connections > 1 ? 'ões' : ''}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Etapas da rota
            const Text(
              'Etapas da Rota:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            ..._buildRouteSteps(context),

            const SizedBox(height: 24),

            // Botão para ver itinerários detalhados
            if (routeSuggestion.steps.length == 1) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.directions_bus),
                label: const Text('Ver Itinerário Completo'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ItineraryDetailsScreen(line: routeSuggestion.steps[0].line),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ] else ...[
              const Text(
                'Para ver os itinerários detalhados de cada linha, toque nas etapas acima.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRouteSteps(BuildContext context) {
    final steps = <Widget>[];

    for (int i = 0; i < routeSuggestion.steps.length; i++) {
      final step = routeSuggestion.steps[i];
      final isLastStep = i == routeSuggestion.steps.length - 1;

      steps.add(
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ItineraryDetailsScreen(line: step.line),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Número da etapa
                  Text(
                    'Etapa ${i + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Linha
                  Row(
                    children: [
                      const Icon(Icons.directions_bus, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step.line.numeroNome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Pontos de partida e chegada
                  if (step.from != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'De: ${step.from!.nome}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (step.to != null) ...[
                    Row(
                      children: [
                        Icon(
                          isLastStep ? Icons.location_city : Icons.transfer_within_a_station,
                          color: isLastStep ? Colors.red : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isLastStep
                                ? 'Até: ${step.to!.nome} (Destino)'
                                : 'Até: ${step.to!.nome} (Troca de ônibus)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isLastStep ? FontWeight.bold : FontWeight.normal,
                              color: isLastStep ? Colors.red : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (step.from == null && step.to == null) ...[
                    const Text(
                      'Rota direta - verifique o itinerário completo',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Tipo de linha
                  Text(
                    'Tipo: ${step.line.tipoLinha}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),

                  // Toque para ver detalhes
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Toque para ver itinerário',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                      Icon(Icons.arrow_forward, size: 16, color: Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Adiciona indicador de transferência se não for a última etapa
      if (!isLastStep) {
        steps.add(
          Container(
            margin: const EdgeInsets.only(left: 16, bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.transfer_within_a_station, color: Colors.orange.shade700, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Troca em ${step.to!.nome}',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return steps;
  }
}
