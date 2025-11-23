import 'package:flutter/material.dart';
import '../models/linha.dart';
import '../models/itinerario.dart';
import '../models/horario.dart';
import '../models/logradouro.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/graph_utils.dart';

class BusProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Linha> _linhas = [];
  List<Linha> _filteredLinhas = [];
  List<Logradouro> _logradouros = [];

  // Cache for itineraries to build graph
  final Map<int, ItinerarioCompleto> _itinerarioCache = {};
  TransportGraph? _graph;
  bool _isGraphBuilding = false;

  List<Linha> get linhas => _filteredLinhas;
  List<Logradouro> get logradouros => _logradouros;
  bool get isGraphReady => _graph != null;
  bool get isGraphBuilding => _isGraphBuilding;

  Future<void> fetchLinhas() async {
    try {
      _linhas = await _apiService.getLinhas();
      _filteredLinhas = _linhas;
      notifyListeners();
    } catch (e) {
      print('Error fetching linhas: $e');
    }
  }

  void filterLinhas(String query) {
    if (query.isEmpty) {
      _filteredLinhas = _linhas;
    } else {
      _filteredLinhas = _linhas.where((linha) {
        return linha.nome.toLowerCase().contains(query.toLowerCase()) ||
            linha.numeroNome.toLowerCase().contains(query.toLowerCase());
      }).toList();
    }
    notifyListeners();
  }

  Future<ItinerarioCompleto> getItinerario(int idLinha) async {
    if (_itinerarioCache.containsKey(idLinha)) {
      return _itinerarioCache[idLinha]!;
    }
    final itinerario = await _apiService.getItinerario(idLinha);
    _itinerarioCache[idLinha] = itinerario;
    return itinerario;
  }

  Future<List<HorarioPosto>> getHorarios(int idLinha, String data) async {
    return await _apiService.getHorarios(idLinha, data);
  }

  Future<void> fetchLogradouros() async {
    try {
      _logradouros = await _apiService.getLogradouros();
      notifyListeners();
    } catch (e) {
      print('Error fetching logradouros: $e');
    }
  }

  Future<void> buildGraph() async {
    if (_isGraphBuilding || _graph != null) return;
    _isGraphBuilding = true;
    notifyListeners();

    try {
      if (_linhas.isEmpty) {
        await fetchLinhas();
      }

      // Get current date in YYYYMMDD format
      final now = DateTime.now();
      final dateStr =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";

      List<Map<String, dynamic>> allItineraries = [];

      // Process in batches to avoid overwhelming the server but still be faster than sequential
      int batchSize = 5;
      for (var i = 0; i < _linhas.length; i += batchSize) {
        var end = (i + batchSize < _linhas.length)
            ? i + batchSize
            : _linhas.length;
        var batch = _linhas.sublist(i, end);

        await Future.wait(
          batch.map((linha) async {
            try {
              // Check schedule
              bool isActive = false;
              try {
                final horarios = await getHorarios(linha.numero, dateStr);
                if (horarios.isNotEmpty) isActive = true;
              } catch (e) {
                // Ignore error, treat as inactive
              }

              if (isActive) {
                var itinerarioCompleto = await getItinerario(linha.numero);
                if (itinerarioCompleto.ida != null) {
                  allItineraries.add({
                    'line': linha.numeroNome,
                    'itinerario': itinerarioCompleto.ida,
                  });
                }
                if (itinerarioCompleto.volta != null) {
                  allItineraries.add({
                    'line': linha.numeroNome,
                    'itinerario': itinerarioCompleto.volta,
                  });
                }
              }
            } catch (e) {
              print('Error processing line ${linha.numero}: $e');
            }
          }),
        );
      }

      _graph = TransportGraph();
      _graph!.buildFromItineraries(allItineraries);
    } catch (e) {
      print('Error building graph: $e');
    } finally {
      _isGraphBuilding = false;
      notifyListeners();
    }
  }

  List<GraphEdge>? findRoute(int startLogId, int endLogId) {
    if (_graph == null) return null;
    return _graph!.findShortestPath(startLogId, endLogId);
  }
}
