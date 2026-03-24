import 'package:flutter/material.dart';

import '../models/horario.dart';
import '../models/itinerario.dart';
import '../models/linha.dart';
import '../models/logradouro.dart';
import '../services/api_service.dart';
import '../services/graph_cache_service.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';

class BusProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final GraphCacheService _graphCacheService = GraphCacheService();

  List<Linha> _linhas = [];
  List<Linha> _filteredLinhas = [];
  List<Logradouro> _logradouros = [];

  bool _isLoading = false;
  String? _error;

  final Map<int, ItinerarioCompleto> _itinerarioCache = {};
  TransportGraph? _graph;
  bool _isGraphBuilding = false;

  List<Linha> get linhas => _filteredLinhas;
  List<Logradouro> get logradouros => _logradouros;
  bool get isGraphReady => _graph != null;
  bool get isGraphBuilding => _isGraphBuilding;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void>? _linesLoadingFuture;

  void _setError(String message, [Object? error]) {
    _error = message;
    debugPrint('$message${error != null ? ' | $error' : ''}');
  }

  Future<void> fetchLinhas({bool forceRefresh = false}) async {
    if (_linesLoadingFuture != null) {
      return _linesLoadingFuture;
    }

    if (_linhas.isNotEmpty && !forceRefresh) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    _linesLoadingFuture = _fetchLinhasInternal();

    try {
      await _linesLoadingFuture;
    } finally {
      _linesLoadingFuture = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchLinhasInternal() async {
    try {
      _linhas = await _apiService.getLinhas();
      _filteredLinhas = _linhas;
    } catch (e) {
      _linhas = [];
      _filteredLinhas = [];
      _setError(
        'Erro ao carregar linhas. Verifique sua conexao e tente novamente.',
        e,
      );
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

  Linha? getLineByNumber(String number) {
    try {
      final num = int.tryParse(number);
      if (num == null) return null;

      return _linhas.firstWhere(
        (l) => l.numero == num,
        orElse: () => Linha(
          numero: num,
          nome: 'Linha $number',
          numeroNome: 'Linha $number',
          tipoLinha: '',
        ),
      );
    } catch (e) {
      return null;
    }
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logradouros = await _apiService.getLogradouros();
    } catch (e) {
      _logradouros = [];
      _setError(
        'Erro ao carregar logradouros. Verifique sua conexao e tente novamente.',
        e,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> buildGraph({bool forceRebuild = false}) async {
    if (_isGraphBuilding) return;
    if (_graph != null && !forceRebuild) return;

    if (forceRebuild) {
      _graph = null;
    }

    _isGraphBuilding = true;
    _error = null;
    notifyListeners();

    try {
      if (!forceRebuild) {
        final cachedGraph = await _graphCacheService.loadGraphIfFresh();
        if (cachedGraph != null) {
          _graph = cachedGraph;
          return;
        }
      } else {
        await _graphCacheService.clearInvalidCache();
      }

      if (_linhas.isEmpty) {
        await fetchLinhas();
      }

      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

      List<Map<String, dynamic>> allItineraries = [];
      int failedLines = 0;

      const batchSize = 5;
      for (var i = 0; i < _linhas.length; i += batchSize) {
        var end = (i + batchSize < _linhas.length)
            ? i + batchSize
            : _linhas.length;
        var batch = _linhas.sublist(i, end);

        await Future.wait(
          batch.map((linha) async {
            try {
              bool isActive = false;
              try {
                final horarios = await getHorarios(linha.numero, dateStr);
                if (horarios.isNotEmpty) isActive = true;
              } catch (e) {
                failedLines++;
                debugPrint(
                  'Erro ao carregar horarios da linha ${linha.numero}: $e',
                );
              }

              if (isActive) {
                final itinerarioCompleto = await getItinerario(linha.numero);
                if (itinerarioCompleto.ida != null) {
                  allItineraries.add({
                    'line': '${linha.numeroNome.trim()}_IDA',
                    'itinerario': itinerarioCompleto.ida,
                  });
                }
                if (itinerarioCompleto.volta != null) {
                  allItineraries.add({
                    'line': '${linha.numeroNome.trim()}_VOLTA',
                    'itinerario': itinerarioCompleto.volta,
                  });
                }
              }
            } catch (e) {
              failedLines++;
              debugPrint(
                'Erro ao montar itinerario da linha ${linha.numero}: $e',
              );
            }
          }),
        );
      }

      if (allItineraries.isEmpty) {
        _graph = null;
        _setError(
          failedLines > 0
              ? 'Nao foi possivel carregar dados suficientes para planejar a viagem.'
              : 'Nenhum itinerario ativo foi encontrado para montar a rede de transporte.',
        );
        return;
      }

      _graph = TransportGraph();
      _graph!.buildFromItineraries(allItineraries);
      _error = null;

      try {
        await _graphCacheService.saveGraphForToday(_graph!);
      } catch (e) {
        debugPrint('Nao foi possivel persistir o cache do grafo: $e');
      }
    } catch (e) {
      _graph = null;
      _setError(
        'Erro ao construir a rede de transporte. Tente novamente em instantes.',
        e,
      );
    } finally {
      _isGraphBuilding = false;
      notifyListeners();
    }
  }

  Future<List<List<GraphEdge>>> findRoutes(int startLogId, int endLogId) async {
    final List<List<GraphEdge>> foundRoutes = [];
    if (_graph == null) return foundRoutes;

    final Map<String, int> initialWaitTimes = await _calculateInitialWaitTimes(
      startLogId,
    );
    final Set<String> penalizedLines = {};

    for (int i = 0; i < 3; i++) {
      final route = await _findSingleValidRoute(
        startLogId,
        endLogId,
        initialWaitTimes,
        penalizedLines: penalizedLines,
      );

      if (route != null) {
        final routeStr = route.map((e) => e.lineName).join(',');
        final isDuplicate = foundRoutes.any(
          (r) => r.map((e) => e.lineName).join(',') == routeStr,
        );

        if (!isDuplicate) {
          foundRoutes.add(route);
          for (final edge in route) {
            penalizedLines.add(edge.lineName);
          }
        } else {
          break;
        }
      } else {
        break;
      }
    }

    return foundRoutes;
  }

  Future<List<GraphEdge>?> _findSingleValidRoute(
    int startLogId,
    int endLogId,
    Map<String, int> initialWaitTimes, {
    Set<String>? penalizedLines,
  }) async {
    final Set<String> excludedLines = {};
    int attempts = 0;
    const maxAttempts = 5;

    final today = DateTime.now();
    final dateStr =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

    while (attempts < maxAttempts) {
      var route = _graph!.findShortestPath(
        startLogId,
        endLogId,
        initialWaitTimes: initialWaitTimes,
        excludedLines: excludedLines,
        penalizedLines: penalizedLines,
      );

      if (route == null || route.isEmpty) {
        return null;
      }

      final invalidLine = await _validateRouteSegments(
        route,
        currentMinutes,
        dateStr,
      );

      if (invalidLine == null) {
        return route;
      }

      excludedLines.add(invalidLine);
      attempts++;
    }

    return null;
  }

  Future<Map<String, int>> _calculateInitialWaitTimes(int startLogId) async {
    final Map<String, int> initialWaitTimes = {};
    final today = DateTime.now();
    final dateStr =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

    for (var linha in _linhas) {
      if (!_itinerarioCache.containsKey(linha.numero)) continue;

      final itinerarioCompleto = _itinerarioCache[linha.numero]!;

      if (itinerarioCompleto.ida != null) {
        double dist = 0;
        bool found = false;
        for (var p in itinerarioCompleto.ida!.pontos) {
          if (p.logId == startLogId) {
            found = true;
            break;
          }
          dist += p.distanciaPercorrida;
        }

        if (found) {
          final wait = await _calculateNextBusWaitTime(
            linha.numero,
            dateStr,
            itinerarioCompleto.ida!.pontoInicial,
            dist,
            currentMinutes,
          );
          final key = '${linha.numeroNome.trim()}_IDA';
          if (wait != null) {
            if (wait > 45) {
              initialWaitTimes[key] = 999999;
            } else {
              initialWaitTimes[key] = wait;
            }
          } else {
            initialWaitTimes[key] = 999999;
          }
        }
      }

      if (itinerarioCompleto.volta != null) {
        double dist = 0;
        bool found = false;
        for (var p in itinerarioCompleto.volta!.pontos) {
          if (p.logId == startLogId) {
            found = true;
            break;
          }
          dist += p.distanciaPercorrida;
        }

        if (found) {
          final wait = await _calculateNextBusWaitTime(
            linha.numero,
            dateStr,
            itinerarioCompleto.volta!.pontoInicial,
            dist,
            currentMinutes,
          );
          final key = '${linha.numeroNome.trim()}_VOLTA';
          if (wait != null) {
            if (wait > 45) {
              initialWaitTimes[key] = 999999;
            } else {
              initialWaitTimes[key] = wait;
            }
          } else {
            initialWaitTimes[key] = 999999;
          }
        }
      }
    }
    return initialWaitTimes;
  }

  Future<String?> _validateRouteSegments(
    List<GraphEdge> route,
    int startMinutes,
    String dateStr,
  ) async {
    int currentMinutes = startMinutes;
    String? previousLine;

    for (int i = 0; i < route.length; i++) {
      final edge = route[i];

      if (edge.lineName != previousLine) {
        String lineNameClean = edge.lineName
            .replaceAll('_IDA', '')
            .replaceAll('_VOLTA', '')
            .trim();
        final match = RegExp(r'^(\d+)').firstMatch(lineNameClean);
        if (match == null) continue;

        int lineNum = int.parse(match.group(1)!);

        if (i > 0) {
          int boardingStopId = route[i - 1].destination.id;

          var itinerarioCompleto = await getItinerario(lineNum);
          var itinerario = edge.lineName.endsWith('_VOLTA')
              ? itinerarioCompleto.volta
              : itinerarioCompleto.ida;

          if (itinerario == null) {
            return edge.lineName;
          }

          double dist = 0;
          bool found = false;
          for (var p in itinerario.pontos) {
            if (p.logId == boardingStopId) {
              found = true;
              break;
            }
            dist += p.distanciaPercorrida;
          }

          if (!found) {
            return edge.lineName;
          }

          final waitMinutes = await _calculateNextBusWaitTime(
            lineNum,
            dateStr,
            itinerario.pontoInicial,
            dist,
            currentMinutes,
          );

          if (waitMinutes == null || waitMinutes > 45) {
            return edge.lineName;
          }

          currentMinutes += waitMinutes;
        }
      }

      int travelMinutes = TimeUtils.calculateTravelTimeMinutes(edge.weight);
      currentMinutes += travelMinutes;

      previousLine = edge.lineName;
    }

    return null;
  }

  Future<int?> _calculateNextBusWaitTime(
    int linhaId,
    String date,
    String pontoInicial,
    double distanceToStop,
    int currentMinutes,
  ) async {
    try {
      final horarios = await getHorarios(linhaId, date);

      HorarioPosto? matchingPosto;
      for (var posto in horarios) {
        if (_areNamesSimilar(posto.postoControle, pontoInicial)) {
          matchingPosto = posto;
          break;
        }
      }

      if (matchingPosto == null && horarios.isNotEmpty) {
        if (horarios.length == 1) matchingPosto = horarios.first;
      }

      if (matchingPosto == null) return null;

      final travelMinutes = TimeUtils.calculateTravelTimeMinutes(distanceToStop);

      int? bestArrival;

      for (var h in matchingPosto.horarios) {
        try {
          final parts = h.horario.split(':');
          final departureMinutes =
              int.parse(parts[0]) * 60 + int.parse(parts[1]);
          final arrivalMinutes = departureMinutes + travelMinutes;

          if (arrivalMinutes > currentMinutes) {
            bestArrival = arrivalMinutes;
            break;
          }
        } catch (e) {
          debugPrint(
            'Horario invalido na linha $linhaId: ${h.horario} | $e',
          );
        }
      }

      if (bestArrival != null) {
        return bestArrival - currentMinutes;
      }
    } catch (e) {
      debugPrint(
        'Erro ao calcular proximo horario da linha $linhaId em $pontoInicial: $e',
      );
    }
    return null;
  }

  bool _areNamesSimilar(String name1, String name2) {
    final n1 = _normalizeName(name1);
    final n2 = _normalizeName(name2);

    if (n1.contains(n2) || n2.contains(n1)) return true;

    final words1 = n1.split(' ').where((w) => w.length > 2).toSet();
    final words2 = n2.split(' ').where((w) => w.length > 2).toSet();

    if (words1.isEmpty || words2.isEmpty) return false;

    final intersection = words1.intersection(words2);
    return intersection.length >= words1.length * 0.6 ||
        intersection.length >= words2.length * 0.6;
  }

  String _normalizeName(String name) {
    return name.toLowerCase()
        .replaceAll(RegExp(r'^\d+-'), '')
        .replaceAll(RegExp(r'[Ã¡Ã Ã¢Ã£Ã¤]'), 'a')
        .replaceAll(RegExp(r'[Ã©Ã¨ÃªÃ«]'), 'e')
        .replaceAll(RegExp(r'[Ã­Ã¬Ã®Ã¯]'), 'i')
        .replaceAll(RegExp(r'[Ã³Ã²Ã´ÃµÃ¶]'), 'o')
        .replaceAll(RegExp(r'[ÃºÃ¹Ã»Ã¼]'), 'u')
        .replaceAll(RegExp(r'[Ã§]'), 'c')
        .replaceAll(RegExp(r'\b(de|da|do|dos|das|e|o|a)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<int?> getPredictedArrivalForStreet(
    int lineId,
    String streetName,
  ) async {
    try {
      final itinerarioCompleto = await getItinerario(lineId);
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final horarios = await getHorarios(lineId, dateStr);
      final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

      for (var itinerario in [itinerarioCompleto.ida, itinerarioCompleto.volta]) {
        if (itinerario == null) continue;

        double cumulativeDist = 0;
        bool found = false;
        for (var ponto in itinerario.pontos) {
          if (_areNamesSimilar(ponto.nome, streetName)) {
            found = true;
            break;
          }
          cumulativeDist += ponto.distanciaPercorrida;
        }

        if (!found) continue;

        HorarioPosto? matchingPosto;
        for (var posto in horarios) {
          if (_areNamesSimilar(posto.postoControle, itinerario.pontoInicial)) {
            matchingPosto = posto;
            break;
          }
        }
        if (matchingPosto == null && horarios.length == 1) {
          matchingPosto = horarios.first;
        }
        if (matchingPosto == null) continue;

        List<int> allDepartureMinutes = [];
        for (var h in matchingPosto.horarios) {
          try {
            final parts = h.horario.split(':');
            final mins = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            allDepartureMinutes.add(mins);
          } catch (e) {
            debugPrint(
              'Horario invalido encontrado para a linha $lineId: ${h.horario} | $e',
            );
          }
        }
        allDepartureMinutes.sort();

        final travelMinutes = TimeUtils.calculateTravelTimeMinutes(
          cumulativeDist,
        );

        for (var depMins in allDepartureMinutes) {
          final arrivalMins = depMins + travelMinutes;
          if (arrivalMins > currentMinutes) {
            return arrivalMins - currentMinutes;
          }
        }
      }
    } catch (e) {
      _setError(
        'Erro ao prever chegada da linha. Verifique sua conexao e tente novamente.',
        e,
      );
    }
    return null;
  }
}
