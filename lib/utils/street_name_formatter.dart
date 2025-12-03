// Extensão para converter strings para Title Case
extension StringCasingExtension on String {
  // Converte a string para Title Case (Ex: "AVENIDA" vira "Avenida"; "DOS" vira "dos")
  String toTitleCase() => split(' ').map((word) {
    if (word.isEmpty) return '';
    // Manter preposições/artigos comuns em minúsculas
    if (['de', 'do', 'da', 'dos', 'das', 'e', 'a', 'o'].contains(word.toLowerCase()) && 
        word.length <= 3) {
      return word.toLowerCase();
    }
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

class StreetNameFormatter {
  /// Formata o nome da rua usando a mesma lógica do Logradouro
  /// Exemplo: "Castro, conego de" + "Avenida" -> "Avenida Cônego de Castro"
  static String formatStreetName(String streetName) {
    if (streetName.isEmpty) return '';

    // 1. PRIMEIRA ETAPA: Tratar e Mover o Qualificador de Bairro
    String nomeSemQualificador = streetName;
    String qualificador = '';

    final regex = RegExp(r'(\s*\([^)]+\))');
    final match = regex.firstMatch(streetName);

    if (match != null) {
      qualificador = match.group(0)!.trim();
      nomeSemQualificador = streetName.replaceAll(regex, '').trim();
    }

    // 2. SEGUNDA ETAPA: Separar tipo e nome
    String tipo = '';
    String nome = nomeSemQualificador;

    // Lista de tipos de logradouro
    final tipos = [
      'Rua', 'Avenida', 'Av.', 'Av', 'Travessa', 'Trav.', 
      'Alameda', 'Praça', 'Largo', 'Rodovia', 'Via', 'Estrada'
    ];

    // Verificar se começa com algum tipo
    for (var t in tipos) {
      if (nomeSemQualificador.toLowerCase().startsWith('${t.toLowerCase()} ')) {
        tipo = t;
        nome = nomeSemQualificador.substring(t.length + 1).trim();
        break;
      }
    }

    // 3. TERCEIRA ETAPA: Aplicar Title Case
    final tipoTitleCase = tipo.toTitleCase();
    final nomePrincipalTitleCase = nome.toTitleCase();
    String nomeFinal;

    // 4. QUARTA ETAPA: Aplicar a Lógica de Inversão (baseada na vírgula)
    if (nomePrincipalTitleCase.contains(',')) {
      // Caso de Inversão (Ex: "Castro, Conego de" -> "Cônego de Castro")
      final parts = nomePrincipalTitleCase.split(',').map((p) => p.trim()).toList();

      if (parts.length >= 2) {
        // Constrói: Tipo + Qualificador + Nome Principal
        if (tipoTitleCase.isNotEmpty) {
          nomeFinal = '$tipoTitleCase ${parts[1]} ${parts[0]}'.trim();
        } else {
          nomeFinal = '${parts[1]} ${parts[0]}'.trim();
        }
      } else {
        // Se a vírgula não levou a uma inversão válida
        if (tipoTitleCase.isNotEmpty) {
          nomeFinal = '$tipoTitleCase $nomePrincipalTitleCase'.trim();
        } else {
          nomeFinal = nomePrincipalTitleCase;
        }
      }
    } else {
      // Caso de Nome Normal
      if (tipoTitleCase.isNotEmpty) {
        nomeFinal = '$tipoTitleCase $nomePrincipalTitleCase'.trim();
      } else {
        nomeFinal = nomePrincipalTitleCase;
      }
    }

    // 5. QUINTA ETAPA: Colocar o Qualificador de Bairro no FINAL
    if (qualificador.isNotEmpty) {
      return '$nomeFinal $qualificador';
    }

    return nomeFinal;
  }
}
