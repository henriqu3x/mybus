import '../models/line.dart';
import '../models/logradouro.dart';

/// Representa uma etapa de uma rota
class RouteStep {
  /// Linha da etapa
  final Line line;

  /// Ponto de partida da etapa (null para primeira etapa)
  final Logradouro? from;

  /// Ponto de chegada da etapa (null para última etapa)
  final Logradouro? to;

  const RouteStep({
    required this.line,
    this.from,
    this.to,
  });

  @override
  String toString() {
    return 'RouteStep{line: ${line.numeroNome}, from: ${from?.nome}, to: ${to?.nome}}';
  }
}

/// Representa uma sugestão de rota, que pode ser direta ou com conexões
class RouteSuggestion {
  /// Descrição da rota (ex: "Pegue linha 51 até Terminal Parangaba, depois linha 52 até destino")
  final String description;

  /// Lista de etapas da rota
  final List<RouteStep> steps;

  /// Número de conexões (0 para direta)
  final int connections;

  const RouteSuggestion({
    required this.description,
    required this.steps,
    required this.connections,
  });

  /// Cria uma sugestão de rota direta
  factory RouteSuggestion.direct(Line line) {
    return RouteSuggestion(
      description: 'Rota direta: ${line.numeroNome}',
      steps: [RouteStep(line: line, from: null, to: null)],
      connections: 0,
    );
  }

  /// Cria uma sugestão de rota com uma conexão
  factory RouteSuggestion.withConnection({
    required Line firstLine,
    required Logradouro transferPoint,
    required Line secondLine,
  }) {
    return RouteSuggestion(
      description: 'Pegue ${firstLine.numeroNome} até ${transferPoint.nome}, depois ${secondLine.numeroNome} até destino',
      steps: [
        RouteStep(line: firstLine, from: null, to: transferPoint),
        RouteStep(line: secondLine, from: transferPoint, to: null),
      ],
      connections: 1,
    );
  }

  @override
  String toString() {
    return 'RouteSuggestion{description: $description, connections: $connections, steps: $steps}';
  }
}
