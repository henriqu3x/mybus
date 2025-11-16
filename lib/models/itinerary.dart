/// Representa um ponto no itinerário de uma linha de ônibus
class ItineraryPoint {
  /// Identificador único do logradouro
  final int logId;

  /// Nome do ponto de parada
  final String name;

  /// Distância percorrida até este ponto (em metros)
  final int distanciaPercorrida;

  const ItineraryPoint({
    required this.logId,
    required this.name,
    required this.distanciaPercorrida,
  });

  /// Cria uma instância de ItineraryPoint a partir de um mapa JSON
  factory ItineraryPoint.fromJson(Map<String, dynamic> json) {
    return ItineraryPoint(
      logId: json['logId'] is int ? json['logId'] : int.tryParse(json['logId']?.toString() ?? '0') ?? 0,
      name: (json['nome'] ?? '').toString().trim(),
      distanciaPercorrida: json['distanciaPercorrida'] is int
          ? json['distanciaPercorrida']
          : int.tryParse(json['distanciaPercorrida']?.toString() ?? '0') ?? 0,
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'logId': logId,
      'nome': name,
      'distanciaPercorrida': distanciaPercorrida,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItineraryPoint &&
          runtimeType == other.runtimeType &&
          logId == other.logId &&
          name == other.name &&
          distanciaPercorrida == other.distanciaPercorrida;

  @override
  int get hashCode => logId.hashCode ^ name.hashCode ^ distanciaPercorrida.hashCode;

  @override
  String toString() {
    return 'ItineraryPoint{logId: $logId, name: $name, distanciaPercorrida: $distanciaPercorrida}';
  }
}

/// Representa o itinerário completo de uma linha de ônibus
class Itinerary {
  /// Ponto de partida do itinerário
  final String pontoInicial;

  /// Lista de pontos que compõem o itinerário
  final List<ItineraryPoint> points;

  const Itinerary({
    required this.pontoInicial,
    required this.points,
  });

  /// Cria uma instância de Itinerary a partir de um mapa JSON
  factory Itinerary.fromJson(Map<String, dynamic> json) {
    return Itinerary(
      pontoInicial: (json['pontoInicial'] ?? '').toString().trim(),
      points: (json['itinerarioIda'] as List<dynamic>?)
              ?.map((point) => ItineraryPoint.fromJson(
                  point is Map<String, dynamic> ? point : {},
                ))
              .toList() ??
          (json['itinerarioVolta'] as List<dynamic>?)
              ?.map((point) => ItineraryPoint.fromJson(
                  point is Map<String, dynamic> ? point : {},
                ))
              .toList() ??
          [],
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'pontoInicial': pontoInicial,
      'itinerarioIda': {
        'sequenciaLogradouro': points.map((point) => point.toJson()).toList(),
      },
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Itinerary &&
          runtimeType == other.runtimeType &&
          pontoInicial == other.pontoInicial &&
          points == other.points;

  @override
  int get hashCode => pontoInicial.hashCode ^ points.hashCode;

  @override
  String toString() {
    return 'Itinerary{pontoInicial: $pontoInicial, points: $points}';
  }
}
