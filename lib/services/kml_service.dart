import 'dart:math';
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
      print('Erro ao carregar KML: $e');
      rethrow;
    }
  }

  /// Busca as coordenadas para uma ou mais linhas.
  /// Retorna uma lista de listas de coordenadas [latitude, longitude].
  /// O formato de retorno é pensado para fácil injeção no JavaScript do OpenLayers.
  Future<List<List<List<double>>>> getCoordinatesForLines(
    List<String> lineNames,
  ) async {
    await loadKmlData();
    if (_document == null) return [];

    final List<List<List<double>>> allRoutesCoordinates = [];

    final placemarks = _document!.findAllElements('Placemark');

    for (var lineName in lineNames) {
      final cleanLineName = lineName.trim();

      // Extract line code and direction for flexible matching
      // Example: "371 - Parangaba/José Bastos/Centro - Ida"
      String? lineCode;
      String? direction;

      final parts = cleanLineName.split(' - ');
      if (parts.isNotEmpty) {
        lineCode = parts[0]; // "371"
        if (parts.length >= 3) {
          direction = parts.last; // "Ida" or "Volta"
        }
      }

      try {
        final placemark = placemarks.firstWhere(
          (element) {
            final nameElement = element.getElement('name');
            if (nameElement == null) return false;

            final kmlName = nameElement.innerText;

            // Try flexible matching: line code at start + direction at end
            if (lineCode != null && direction != null) {
              final startsWithCode = kmlName.startsWith(lineCode + ' - ');
              final endsWithDirection = kmlName.endsWith(' - $direction');
              if (startsWithCode && endsWithDirection) {
                return true;
              }
            }

            // Fallback to exact match
            return kmlName == cleanLineName;
          },
          orElse: () {
            throw StateError('No match');
          },
        );

        // Agrega todas as LineString presentes no Placemark (alguns KMLs
        // dividem a rota em múltiplos trechos). Antes pegávamos apenas o
        // primeiro trecho o que fazia a rota parar no ponto de controle.
        final lineStringElements = placemark.findAllElements('LineString').toList();
        if (lineStringElements.isNotEmpty) {
          final List<List<double>> routeCoords = [];
          for (var ls in lineStringElements) {
            final coordinatesText = ls.getElement('coordinates')?.innerText.trim();
            if (coordinatesText == null || coordinatesText.isEmpty) continue;

            // Separe por qualquer espaço em branco (que pode ser múltiplas quebras)
            final points = coordinatesText.split(RegExp(r'\s+'));
            for (var point in points) {
              final parts = point.split(',');
              if (parts.length >= 2) {
                final lon = double.tryParse(parts[0]);
                final lat = double.tryParse(parts[1]);
                if (lon != null && lat != null) {
                  routeCoords.add([lon, lat]);
                }
              }
            }
          }

          if (routeCoords.isNotEmpty) {
            allRoutesCoordinates.add(routeCoords);
          }
        }
      } catch (e) {
        // Ignore errors for individual lines
      }
    }

    return allRoutesCoordinates;
  }

  static const String _stopsKmlPath = 'assets/paradas_onibus.kml';
  XmlDocument? _stopsDocument;

  /// Carrega o arquivo KML de paradas e retorna uma lista de StopInfo
  Future<List<StopInfo>> loadStopsMetadata() async {
    final List<StopInfo> stops = [];

    if (_stopsDocument == null) {
      try {
        final String data = await rootBundle.loadString(_stopsKmlPath);
        _stopsDocument = XmlDocument.parse(data);
      } catch (e) {
        print('Erro ao carregar KML de paradas: $e');
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
  Future<List<StopInfo>> findStopsOnStreet(String streetName, List<String> busLines) async {
    final allStops = await loadStopsMetadata();
    final normalizedStreet = _normalizeStreetName(streetName);
    
    // Normalizar números de linhas (remover prefixos de zeros, etc)
    final normalizedLines = busLines.map((l) => l.trim()).toSet();
    
    final matchingStops = <StopInfo>[];
    
    for (var stop in allStops) {
      final normalizedStopName = _normalizeStreetName(stop.name);
      
      // Verificar se o nome da parada contém a rua
      if (normalizedStopName.contains(normalizedStreet) || normalizedStreet.contains(normalizedStopName)) {
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
        .replaceAll(RegExp(r'\b(rua|avenida|av\.|pça|praça|trav|travessa|rod|rodovia|estrada|est\.|r\.)\b'), '')
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
      final distance = sqrt((lat - targetLat) * (lat - targetLat) +
              (lon - targetLon) * (lon - targetLon));

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
}
