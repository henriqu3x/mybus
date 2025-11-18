/// Representa um logradouro (rua, avenida, etc.) com informações de geolocalização.
class Logradouro {
  /// Identificador único do logradouro
  final int id;
  
  /// Nome do logradouro (ex: "Castro, Cônego de")
  final String nome;
  
  /// Tipo do logradouro (ex: "Rua", "Avenida")
  final String tipo;

  /// Latitude do logradouro. Pode ser atualizada após a geocodificação.
  double latitude;

  /// Longitude do logradouro. Pode ser atualizada após a geocodificação.
  double longitude;

  Logradouro({
    required this.id,
    required this.nome,
    required this.tipo,
    // Define valores padrão para 0.0, assumindo que serão geocodificados se necessário.
    this.latitude = 0.0, 
    this.longitude = 0.0,
  });

  /// Cria uma instância de Logradouro a partir de um mapa JSON
  factory Logradouro.fromJson(Map<String, dynamic> json) {
    // Tenta obter Lat/Lon se a API já as fornecer. Caso contrário, usa 0.0.
    final lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
    final lon = (json['longitude'] as num?)?.toDouble() ?? 0.0;

    return Logradouro(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      nome: (json['nome'] ?? '').toString().trim(),
      tipo: (json['tipo'] ?? '').toString().trim(),
      latitude: lat,
      longitude: lon,
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
  
  /// Retorna o nome completo do logradouro (tipo + nome)
  String get nomeCompleto {
    return '${tipo.isNotEmpty ? "$tipo " : ""}$nome';
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Logradouro &&
          runtimeType == other.runtimeType &&
          id == other.id; // O ID é suficiente para identificar unicamente

  @override
  int get hashCode => id.hashCode;
      
  @override
  String toString() {
    return 'Logradouro{id: $id, nome: $nome, tipo: $tipo, lat: $latitude, lon: $longitude}';
  }
}