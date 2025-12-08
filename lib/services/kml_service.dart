import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

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
                print(
                  'DEBUG: Flexible match found: "$kmlName" matches "$cleanLineName"',
                );
                return true;
              }
            }

            // Fallback to exact match
            return kmlName == cleanLineName;
          },
          orElse: () {
            print('DEBUG: No match found for line: "$cleanLineName" in KML.');
            print(
              'DEBUG: Tried matching with code: "$lineCode" and direction: "$direction"',
            );
            throw StateError('No match');
          },
        );

        // If we get here, we found a placemark
        print('DEBUG: Found Placemark for $cleanLineName');

        final lineString = placemark.findAllElements('LineString').firstOrNull;
        if (lineString != null) {
          final coordinatesText = lineString
              .getElement('coordinates')
              ?.innerText
              .trim();
          if (coordinatesText != null) {
            final List<List<double>> routeCoords = [];
            final points = coordinatesText.split(' ');
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
            if (routeCoords.isNotEmpty) {
              allRoutesCoordinates.add(routeCoords);
              print(
                'DEBUG: Extracted ${routeCoords.length} points for $cleanLineName',
              );
            } else {
              print('DEBUG: No valid coordinates parsed for $cleanLineName');
            }
          } else {
            print('DEBUG: No coordinates text found for $cleanLineName');
          }
        } else {
          print('DEBUG: No LineString found for $cleanLineName');
        }
      } catch (e) {
        if (e is! StateError) {
          print('DEBUG: Exception finding route in KML for $lineName: $e');
        }
      }
    }

    if (allRoutesCoordinates.isEmpty) {
      print('DEBUG: allRoutesCoordinates is empty! No lines matched.');
    } else {
      print('DEBUG: Total routes found: ${allRoutesCoordinates.length}');
    }

    return allRoutesCoordinates;
  }
}
