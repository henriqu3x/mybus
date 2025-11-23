class Logradouro {
  final int id;
  final String nome;
  final String tipo;

  Logradouro({required this.id, required this.nome, required this.tipo});

  factory Logradouro.fromJson(Map<String, dynamic> json) {
    return Logradouro(
      id: json['id'],
      nome: json['nome'].toString().trim(),
      tipo: json['tipo'].toString().trim(),
    );
  }
  Map<String, dynamic> toJson() {
    return {'id': id, 'nome': nome, 'tipo': tipo};
  }
}
