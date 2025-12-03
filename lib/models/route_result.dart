// route_result.dart (ou route_segment.dart)

import '../models/line.dart';
import '../models/logradouro.dart';

/// Define o tipo de transporte usado no segmento da rota.
enum SegmentType {
  walk,   // Caminhada (Acesso, Transbordo ou Saída)
  bus,    // Ônibus
}

/// Representa um único segmento dentro de uma rota calculada pelo Dijkstra.
class RouteSegment {
  /// Tipo de transporte deste segmento.
  final SegmentType type;

  /// Linha de ônibus usada (nulo se for caminhada).
  final Line? line; 
  
  /// Ponto de partida do segmento.
  final Logradouro startPoint;

  /// Ponto final (destino) do segmento.
  final Logradouro endPoint;
  
  /// Distância total deste segmento em quilômetros (km).
  final double distanceKm;
  
  /// Tempo estimado para completar este segmento em minutos.
  final double durationMinutes;
  
  /// Tempo de espera (se for ônibus, 0.0 para caminhada).
  final double? waitTimeMinutes;

  RouteSegment({
    required this.type,
    required this.startPoint,
    required this.endPoint,
    required this.distanceKm,
    required this.durationMinutes,
    this.line,
    this.waitTimeMinutes,
  });

  /// ------------------------------------------------------------
  /// FÁBRICAS DE CONSTRUÇÃO
  /// ------------------------------------------------------------

  factory RouteSegment.walk({
    required Logradouro startPoint,
    required Logradouro endPoint,
    required double distanceKm,
    required double durationMinutes,
  }) {
    return RouteSegment(
      type: SegmentType.walk,
      startPoint: startPoint,
      endPoint: endPoint,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      line: null,
      waitTimeMinutes: 0.0,
    );
  }

  factory RouteSegment.bus({
    required Line line,
    required Logradouro startPoint,
    required Logradouro endPoint,
    required double distanceKm,
    required double travelTimeMinutes,
    required double waitTimeMinutes,
  }) {
    return RouteSegment(
      type: SegmentType.bus,
      line: line,
      startPoint: startPoint,
      endPoint: endPoint,
      distanceKm: distanceKm,
      durationMinutes: travelTimeMinutes + waitTimeMinutes,
      waitTimeMinutes: waitTimeMinutes,
    );
  }

  @override
  String toString() {
    final lineDetails = line != null ? ' | Linha: ${line!.name}' : '';
    return 'Segmento: ${type.name} de ${startPoint.nome} a ${endPoint.nome} (${distanceKm.toStringAsFixed(2)} km) - ${durationMinutes.toStringAsFixed(0)} min$lineDetails';
  }
}