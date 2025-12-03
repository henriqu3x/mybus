/// Representa um horário de saída de uma linha de ônibus
class ScheduleEntry {
  /// Horário de saída no formato HH:MM
  final String horario;

  /// Indica se o veículo é acessível para pessoas com deficiência
  final bool acessivel;

  /// Número da tabela de horários
  final int tabela;

  const ScheduleEntry({
    required this.horario,
    required this.acessivel,
    required this.tabela,
  });

  /// Cria uma instância de ScheduleEntry a partir de um mapa JSON
  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      horario: (json['horario'] ?? '').toString().trim(),
      acessivel: json['acessivel'] is bool
          ? json['acessivel']
          : (json['acessivel']?.toString().toLowerCase() == 'sim'),
      tabela: json['tabela'] is int
          ? json['tabela']
          : int.tryParse(json['tabela']?.toString() ?? '0') ?? 0,
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'horario': horario,
      'acessivel': acessivel ? 'sim' : 'não',
      'tabela': tabela.toString(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleEntry &&
          runtimeType == other.runtimeType &&
          horario == other.horario &&
          acessivel == other.acessivel &&
          tabela == other.tabela;

  @override
  int get hashCode => horario.hashCode ^ acessivel.hashCode ^ tabela.hashCode;

  @override
  String toString() {
    return 'ScheduleEntry{horario: $horario, acessivel: $acessivel, tabela: $tabela}';
  }
}

/// Representa a programação de horários de uma linha de ônibus
class Schedule {
  /// Nome do ponto de controle
  final String postoControle;

  /// Lista de horários de saída
  final List<ScheduleEntry> entries;

  const Schedule({
    required this.postoControle,
    required this.entries,
  });

  /// Cria uma instância de Schedule a partir de um mapa JSON
  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      postoControle: (json['postoControle'] ?? '').toString().trim(),
      entries: (json['horarios'] as List<dynamic>?)
              ?.map((entry) => ScheduleEntry.fromJson(
                  entry is Map<String, dynamic> ? entry : {},
                ))
              .toList() ??
          [],
    );
  }

  /// Converte a instância para um mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'postoControle': postoControle,
      'horarios': {
        'saida': entries.map((entry) => entry.toJson()).toList(),
      },
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Schedule &&
          runtimeType == other.runtimeType &&
          postoControle == other.postoControle &&
          entries == other.entries;

  @override
  int get hashCode => postoControle.hashCode ^ entries.hashCode;

  @override
  String toString() {
    return 'Schedule{postoControle: $postoControle, entries: $entries}';
  }
}
