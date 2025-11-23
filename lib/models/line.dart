import 'logradouro.dart'; // <--- IMPORT OBRIGATÓRIO
import 'package:flutter/foundation.dart';

/// Representa uma linha de ônibus
class Line {
   /// Número da linha (ex: 51, 52, etc.)
   final int id;
  
   /// Nome completo da linha (ex: "Grande Circular I")
   final String name;
  
   /// Número e nome formatado (ex: "051-Grande Circular I")
   final String numeroNome;
  
   /// Tipo da linha (ex: "Complementar", "Alimentadora")
   final String tipoLinha;

    /// LISTA DE PARADAS (Logradouros) DA LINHA EM ORDEM SEQUENCIAL.
    /// ESSENCIAL PARA O DIJKSTRA.
    final List<Logradouro> stops; // <--- CAMPO ADICIONADO

   const Line({
     required this.id,
     required this.name,
     required this.numeroNome,
     required this.tipoLinha,
    this.stops = const [], // <--- ADICIONADO ao construtor (opcionalmente com valor padrão)
   });

   /// Cria uma instância de Line a partir de um mapa JSON
   factory Line.fromJson(Map<String, dynamic> json) {
     // NOTA: A lógica para desserializar 'stops' não está aqui, mas seria necessária
    // se a API retornasse as paradas junto com os dados básicos da linha.
     return Line(
        id: json['numero'] is int ? json['numero'] : int.tryParse(json['numero']?.toString() ?? '0') ?? 0,
        name: (json['nome'] ?? '').toString().trim(),
        numeroNome: (json['numeroNome'] ?? '').toString().trim(),
        tipoLinha: (json['tipoLinha'] ?? '').toString().trim(),
      stops: [], // <--- Inicializa como vazio na desserialização básica
     );
   }

   /// Converte a instância para um mapa JSON
   Map<String, dynamic> toJson() {
     return {
        'numero': id,
        'nome': name,
        'numeroNome': numeroNome,
        'tipoLinha': tipoLinha,
      'stops': stops.map((s) => s.toJson()).toList(), // Adiciona stops
     };
   }
  
   @override
   bool operator ==(Object other) =>
        identical(this, other) ||
        other is Line &&
             runtimeType == other.runtimeType &&
             id == other.id &&
             name == other.name &&
             numeroNome == other.numeroNome &&
             tipoLinha == other.tipoLinha &&
          listEquals(stops, other.stops); // <--- INCLUÍDO NO HASH/EQUALS

   @override
   int get hashCode =>
        id.hashCode ^ name.hashCode ^ numeroNome.hashCode ^ tipoLinha.hashCode ^ stops.hashCode;

   @override
   String toString() {
     return 'Line{id: $id, name: $name, numeroNome: $numeroNome, tipoLinha: $tipoLinha, stopsCount: ${stops.length}}';
   }
}