import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

class StopInfo {
  final int id;
  final String name; // Usually the address or name in description
  final double lat;
  final double lon;
  final List<String> lines;

  StopInfo({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.lines,
  });
}

class KmlService {
  static const String _kmlPath = 'assets/rotas_horarios.kml';
  XmlDocument? _document;

  /// Carrega o arquivo KML dos assets e faz o parse
  Future<void> loadKmlData() async {
    if (_document != null) return;
    try {
      final String data = await rootBundle.loadString(_kmlPath);
      _document = XmlDocument.parse(data);
    } catch (e) {
      rethrow;
    }
  }

  List<List<double>> _parseCoordinates(String rawCoords) {
    final List<List<double>> points = [];
    // O KML separa pontos por espaço ou quebra de linha
    final coordsList = rawCoords.trim().split(RegExp(r'\s+'));

    for (var coordString in coordsList) {
      if (coordString.isEmpty) continue;

      // Cada ponto no KML é "longitude,latitude,altitude"
      final parts = coordString.split(',');
      if (parts.length >= 2) {
        final double? lon = double.tryParse(parts[0].trim());
        final double? lat = double.tryParse(parts[1].trim());

        if (lat != null && lon != null) {
          points.add([lon, lat]); // Mantendo o padrão [longitude, latitude]
        }
      }
    }
    return points;
  }

  /// Busca as coordenadas para uma ou mais linhas.
  /// Retorna uma lista de listas de coordenadas [latitude, longitude].
  /// O formato de retorno é pensado para fácil injeção no JavaScript do OpenLayers.
  Future<List<List<List<double>>>> getCoordinatesForLines(
    List<String> targetLines,
  ) async {
    await loadKmlData();
    final List<List<List<double>>> allLinesCoords = [];

    if (_document == null) return [];

    // Pega todos os Placemarks (rotas) do KML
    final placemarks = _document!.findAllElements('Placemark');

    for (var targetLine in targetLines) {
      // 1. Extraímos o código e o sentido da busca (ex: "014" e "Volta")
      String targetCode = targetLine.split(' - ').first.trim();
      bool isVolta = targetLine.toLowerCase().contains('volta');

      for (var placemark in placemarks) {
        final nameElement = placemark.findElements('name');
        if (nameElement.isEmpty) continue;

        String kmlRouteName = nameElement.first.innerText;

        // 2. Extraímos o código e o sentido do nome que está no KML
        String kmlCode = kmlRouteName.split(' - ').first.trim();
        bool kmlIsVolta = kmlRouteName.toLowerCase().contains('volta');

        // 3. COMPARACAO SEGURA:
        // Verificamos se o número da linha é igual E se o sentido bate
        if (kmlCode == targetCode && kmlIsVolta == isVolta) {
          final lineString = placemark.findElements('LineString').firstOrNull;
          if (lineString != null) {
            final coordsElement = lineString
                .findElements('coordinates')
                .firstOrNull;
            if (coordsElement != null) {
              allLinesCoords.add(_parseCoordinates(coordsElement.innerText));
              // Encontrou a rota certa, pode pular para a próxima linha da busca
              break;
            }
          }
        }
      }
    }
    return allLinesCoords;
  }

  static const String _stopsKmlPath = 'assets/paradas_onibus.kml';
  XmlDocument? _stopsDocument;

  // lookup from API logradouro id -> list of KML stop ids
  final Map<int, List<int>> _logradouroLookup = {};
  bool _logradouroLookupLoaded = false;

  // mapping from normalized street name -> API id (from logradouros_normalizados.json)
  final Map<String, int> _streetNameToApiId = {};
  bool _normalizadosLoaded = false;

  /// Carrega o arquivo KML de paradas e retorna uma lista de StopInfo
  Future<List<StopInfo>> loadStopsMetadata() async {
    final List<StopInfo> stops = [];

    if (_stopsDocument == null) {
      try {
        final String data = await rootBundle.loadString(_stopsKmlPath);
        _stopsDocument = XmlDocument.parse(data);
      } catch (e) {
        return [];
      }
    }

    final placemarks = _stopsDocument!.findAllElements('Placemark');

    for (var placemark in placemarks) {
      try {
        // 1. Extrair ID (Name)
        final nameElement = placemark.getElement('name');
        if (nameElement == null) continue;
        final stopId = int.tryParse(nameElement.innerText.trim());
        if (stopId == null) continue;

        // 2. Extrair Coordenadas
        final pointElement = placemark.getElement('Point');
        if (pointElement == null) continue;
        final coordsElement = pointElement.getElement('coordinates');
        if (coordsElement == null) continue;

        final coordsParts = coordsElement.innerText.trim().split(',');
        if (coordsParts.length < 2) continue;

        final lon = double.tryParse(coordsParts[0]);
        final lat = double.tryParse(coordsParts[1]);
        if (lon == null || lat == null) continue;

        // 3. Extrair Metadata (Description) -> Endereço e Linhas
        final descElement = placemark.getElement('description');
        String name = 'Parada $stopId'; // Default
        List<String> lines = [];

        if (descElement != null) {
          final desc = descElement.innerText;

          // Extrair Endereço (brute force parsing)
          // Look for "Endereço: </b>" and take until "<br>"
          final addressMatch = RegExp(
            r'Endereço: </b>(.*?)(<|$)',
          ).firstMatch(desc);
          if (addressMatch != null && addressMatch.group(1) != null) {
            name = addressMatch.group(1)!.trim();
          }

          // Extrair Linhas
          // "Linhas da parada: </b>X linha(s)<br>042; 071..."
          final linesHeaderMatch = RegExp(
            r'Linhas da parada:.*?<br>(.*?)(]]>|$)',
          ).firstMatch(desc);
          if (linesHeaderMatch != null && linesHeaderMatch.group(1) != null) {
            final linesText = linesHeaderMatch.group(1)!.trim();
            lines = linesText
                .split(';')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }

        stops.add(
          StopInfo(id: stopId, name: name, lat: lat, lon: lon, lines: lines),
        );
      } catch (e) {
        continue;
      }
    }

    return stops;
  }

  /// Carrega arquivo `assets/logradouro_lookup.json` se existir.
  Future<void> _loadLogradouroLookup() async {
    if (_logradouroLookupLoaded) return;
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/logradouro_lookup.json',
      );
      final data = jsonDecode(jsonStr);
      if (data is Map) {
        data.forEach((k, v) {
          try {
            final intKey = int.tryParse(k.toString());
            if (intKey == null) return;
            if (v is List) {
              final ids = <int>[];
              for (var item in v) {
                final iid = (item is int)
                    ? item
                    : int.tryParse(item.toString());
                if (iid != null) ids.add(iid);
              }
              _logradouroLookup[intKey] = ids;
            }
          } catch (e) {
            // ignore malformed entries
          }
        });
      }
    } catch (e) {
      // ignore if file not present or invalid
    }
    _logradouroLookupLoaded = true;
  }

  /// Retorna as paradas (StopInfo) associadas ao id do logradouro da API
  Future<List<StopInfo>> findStopsByApiId(int apiId) async {
    await _loadLogradouroLookup();
    final stops = await loadStopsMetadata();
    // Debug info to help trace missing mappings
    try {
      if (!_logradouroLookupLoaded) {}
      if (_logradouroLookup.containsKey(apiId)) {
        final mapped = _logradouroLookup[apiId]!;
      } else {}
    } catch (e) {}

    final ids = _logradouroLookup[apiId];
    if (ids == null || ids.isEmpty) {
      return [];
    }
    // preserve order from ids list
    final result = <StopInfo>[];
    final mapById = {for (var s in stops) s.id: s};
    for (var id in ids) {
      final s = mapById[id];
      if (s != null) result.add(s);
    }
    return result;
  }

  /// Carrega arquivo `assets/logradouros_normalizados.json` e mapeia nomes normalizados para IDs da API
  Future<void> _loadNormalizadosMapping() async {
    if (_normalizadosLoaded) return;
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/logradouros_normalizados.json',
      );
      final data = jsonDecode(jsonStr);
      if (data is List) {
        for (var entry in data) {
          if (entry is Map) {
            final id = (entry['id'] is int)
                ? entry['id']
                : int.tryParse(entry['id'].toString());
            final nome = (entry['nome'] is String)
                ? entry['nome']
                : entry['nome'].toString();
            if (id != null && nome.isNotEmpty) {
              final normalizedName = _normalizeStreetName(nome);
              _streetNameToApiId[normalizedName] = id;
            }
          }
        }
      }
    } catch (e) {
      // ignore if file not present or invalid
    }
    _normalizadosLoaded = true;
  }

  /// Busca o ID da API para um nome de rua (normalizado)
  /// Retorna null se não encontrar
  Future<int?> getApiIdForStreet(String streetName) async {
    await _loadNormalizadosMapping();
    final normalized = _normalizeStreetName(streetName);
    return _streetNameToApiId[normalized];
  }

  // Mantendo compatibilidade com código anterior se necessário, mas idealmente migrar
  Future<Map<int, List<double>>> loadStopsCoordinates() async {
    final stops = await loadStopsMetadata();
    return {
      for (var s in stops) s.id: [s.lon, s.lat],
    };
  }

  /// Busca paradas de ônibus que passam em uma determinada rua e servem as linhas especificadas
  /// [streetName]: nome da rua (ex: "Rua das Flores", "Avenida Paulista")
  /// [busLines]: lista de números de linhas de ônibus (ex: ["369", "371"])
  /// Retorna uma lista de StopInfo que correspondem aos critérios
  Future<List<StopInfo>> findStopsOnStreet(
    String streetName,
    List<String> busLines,
  ) async {
    final allStops = await loadStopsMetadata();
    final normalizedStreet = _normalizeStreetName(streetName);

    // Normalizar números de linhas (remover prefixos de zeros, etc)
    final normalizedLines = busLines.map((l) => l.trim()).toSet();

    final matchingStops = <StopInfo>[];

    for (var stop in allStops) {
      final normalizedStopName = _normalizeStreetName(stop.name);

      // Verificar se o nome da parada contém a rua
      if (normalizedStopName.contains(normalizedStreet) ||
          normalizedStreet.contains(normalizedStopName)) {
        // Verificar se a parada serve alguma das linhas especificadas
        final hasMatchingLine = stop.lines.any((stopLine) {
          final normalizedStopLine = stopLine.trim();
          return normalizedLines.contains(normalizedStopLine);
        });

        if (hasMatchingLine) {
          matchingStops.add(stop);
        }
      }
    }

    return matchingStops;
  }

  /// Normaliza um nome de rua para facilitar comparação
  /// Remove acentos, converte para minúsculas, remove prefixos como "Rua", "Avenida", etc
  String _normalizeStreetName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(
          RegExp(
            r'\b(rua|avenida|av\.|pça|praça|trav|travessa|rod|rodovia|estrada|est\.|r\.)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Encontra o ponto mais próximo em uma rota de coordenadas
  /// [routeCoordinates]: lista de coordenadas [lon, lat]
  /// [targetLat], [targetLon]: coordenadas alvo
  /// Retorna o índice da coordenada mais próxima e a distância
  ({int index, double distance}) _findClosestPointInRoute(
    List<List<double>> routeCoordinates,
    double targetLat,
    double targetLon,
  ) {
    if (routeCoordinates.isEmpty) return (index: 0, distance: double.infinity);

    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < routeCoordinates.length; i++) {
      final coord = routeCoordinates[i];
      final lon = coord[0];
      final lat = coord[1];

      // Distância euclidiana (simplificada)
      final distance = sqrt(
        (lat - targetLat) * (lat - targetLat) +
            (lon - targetLon) * (lon - targetLon),
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return (index: closestIndex, distance: minDistance);
  }

  /// Corta uma rota de coordenadas desde um ponto de início até um ponto de término
  /// [routeCoordinates]: lista de coordenadas [lon, lat]
  /// [startIndex]: índice da coordenada de início
  /// [endIndex]: índice da coordenada de término
  /// Retorna um sub-segmento da rota
  List<List<double>> _sliceRoute(
    List<List<double>> routeCoordinates,
    int startIndex,
    int endIndex,
  ) {
    if (routeCoordinates.isEmpty) return [];

    // Garante que start <= end
    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    // Garante que os índices estão dentro dos limites
    final clampedStart = start.clamp(0, routeCoordinates.length - 1);
    final clampedEnd = end.clamp(0, routeCoordinates.length - 1);

    return routeCoordinates.sublist(clampedStart, clampedEnd + 1);
  }

  /// Extrai todas as linhas únicas disponíveis no arquivo KML de paradas
  Future<List<String>> getUniqueLines() async {
    final stops = await loadStopsMetadata();
    final allLines = <String>{};

    for (var stop in stops) {
      for (var line in stop.lines) {
        allLines.add(line);
      }
    }

    final sortedLines = allLines.toList()
      ..sort((a, b) {
        // Tenta extrair números para ordenação natural (ex: "042" antes de "371")
        final aNum = int.tryParse(
          a
              .split(RegExp(r'\D+'))
              .firstWhere((e) => e.isNotEmpty, orElse: () => '0'),
        );
        final bNum = int.tryParse(
          b
              .split(RegExp(r'\D+'))
              .firstWhere((e) => e.isNotEmpty, orElse: () => '0'),
        );
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.compareTo(b);
      });

    return sortedLines;
  }

  /// Retorna uma lista com todas as linhas "completas" encontradas no KML de rotas.
  /// Formato esperado: "371 - Parangaba/José Bastos/Centro - Ida"
  /// Isso é útil para o autocomplete.
  Future<List<String>> getAllFullLineNames() async {
    await loadKmlData();
    if (_document == null) return [];

    final placemarks = _document!.findAllElements('Placemark');
    final Set<String> uniqueNames = {};

    for (var placemark in placemarks) {
      final nameElement = placemark.getElement('name');
      if (nameElement != null) {
        uniqueNames.add(nameElement.innerText.trim());
      }
    }

    final sortedList = uniqueNames.toList()
      ..sort((a, b) {
        // Tenta extrair números para ordenação natural
        final aNum = int.tryParse(
          a
              .split(RegExp(r'\D+'))
              .firstWhere((e) => e.isNotEmpty, orElse: () => '0'),
        );
        final bNum = int.tryParse(
          b
              .split(RegExp(r'\D+'))
              .firstWhere((e) => e.isNotEmpty, orElse: () => '0'),
        );
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.compareTo(b);
      });

    return sortedList;
  }

  /// Retorna todas as paradas que servem uma determinada linha
  Future<List<StopInfo>> getStopsForLine(String lineName) async {
    // 1. Carrega todas as paradas que mencionam esse código de linha
    final allStops = await loadStopsMetadata();
    String lineCode = lineName.split(' - ').first.trim();

    final stopsWithLine = allStops.where((stop) {
      return stop.lines.any((l) => l.trim() == lineCode);
    }).toList();

    // 2. Carrega a Geometria (Polyline) da rota selecionada (específica Ida ou Volta)
    final routeData = await getCoordinatesForLines([lineName]);
    if (routeData.isEmpty)
      return stopsWithLine; // Fallback caso não ache a rota

    final routePoints = routeData.first; // Lista de [lon, lat]

    // 3. Filtra paradas: Só aceita paradas que estão perto da "linha azul" da rota
    // Isso remove paradas do sentido oposto automaticamente
    final List<StopInfo> filteredStops = [];
    const double threshold = 0.0005; // Aprox. 150 metros de tolerância

    for (var stop in stopsWithLine) {
      final closest = _findClosestPointInRoute(routePoints, stop.lat, stop.lon);

      // Se a parada estiver muito longe da linha desta rota específica,
      // ela provavelmente é do sentido oposto ou de outra variante.
      if (closest.distance < threshold) {
        filteredStops.add(stop);
      }
    }

    return filteredStops;
  }

  StopInfo? getNextStop(
    double userLat,
    double userLon,
    List<StopInfo> orderedStops,
    List<List<double>> routeCoordinates,
  ) {
    if (orderedStops.isEmpty || routeCoordinates.isEmpty) return null;

    // 1. Descobrimos em que ponto da LineString o usuário está agora
    final userPos = _findClosestPointInRoute(
      routeCoordinates,
      userLat,
      userLon,
    );

    // 2. Procuramos a primeira parada cujo 'routeIndex' seja maior que o do usuário
    for (var stop in orderedStops) {
      final stopPos = _findClosestPointInRoute(
        routeCoordinates,
        stop.lat,
        stop.lon,
      );

      // Se o índice da parada na rota é maior que o índice atual do usuário,
      // significa que o usuário ainda não passou por ela.
      if (stopPos.index > userPos.index) {
        return stop;
      }
    }

    return null; // Viagem concluída ou última parada
  }
}
