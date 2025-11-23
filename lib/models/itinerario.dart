class Ponto {
  final int logId;
  final String nome;
  final double distanciaPercorrida;

  Ponto({
    required this.logId,
    required this.nome,
    required this.distanciaPercorrida,
  });

  factory Ponto.fromJson(Map<String, dynamic> json) {
    return Ponto(
      logId: json['logId'],
      nome: json['nome'],
      distanciaPercorrida: (json['distanciaPercorrida'] as num).toDouble(),
    );
  }
}

class Itinerario {
  final String pontoInicial;
  final List<Ponto> pontos;

  Itinerario({required this.pontoInicial, required this.pontos});

  factory Itinerario.fromJson(Map<String, dynamic> json, String key) {
    // key is either 'itinerarioIda' or 'itinerarioVolta'
    var list = json[key] as List;
    List<Ponto> pontosList = list.map((i) => Ponto.fromJson(i)).toList();

    return Itinerario(
      pontoInicial: json['pontoInicial'] ?? '',
      pontos: pontosList,
    );
  }
}

class ItinerarioCompleto {
  final Itinerario? ida;
  final Itinerario? volta;

  ItinerarioCompleto({this.ida, this.volta});

  factory ItinerarioCompleto.fromJson(Map<String, dynamic> json) {
    return ItinerarioCompleto(
      ida: json['ida'] != null
          ? Itinerario.fromJson(json['ida'], 'itinerarioIda')
          : null,
      volta: json['volta'] != null
          ? Itinerario.fromJson(json['volta'], 'itinerarioVolta')
          : null,
    );
  }
}
