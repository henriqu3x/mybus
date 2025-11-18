/// Representa um ponto no itinerário de uma linha de ônibus
class ItineraryPoint {
  /// Identificador único do logradouro (ponto de parada)
  final int logId;

  /// Nome do ponto de parada
  final String name;

  /// Distância percorrida até este ponto (em metros)
  final int distanciaPercorrida;
  
  // 🛑 ADICIONADOS: Coordenadas geográficas, essenciais para o roteamento
  final double latitude;
  final double longitude;

  const ItineraryPoint({
    required this.logId,
    required this.name,
    required this.distanciaPercorrida,
    required this.latitude,
    required this.longitude,
  });

  /// Cria uma instância de ItineraryPoint a partir de um mapa JSON
  factory ItineraryPoint.fromJson(Map<String, dynamic> json) {
    // Tenta extrair Latitude e Longitude (assume 0.0 se não estiver presente)
    final lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
    final lon = (json['longitude'] as num?)?.toDouble() ?? 0.0;
    
    return ItineraryPoint(
      logId: json['logId'] is int ? json['logId'] : int.tryParse(json['logId']?.toString() ?? '0') ?? 0,
      name: (json['nome'] ?? '').toString().trim(),
      distanciaPercorrida: json['distanciaPercorrida'] is int
          ? json['distanciaPercorrida']
          : int.tryParse(json['distanciaPercorrida']?.toString() ?? '0') ?? 0,
      latitude: lat,
      longitude: lon,
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'logId': logId,
      'nome': name,
      'distanciaPercorrida': distanciaPercorrida,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItineraryPoint &&
          runtimeType == other.runtimeType &&
          logId == other.logId; // Comparar apenas pelo ID é suficiente

  @override
  int get hashCode => logId.hashCode;

  @override
  String toString() {
    return 'ItineraryPoint{logId: $logId, name: $name, dist: $distanciaPercorrida, lat: $latitude, lon: $longitude}';
  }
}

// ------------------------------------------------------------
// CLASSE ITINERARY
// ------------------------------------------------------------

/// Representa o itinerário completo de uma linha de ônibus (em uma única direção: ida ou volta)
class Itinerary {
  /// Ponto de partida do itinerário
  final String pontoInicial;

  /// Lista de pontos que compõem o itinerário
  final List<ItineraryPoint> points;

  const Itinerary({
    required this.pontoInicial,
    required this.points,
  });

  /// Cria uma instância de Itinerary a partir de um mapa JSON.
  /// ⚠️ OBS: Esta factory presume que o JSON contém APENAS a lista de pontos para UMA direção,
  /// ou que a lista de pontos está na chave 'sequenciaLogradouro' ou 'points'.
  factory Itinerary.fromJson(Map<String, dynamic> json) {
    // Tenta extrair a lista de pontos da chave genérica de sequências.
    // Usamos o padrão original de fallback para garantir compatibilidade se a API
    // enviar 'itinerarioIda' ou 'itinerarioVolta' como a lista principal.
    final List<dynamic> pointsList = (json['itinerarioIda'] ?? json['itinerarioVolta'] ?? json['points'] ?? []) as List<dynamic>;

    return Itinerary(
      pontoInicial: (json['pontoInicial'] ?? '').toString().trim(),
      points: pointsList
          .map((point) => ItineraryPoint.fromJson(
                point is Map<String, dynamic> ? point : {},
              ))
          .toList(),
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'pontoInicial': pontoInicial,
      // Retorna a lista de pontos na chave que o seu backend espera
      'sequenciaLogradouro': points.map((point) => point.toJson()).toList(),
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
    return 'Itinerary{pontoInicial: $pontoInicial, pointsCount: ${points.length}}';
  }
}