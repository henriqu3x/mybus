// Coloque esta extensão no topo do arquivo (ou em um arquivo de utilitário, se preferir)
extension StringCasingExtension on String {
    // Converte a string para Title Case (Ex: "AVENIDA" vira "Avenida"; "DOS" vira "dos")
    String toTitleCase() => this.split(' ').map((word) {
        if (word.isEmpty) return '';
        // Manter preposições/artigos comuns em minúsculas
        if (['de', 'do', 'da', 'dos', 'das', 'e', 'a', 'o'].contains(word.toLowerCase()) && word.length <= 3) {
            return word.toLowerCase();
        }
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
}

class Logradouro {
  final int id;
  final String nome; 
  final String tipo; 

  Logradouro({required this.id, required this.nome, required this.tipo});

  factory Logradouro.fromJson(Map<String, dynamic> json) {
    
    final rawTipo = json['tipo'].toString().trim();
    final rawNome = json['nome'].toString().trim();
    
    final formattedName = _formatLogradouroName(rawTipo, rawNome);

    return Logradouro(
      id: json['id'],
      nome: formattedName, 
      tipo: rawTipo,
    );
  }

  // Lógica principal de Formatação, Inversão e Movimentação de Qualificadores
  static String _formatLogradouroName(String rawTipo, String rawNome) {
    // 1. PRIMEIRA ETAPA: Tratar e Mover o Qualificador de Bairro (Ex: "(parque Santa Rosa)")
    String nomeSemQualificador = rawNome;
    String qualificador = '';

    // Expressão regular para encontrar um trecho entre parênteses em qualquer lugar da string
    final regex = RegExp(r'(\s*\([^)]+\))');
    final match = regex.firstMatch(rawNome);

    if (match != null) {
      // Guarda o trecho entre parênteses (com ou sem espaço extra)
      qualificador = match.group(0)!.trim(); 
      // Remove o trecho entre parênteses do nome principal
      nomeSemQualificador = rawNome.replaceAll(regex, '').trim(); 
    }
    // Agora nomeSemQualificador é "Rua São Fidélis" (ou "São Fidélis") e qualificador é "(parque Santa Rosa)"

    // 2. SEGUNDA ETAPA: Aplicar a Lógica de Inversão (baseada na vírgula)
    
    // Capitaliza o Tipo e o Nome para melhor apresentação
    final tipoTitleCase = rawTipo.toTitleCase();
    final nomePrincipalTitleCase = nomeSemQualificador.toTitleCase();
    String nomeFinal;
    
    if (nomePrincipalTitleCase.contains(',')) {
      // Caso de Inversão (Ex: "Silas Ribeiro, Prof." + "Rua")
      final parts = nomePrincipalTitleCase.split(',').map((p) => p.trim()).toList();
      
      if (parts.length >= 2) {
        // Constrói: Tipo + Qualificador + Nome Principal
        nomeFinal = '$tipoTitleCase ${parts[1]} ${parts[0]}'.trim();
      } else {
        // Se a vírgula não levou a uma inversão válida, usa a forma Tipo + Nome.
        nomeFinal = '$tipoTitleCase $nomePrincipalTitleCase'.trim();
      }
    } else {
      // Caso de Nome Normal (Ex: "Pereira de Miranda" + "Rua")
      nomeFinal = '$tipoTitleCase $nomePrincipalTitleCase'.trim();
    }

    // 3. TERCEIRA ETAPA: Colocar o Qualificador de Bairro no FINAL
    
    // Se o nome foi encontrado, adiciona o qualificador (se houver) ao final.
    if (qualificador.isNotEmpty) {
      return '$nomeFinal $qualificador';
    }

    return nomeFinal;
  }
  
  Map<String, dynamic> toJson() {
    return {'id': id, 'nome': nome, 'tipo': tipo};
  }
}