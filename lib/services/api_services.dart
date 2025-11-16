import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/itinerary.dart';
import '../models/line.dart';
import '../models/schedule.dart';
import '../models/logradouro.dart';

class ApiServices {
  static const String baseUrl = 'http://gistapis.etufor.ce.gov.br:8081/api';

  /// Busca o itinerário de uma linha específica
  Future<Map<String, Itinerary>> fetchItinerary(int idLinha) async {
    final response = await http.get(Uri.parse('$baseUrl/itinerario/$idLinha'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;

      return {
        'ida': Itinerary.fromJson(data['ida'] as Map<String, dynamic>),
        'volta': Itinerary.fromJson(data['volta'] as Map<String, dynamic>),
      };
    } else {
      throw Exception('Failed to load itinerary');
    }
  }

  /// Busca todas as linhas disponíveis
  Future<List<Line>> fetchLines() async {
    final response = await http.get(Uri.parse('$baseUrl/linhas/'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List<dynamic>;
      return data.map((json) => Line.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load lines');
    }
  }

  /// Busca os horários de uma linha para uma data específica
  Future<List<Schedule>> fetchSchedules(int idLinha, String date) async {
    final response = await http.get(Uri.parse('$baseUrl/horarios/$idLinha?data=$date'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List<dynamic>;
      return data.map((json) => Schedule.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load schedules');
    }
  }

  /// Busca todos os logradouros
  Future<List<Logradouro>> fetchLogradouros() async {
    final response = await http.get(Uri.parse('$baseUrl/logradouros/'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List<dynamic>;
      return data.map((json) => Logradouro.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load logradouros');
    }
  }

  /// Busca as linhas que passam por um logradouro específico
  Future<List<Line>> fetchLinesByLogradouro(int idLogradouro) async {
    final response = await http.get(Uri.parse('$baseUrl/LinhasDologradouro/$idLogradouro'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List<dynamic>;
      return data.map((json) => Line.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load lines by logradouro');
    }
  }

  /// Busca todos os logradouros (para encontrar pontos de conexão)
  Future<List<Logradouro>> fetchAllLogradouros() async {
    return fetchLogradouros();
  }
}
