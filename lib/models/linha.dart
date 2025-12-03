class Linha {
  final int numero;
  final String nome;
  final String numeroNome;
  final String tipoLinha;

  Linha({
    required this.numero,
    required this.nome,
    required this.numeroNome,
    required this.tipoLinha,
  });

  factory Linha.fromJson(Map<String, dynamic> json) {
    return Linha(
      numero: json['numero'],
      nome: json['nome'],
      numeroNome: json['numeroNome'],
      tipoLinha: json['tipoLinha'],
    );
  }
}
