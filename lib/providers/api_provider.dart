import 'package:flutter/foundation.dart';
import '../services/api_services.dart';
import '../models/itinerary.dart';
import '../models/line.dart';
import '../models/schedule.dart';
import '../models/logradouro.dart';
import '../models/route_suggestion.dart';

class ApiProvider with ChangeNotifier {
  final ApiServices _apiServices = ApiServices();

  // Estado para itinerários
  Map<String, Itinerary>? _itinerary;
  bool _isLoadingItinerary = false;
  String? _errorItinerary;

  // Estado para linhas
  List<Line>? _lines;
  bool _isLoadingLines = false;
  String? _errorLines;

  // Estado para horários
  List<Schedule>? _schedules;
  bool _isLoadingSchedules = false;
  String? _errorSchedules;

  // Estado para logradouros
  List<Logradouro>? _logradouros;
  bool _isLoadingLogradouros = false;
  String? _errorLogradouros;

  // Estado para linhas por logradouro
  List<Line>? _linesByLogradouro;
  bool _isLoadingLinesByLogradouro = false;
  String? _errorLinesByLogradouro;

  // Favoritos
  final List<Line> _favoriteLines = [];

  // Getters para itinerários
  Map<String, Itinerary>? get itinerary => _itinerary;
  bool get isLoadingItinerary => _isLoadingItinerary;
  String? get errorItinerary => _errorItinerary;

  // Getters para linhas
  List<Line>? get lines => _lines;
  bool get isLoadingLines => _isLoadingLines;
  String? get errorLines => _errorLines;

  // Getters para horários
  List<Schedule>? get schedules => _schedules;
  bool get isLoadingSchedules => _isLoadingSchedules;
  String? get errorSchedules => _errorSchedules;

  // Getters para logradouros
  List<Logradouro>? get logradouros => _logradouros;
  bool get isLoadingLogradouros => _isLoadingLogradouros;
  String? get errorLogradouros => _errorLogradouros;

  // Getters para linhas por logradouro
  List<Line>? get linesByLogradouro => _linesByLogradouro;
  bool get isLoadingLinesByLogradouro => _isLoadingLinesByLogradouro;
  String? get errorLinesByLogradouro => _errorLinesByLogradouro;

  // Getters para favoritos
  List<Line> get favoriteLines => _favoriteLines;

  /// Busca o itinerário de uma linha específica
  Future<void> fetchItinerary(int idLinha) async {
    _isLoadingItinerary = true;
    _errorItinerary = null;
    notifyListeners();

    try {
      _itinerary = await _apiServices.fetchItinerary(idLinha);
    } catch (e) {
      _errorItinerary = e.toString();
    } finally {
      _isLoadingItinerary = false;
      notifyListeners();
    }
  }

  /// Busca todas as linhas disponíveis
  Future<void> fetchLines() async {
    _isLoadingLines = true;
    _errorLines = null;
    notifyListeners();

    try {
      _lines = await _apiServices.fetchLines();
    } catch (e) {
      _errorLines = e.toString();
    } finally {
      _isLoadingLines = false;
      notifyListeners();
    }
  }

  /// Busca os horários de uma linha para uma data específica
  Future<void> fetchSchedules(int idLinha, String date) async {
    _isLoadingSchedules = true;
    _errorSchedules = null;
    notifyListeners();

    try {
      _schedules = await _apiServices.fetchSchedules(idLinha, date);
    } catch (e) {
      _errorSchedules = e.toString();
    } finally {
      _isLoadingSchedules = false;
      notifyListeners();
    }
  }

  /// Busca todos os logradouros
  Future<void> fetchLogradouros() async {
    _isLoadingLogradouros = true;
    _errorLogradouros = null;
    notifyListeners();

    try {
      _logradouros = await _apiServices.fetchLogradouros();
    } catch (e) {
      _errorLogradouros = e.toString();
    } finally {
      _isLoadingLogradouros = false;
      notifyListeners();
    }
  }

  /// Busca as linhas que passam por um logradouro específico
  Future<void> fetchLinesByLogradouro(int idLogradouro) async {
    _isLoadingLinesByLogradouro = true;
    _errorLinesByLogradouro = null;
    notifyListeners();

    try {
      _linesByLogradouro = await _apiServices.fetchLinesByLogradouro(idLogradouro);
    } catch (e) {
      _errorLinesByLogradouro = e.toString();
    } finally {
      _isLoadingLinesByLogradouro = false;
      notifyListeners();
    }
  }

  /// Verifica se uma linha está nos favoritos
  bool isFavorite(Line line) {
    return _favoriteLines.any((favorite) => favorite.id == line.id);
  }

  /// Adiciona uma linha aos favoritos
  void addToFavorites(Line line) {
    if (!isFavorite(line)) {
      _favoriteLines.add(line);
      notifyListeners();
    }
  }

  /// Remove uma linha dos favoritos
  void removeFromFavorites(Line line) {
    _favoriteLines.removeWhere((favorite) => favorite.id == line.id);
    notifyListeners();
  }

  /// Limpa o estado de erro para itinerários
  void clearItineraryError() {
    _errorItinerary = null;
    notifyListeners();
  }

  /// Limpa o estado de erro para linhas
  void clearLinesError() {
    _errorLines = null;
    notifyListeners();
  }

  /// Limpa o estado de erro para horários
  void clearSchedulesError() {
    _errorSchedules = null;
    notifyListeners();
  }

  /// Limpa o estado de erro para logradouros
  void clearLogradourosError() {
    _errorLogradouros = null;
    notifyListeners();
  }

  /// Limpa o estado de erro para linhas por logradouro
  void clearLinesByLogradouroError() {
    _errorLinesByLogradouro = null;
    notifyListeners();
  }

  /// Verifica se um itinerário contém um logradouro específico
  bool _itineraryContainsLogradouro(Map<String, Itinerary> itinerary, Logradouro logradouro) {
    for (final direction in ['ida', 'volta']) {
      final dirItinerary = itinerary[direction];
      if (dirItinerary != null) {
        for (final point in dirItinerary.points) {
          if (point.logId == logradouro.id) {
            return true;
          }
          // Fallback to name matching if IDs don't match
          final pointNameNormalized = point.name.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
          final logradouroNameNormalized = logradouro.nome.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

          // Check if one normalized name contains the other
          if (pointNameNormalized.contains(logradouroNameNormalized) || logradouroNameNormalized.contains(pointNameNormalized)) {
            return true;
          }

          // Fallback: check if all words from logradouro are present in point name
          final pointWords = pointNameNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
          final logradouroWords = logradouroNameNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

          if (logradouroWords.isNotEmpty && logradouroWords.every((word) => pointWords.contains(word))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Busca sugestões de rotas entre dois logradouros
  Future<List<RouteSuggestion>> fetchRouteSuggestions(Logradouro origin, Logradouro destination) async {
    print('DEBUG: fetchRouteSuggestions called');
    print('DEBUG: Origin - ID: ${origin.id}, Nome: ${origin.nome}');
    print('DEBUG: Destination - ID: ${destination.id}, Nome: ${destination.nome}');

    // Primeiro, tenta encontrar rotas diretas (limita a 2)
    final directLines = await _findDirectRoutes(origin, destination);
    print('DEBUG: Direct lines found: ${directLines.length} - ${directLines.map((l) => l.id).toList()}');
    if (directLines.isNotEmpty) {
      return directLines.take(2).map((line) => RouteSuggestion.direct(line)).toList();
    }

    // Se não há rotas diretas, busca rotas com uma conexão (limita a 2)
    final connectionRoutes = await _findRoutesWithConnection(origin, destination);
    print('DEBUG: Connection routes found: ${connectionRoutes.length}');
    if (connectionRoutes.isNotEmpty) {
      return connectionRoutes.take(2).toList();
    }

    // Se não há rotas com uma conexão, busca rotas com duas conexões (limita a 2)
    final twoConnectionRoutes = await _findRoutesWithTwoConnections(origin, destination);
    print('DEBUG: Two connection routes found: ${twoConnectionRoutes.length}');
    return twoConnectionRoutes.take(2).toList();
  }

  /// Encontra rotas diretas entre origem e destino usando itinerários
  Future<List<Line>> _findDirectRoutes(Logradouro origin, Logradouro destination) async {
    List<Line> originLines = [];
    List<Line> destinationLines = [];
    bool originFailed = false;
    bool destinationFailed = false;

    try {
      originLines = await _apiServices.fetchLinesByLogradouro(origin.id);
      print('DEBUG: Origin lines for ${origin.id}: ${originLines.map((l) => l.id).toList()}');
    } catch (e) {
      print('DEBUG: Failed to fetch origin lines for ${origin.id}: $e');
      originFailed = true;
      originLines = [];
    }

    try {
      destinationLines = await _apiServices.fetchLinesByLogradouro(destination.id);
      print('DEBUG: Destination lines for ${destination.id}: ${destinationLines.map((l) => l.id).toList()}');
    } catch (e) {
      print('DEBUG: Failed to fetch destination lines for ${destination.id}: $e');
      destinationFailed = true;
      destinationLines = [];
    }

    // Primeiro, tenta encontrar linhas comuns pelos IDs (método original)
    final commonLinesById = originLines.where((line) =>
      destinationLines.any((destLine) => destLine.id == line.id)
    ).toList();

    print('DEBUG: Common lines by ID: ${commonLinesById.map((l) => l.id).toList()}');
    if (commonLinesById.isNotEmpty) {
      return commonLinesById;
    }

    // Se uma das chamadas falhou, tenta abordagem alternativa: buscar todas as linhas e verificar itinerários
    if (originFailed || destinationFailed) {
      print('DEBUG: One of the API calls failed, trying alternative approach with all lines');
      try {
        final allLines = await _apiServices.fetchLines();
        final directLines = <Line>[];

        for (final line in allLines) {
          try {
            final itinerary = await _apiServices.fetchItinerary(line.id);
            final hasOrigin = _itineraryContainsLogradouro(itinerary, origin);
            final hasDestination = _itineraryContainsLogradouro(itinerary, destination);
            print('DEBUG: Line ${line.id} - hasOrigin: $hasOrigin, hasDestination: $hasDestination');

            if (hasOrigin && hasDestination) {
              directLines.add(line);
            }
          } catch (e) {
            print('DEBUG: Failed to fetch itinerary for line ${line.id}: $e');
            continue;
          }
        }

        print('DEBUG: Direct lines found via alternative approach: ${directLines.map((l) => l.id).toList()}');
        return directLines;
      } catch (e) {
        print('DEBUG: Failed to fetch all lines: $e');
        return [];
      }
    }

    // Se não encontrou por ID, verifica itinerários para encontrar linhas que passam por ambos os pontos
    final directLines = <Line>[];

    for (final line in originLines) {
      try {
        final itinerary = await _apiServices.fetchItinerary(line.id);
        final hasOrigin = _itineraryContainsLogradouro(itinerary, origin);
        final hasDestination = _itineraryContainsLogradouro(itinerary, destination);
        print('DEBUG: Line ${line.id} - hasOrigin: $hasOrigin, hasDestination: $hasDestination');

        if (hasOrigin && hasDestination) {
          directLines.add(line);
        }
      } catch (e) {
        print('DEBUG: Failed to fetch itinerary for line ${line.id}: $e');
        // Pula linhas com erro no itinerário
        continue;
      }
    }

    print('DEBUG: Direct lines found via itinerary: ${directLines.map((l) => l.id).toList()}');
    return directLines;
  }

  /// Encontra rotas com uma conexão usando itinerários
  Future<List<RouteSuggestion>> _findRoutesWithConnection(Logradouro origin, Logradouro destination) async {
    final uniqueSuggestions = <RouteSuggestion>[];
    final seen = <String>{};

    // Busca linhas da origem
    List<Line> originLines = [];
    bool originFailed = false;
    try {
      originLines = await _apiServices.fetchLinesByLogradouro(origin.id);
    } catch (e) {
      print('DEBUG: Failed to fetch origin lines for ${origin.id}: $e');
      originFailed = true;
    }

    // Fallback se a API falhar: buscar todas as linhas e verificar itinerários
    if (originFailed || originLines.isEmpty) {
      try {
        final allLines = await _apiServices.fetchLines();
        for (final line in allLines) {
          try {
            final itinerary = await _apiServices.fetchItinerary(line.id);
            if (_itineraryContainsLogradouro(itinerary, origin)) {
              originLines.add(line);
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        print('DEBUG: Failed to fetch all lines for origin fallback: $e');
      }
    }
    if (originLines.isEmpty) return uniqueSuggestions;

    // Busca linhas do destino
    List<Line> destinationLines = [];
    bool destinationFailed = false;
    try {
      destinationLines = await _apiServices.fetchLinesByLogradouro(destination.id);
    } catch (e) {
      print('DEBUG: Failed to fetch destination lines for ${destination.id}: $e');
      destinationFailed = true;
    }

    // Fallback se a API falhar: buscar todas as linhas e verificar itinerários
    if (destinationFailed || destinationLines.isEmpty) {
      try {
        final allLines = await _apiServices.fetchLines();
        for (final line in allLines) {
          try {
            final itinerary = await _apiServices.fetchItinerary(line.id);
            if (_itineraryContainsLogradouro(itinerary, destination)) {
              destinationLines.add(line);
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        print('DEBUG: Failed to fetch all lines for destination fallback: $e');
      }
    }
    if (destinationLines.isEmpty) return uniqueSuggestions;

    // Para cada linha da origem, busca pontos de conexão baseados em itinerários
    for (final originLine in originLines) {
      if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

      Map<String, Itinerary>? originItinerary;
      try {
        originItinerary = await _apiServices.fetchItinerary(originLine.id);
      } catch (e) {
        continue; // Pula esta linha se não conseguir o itinerário
      }

      // Coleta todos os pontos únicos desta linha (de ambos os sentidos)
      final allPoints = <String, Logradouro>{};
      for (final direction in ['ida', 'volta']) {
        final itinerary = originItinerary[direction]!;
        for (final point in itinerary.points) {
          if (!_itineraryContainsLogradouro({direction: itinerary}, origin)) { // Exclui o ponto de origem
            // Normalize point name by removing the number prefix (e.g., "01-" -> "")
            final normalizedName = point.name.replaceFirst(RegExp(r'^\d+-'), '');
            allPoints[normalizedName.toLowerCase().trim()] = Logradouro(id: point.logId, nome: normalizedName, tipo: 'Ponto');
          }
        }
      }

      // Para cada ponto possível de transferência nesta linha
      for (final transferLogradouro in allPoints.values) {
        if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

        // Verifica se alguma linha do destino passa por este ponto de transferência
        // Sempre usa abordagem baseada em itinerário para maior confiabilidade
        List<Line> transferLines = await _findLinesByItineraryPoint(transferLogradouro, destinationLines);

        final connectingLines = transferLines.where((line) =>
          destinationLines.any((destLine) => destLine.id == line.id) && line.id != originLine.id
        ).toList();

        for (final connectingLine in connectingLines) {
          if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

          final suggestion = RouteSuggestion.withConnection(
            firstLine: originLine,
            transferPoint: transferLogradouro,
            secondLine: connectingLine,
          );

          final key = '${suggestion.steps[0].line.id}-${suggestion.steps[1].line.id}-${suggestion.steps[1].from?.id}';
          if (!seen.contains(key)) {
            seen.add(key);
            uniqueSuggestions.add(suggestion);
          }
        }
      }
    }

    return uniqueSuggestions;
  }

  /// Encontra linhas que passam por um ponto específico usando itinerários
  Future<List<Line>> _findLinesByItineraryPoint(Logradouro point, List<Line> candidateLines) async {
    final matchingLines = <Line>[];

    for (final line in candidateLines) {
      try {
        final itinerary = await _apiServices.fetchItinerary(line.id);
        if (_itineraryContainsLogradouro(itinerary, point)) {
          matchingLines.add(line);
        }
      } catch (e) {
        // Pula linhas com erro no itinerário
        continue;
      }
    }

    return matchingLines;
  }

  /// Encontra rotas com duas conexões usando itinerários
  Future<List<RouteSuggestion>> _findRoutesWithTwoConnections(Logradouro origin, Logradouro destination) async {
    final uniqueSuggestions = <RouteSuggestion>[];
    final seen = <String>{};

    // Busca linhas da origem
    List<Line> originLines = [];
    try {
      originLines = await _apiServices.fetchLinesByLogradouro(origin.id);
    } catch (e) {
      return uniqueSuggestions; // Sem linhas de origem, não há rotas
    }
    if (originLines.isEmpty) return uniqueSuggestions;

    // Busca linhas do destino
    List<Line> destinationLines = [];
    try {
      destinationLines = await _apiServices.fetchLinesByLogradouro(destination.id);
    } catch (e) {
      return uniqueSuggestions; // Sem linhas de destino, não há rotas
    }
    if (destinationLines.isEmpty) return uniqueSuggestions;

    // Para cada linha da origem, busca pontos de primeira conexão
    for (final originLine in originLines) {
      if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

      Map<String, Itinerary>? originItinerary;
      try {
        originItinerary = await _apiServices.fetchItinerary(originLine.id);
      } catch (e) {
        continue; // Pula esta linha se não conseguir o itinerário
      }

      // Coleta todos os pontos únicos desta linha (de ambos os sentidos)
      final firstTransferPoints = <String, Logradouro>{};
      for (final direction in ['ida', 'volta']) {
        final itinerary = originItinerary[direction]!;
        for (final point in itinerary.points) {
          if (!_itineraryContainsLogradouro({direction: itinerary}, origin)) { // Exclui o ponto de origem
            firstTransferPoints[point.name.toLowerCase().trim()] = Logradouro(id: point.logId, nome: point.name, tipo: 'Ponto');
          }
        }
      }

      // Para cada ponto de primeira transferência
      for (final firstTransfer in firstTransferPoints.values) {
        if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

        // Busca linhas que passam pelo primeiro ponto de transferência
        List<Line> firstTransferLines = [];
        try {
          firstTransferLines = await _apiServices.fetchLinesByLogradouro(firstTransfer.id);
        } catch (e) {
          // Se falhar por ID, tenta encontrar linhas que passam pelo ponto via itinerário
          firstTransferLines = await _findLinesByItineraryPoint(firstTransfer, await _apiServices.fetchLines());
        }

        // Filtra linhas que são diferentes da linha de origem
        firstTransferLines = firstTransferLines.where((line) => line.id != originLine.id).toList();

        // Para cada linha do primeiro ponto de transferência, busca pontos de segunda conexão
        for (final middleLine in firstTransferLines) {
          if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

          Map<String, Itinerary>? middleItinerary;
          try {
            middleItinerary = await _apiServices.fetchItinerary(middleLine.id);
          } catch (e) {
            continue; // Pula esta linha se não conseguir o itinerário
          }

          // Coleta pontos únicos da linha intermediária (excluindo o primeiro ponto de transferência)
          final secondTransferPoints = <String, Logradouro>{};
          for (final direction in ['ida', 'volta']) {
            final itinerary = middleItinerary[direction]!;
            for (final point in itinerary.points) {
              if (!_itineraryContainsLogradouro({direction: itinerary}, firstTransfer)) { // Exclui o primeiro ponto de transferência
                secondTransferPoints[point.name.toLowerCase().trim()] = Logradouro(id: point.logId, nome: point.name, tipo: 'Ponto');
              }
            }
          }

          // Para cada ponto de segunda transferência
          for (final secondTransfer in secondTransferPoints.values) {
            if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

            // Verifica se alguma linha do destino passa por este segundo ponto de transferência
            List<Line> secondTransferLines = [];
            try {
              secondTransferLines = await _apiServices.fetchLinesByLogradouro(secondTransfer.id);
            } catch (e) {
              // Se falhar por ID, tenta encontrar linhas que passam pelo ponto via itinerário
              secondTransferLines = await _findLinesByItineraryPoint(secondTransfer, destinationLines);
            }

            final finalConnectingLines = secondTransferLines.where((line) =>
              destinationLines.any((destLine) => destLine.id == line.id) && line.id != middleLine.id
            ).toList();

            for (final finalLine in finalConnectingLines) {
              if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

              final suggestion = RouteSuggestion.withTwoConnections(
                firstLine: originLine,
                firstTransferPoint: firstTransfer,
                secondLine: middleLine,
                secondTransferPoint: secondTransfer,
                thirdLine: finalLine,
              );

              final key = '${suggestion.steps[0].line.id}-${suggestion.steps[1].line.id}-${suggestion.steps[1].from?.id}-${suggestion.steps[2].line.id}-${suggestion.steps[2].from?.id}';
              if (!seen.contains(key)) {
                seen.add(key);
                uniqueSuggestions.add(suggestion);
              }
            }
          }
        }
      }
    }

    return uniqueSuggestions;
  }
}
