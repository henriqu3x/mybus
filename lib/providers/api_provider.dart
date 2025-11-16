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

  /// Busca sugestões de rotas entre dois logradouros
  Future<List<RouteSuggestion>> fetchRouteSuggestions(Logradouro origin, Logradouro destination) async {
    // Primeiro, tenta encontrar rotas diretas (limita a 2)
    final directLines = await _findDirectRoutes(origin, destination);
    if (directLines.isNotEmpty) {
      return directLines.take(2).map((line) => RouteSuggestion.direct(line)).toList();
    }

    // Se não há rotas diretas, busca rotas com uma conexão (limita a 2)
    final connectionRoutes = await _findRoutesWithConnection(origin, destination);
    return connectionRoutes.take(2).toList();
  }

  /// Encontra rotas diretas entre origem e destino
  Future<List<Line>> _findDirectRoutes(Logradouro origin, Logradouro destination) async {
    List<Line> originLines = [];
    List<Line> destinationLines = [];

    try {
      originLines = await _apiServices.fetchLinesByLogradouro(origin.id);
    } catch (e) {
      // Se falhar, assume que não há linhas para este logradouro
      originLines = [];
    }

    try {
      destinationLines = await _apiServices.fetchLinesByLogradouro(destination.id);
    } catch (e) {
      // Se falhar, assume que não há linhas para este logradouro
      destinationLines = [];
    }

    return originLines.where((line) =>
      destinationLines.any((destLine) => destLine.id == line.id)
    ).toList();
  }

  /// Encontra rotas com uma conexão
  Future<List<RouteSuggestion>> _findRoutesWithConnection(Logradouro origin, Logradouro destination) async {
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

    // Para cada linha da origem, busca pontos de conexão
    for (final originLine in originLines) {
      if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

      Map<String, Itinerary>? originItinerary;
      try {
        originItinerary = await _apiServices.fetchItinerary(originLine.id);
      } catch (e) {
        continue; // Pula esta linha se não conseguir o itinerário
      }

      // Coleta todos os pontos únicos desta linha (de ambos os sentidos)
      final allPoints = <int, Logradouro>{};
      for (final direction in ['ida', 'volta']) {
        final itinerary = originItinerary[direction]!;
        for (final point in itinerary.points) {
          if (point.logId != origin.id) { // Exclui o ponto de origem
            allPoints[point.logId] = Logradouro(id: point.logId, nome: point.name, tipo: 'Ponto');
          }
        }
      }

      // Para cada ponto possível de transferência nesta linha
      for (final transferLogradouro in allPoints.values) {
        if (uniqueSuggestions.length >= 2) break; // Para quando encontrar 2 sugestões

        // Verifica se alguma linha do destino passa por este ponto de transferência
        List<Line> transferLines = [];
        try {
          transferLines = await _apiServices.fetchLinesByLogradouro(transferLogradouro.id);
        } catch (e) {
          continue; // Pula se não conseguir linhas para o ponto de transferência
        }

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
}
