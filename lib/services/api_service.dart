import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/horario.dart';
import '../models/itinerario.dart';
import '../models/linha.dart';
import '../models/logradouro.dart';

class ApiService {
  static const String baseUrl = 'http://gistapis.etufor.ce.gov.br:8081/api';
  static const Duration _requestTimeout = Duration(seconds: 10);

  // Simple in-memory cache
  final Map<String, dynamic> _cache = {};

  Future<dynamic> _getWithCache(String endpoint) async {
    if (_cache.containsKey(endpoint)) {
      return _cache[endpoint];
    }

    try {
      final response = await http
          .get(Uri.parse('$baseUrl$endpoint'))
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cache[endpoint] = data;
        return data;
      }

      throw Exception('ETUFOR retornou status ${response.statusCode}.');
    } on TimeoutException {
      throw Exception(
        'A consulta a ETUFOR demorou mais de 10 segundos e expirou.',
      );
    } catch (e) {
      throw Exception('Falha ao carregar dados de $endpoint: $e');
    }
  }

  Future<List<Linha>> getLinhas() async {
    final body = await _getWithCache('/linhas/');
    return (body as List).map((dynamic item) => Linha.fromJson(item)).toList();
  }

  Future<ItinerarioCompleto> getItinerario(int idLinha) async {
    final body = await _getWithCache('/itinerario/$idLinha');
    return ItinerarioCompleto.fromJson(body);
  }

  Future<List<HorarioPosto>> getHorarios(int idLinha, String data) async {
    // data format: YYYYMMDD
    final body = await _getWithCache('/horarios/$idLinha?data=$data');
    return (body as List)
        .map((dynamic item) => HorarioPosto.fromJson(item))
        .toList();
  }

  Future<List<Logradouro>> getLogradouros() async {
    final body = await _getWithCache('/logradouros/');
    return (body as List)
        .map((dynamic item) => Logradouro.fromJson(item))
        .toList();
  }

  Future<List<Linha>> getLinhasPorLogradouro(int idLogradouro) async {
    final body = await _getWithCache('/LinhasDologradouro/$idLogradouro');
    return (body as List).map((dynamic item) => Linha.fromJson(item)).toList();
  }
}
