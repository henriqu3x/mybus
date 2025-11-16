/// Representa um logradouro (rua, avenida, etc.)
class Logradouro {
  /// Identificador único do logradouro
  final int id;
  
  /// Nome do logradouro (ex: "Castro, Cônego de")
  final String nome;
  
  /// Tipo do logradouro (ex: "Rua", "Avenida")
  final String tipo;

  const Logradouro({
    required this.id,
    required this.nome,
    required this.tipo,
  });

  /// Cria uma instância de Logradouro a partir de um mapa JSON
  factory Logradouro.fromJson(Map<String, dynamic> json) {
    return Logradouro(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      nome: (json['nome'] ?? '').toString().trim(),
      tipo: (json['tipo'] ?? '').toString().trim(),
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo,
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
          id == other.id &&
          nome == other.nome &&
          tipo == other.tipo;

  @override
  int get hashCode => id.hashCode ^ nome.hashCode ^ tipo.hashCode;
      
  @override
  String toString() {
    return 'Logradouro{id: $id, nome: $nome, tipo: $tipo}';
  }
}
