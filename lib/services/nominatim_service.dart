import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NominatimService {
  
  // Função de limpeza OTIMIZADA para corrigir nomes invertidos da API
  static String _cleanStreetName(String rawName) {
    // 1. Remove o prefixo de número do itinerário (Ex: "07-")
    final regexPrefix = RegExp(r'^\d{1,2}-');
    String cleanedName = rawName.replaceAll(regexPrefix, '').trim();

    // 2. Remove o sufixo de bairro/contexto (Ex: "(Parque São José)")
    final regexSuffix = RegExp(r'\s*\([^)]+\)$');
    cleanedName = cleanedName.replaceAll(regexSuffix, '').trim();
    
    // 3. Verifica a vírgula para inversão e RECONSTRÓI o nome
    if (cleanedName.contains(',')) {
      final parts = cleanedName.split(',').map((p) => p.trim()).toList();
      
      if (parts.length >= 2) {
        // parts[0] = "Avenida Castro"
        // parts[1] = "Cônego de"

        // a. Isola o Tipo de Via (Rua, Avenida, etc.)
        final wordsPart0 = parts[0].split(' ');
        final streetType = wordsPart0.first; // "Avenida"

        // b. Isola o restante do nome que foi mal colocado (Ex: "Castro")
        final baseNamePart = wordsPart0.sublist(1).join(' '); // "Castro"

        // c. RECONSTRÓI na ordem correta: Tipo + Qualificador + Nome Base
        // Ex: "Avenida" + "Cônego de" + "Castro"
        return '$streetType ${parts[1]} $baseNamePart'.trim();
      }
    }
    
    // Para nomes normais ou POIs (Terminal Parangaba)
    return cleanedName; 
  }

  static Future<LatLng?> getCoordinates(String rawStreetName, {String city = 'Fortaleza'}) async {
    // 1. LIMPA E CORRIGE O NOME ANTES DA BUSCA
    final street = _cleanStreetName(rawStreetName);

    // TENTATIVA 1: Busca combinada (mais precisa)
    // Ex: "Avenida Cônego de Castro, Fortaleza, Brasil"
    final querySpecific = '$street, $city, Brasil';
    var coords = await _performSearch(querySpecific);

    if (coords != null) {
      return coords;
    }
    
    // TENTATIVA 2 (FALLBACK): Busca sem a cidade (genérica)
    // Ex: "Avenida Cônego de Castro"
    var coordsFallback = await _performSearch(street);

    return coordsFallback;
  }
  
  // Função auxiliar para realizar a requisição HTTP
  static Future<LatLng?> _performSearch(String query) async {
    // Garante que a query é codificada para a URL
    final encodedQuery = Uri.encodeComponent(query);
    
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=1');
    
    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'MyBusApp/1.0 (seu-email-aqui@exemplo.com)' // Mantenha seu User-Agent real
      });
      
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final firstResult = data.first;
          final lat = double.tryParse(firstResult['lat'].toString());
          final lon = double.tryParse(firstResult['lon'].toString());
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (e) {
      print('Erro na busca Nominatim para "$query": $e');
    }
    return null;
  }
}