class HorarioItem {
  final String horario;
  final String acessivel;
  final int tabela;

  HorarioItem({
    required this.horario,
    required this.acessivel,
    required this.tabela,
  });

  factory HorarioItem.fromJson(Map<String, dynamic> json) {
    return HorarioItem(
      horario: json['horario'],
      acessivel: json['acessivel'],
      tabela: json['tabela'],
    );
  }
}

class HorarioPosto {
  final String postoControle;
  final List<HorarioItem> horarios;

  HorarioPosto({required this.postoControle, required this.horarios});

  factory HorarioPosto.fromJson(Map<String, dynamic> json) {
    var list = json['horarios'] as List;
    List<HorarioItem> horariosList = list
        .map((i) => HorarioItem.fromJson(i))
        .toList();

    return HorarioPosto(
      postoControle: json['postoControle'],
      horarios: horariosList,
    );
  }
}
