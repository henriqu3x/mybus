import 'dart:convert';
import 'package:http/http.dart' as http;

class NominatimService {
  static const String nominatimUrl = 'https://nominatim.openstreetmap.org/search';

  Future<Map<String, double>?> geocodeAddress(String logradouroName) async {
    // Adiciona o contexto da cidade para melhorar a precisão da geocodificação
    final query = '$logradouroName, Fortaleza, CE, Brasil';
    
    final uri = Uri.parse(
      '$nominatimUrl?q=${Uri.encodeComponent(query)}&format=json&limit=1'
    );
    
    // O cabeçalho User-Agent é obrigatório para o Nominatim
    try {
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'EtuforBusPlannerApp/1.0'} 
      );

      if (response.statusCode == 200) {
        final results = json.decode(response.body);
        
        if (results is List && results.isNotEmpty) {
          final firstResult = results[0];
          return {
            'latitude': double.tryParse(firstResult['lat'].toString()) ?? 0.0,
            'longitude': double.tryParse(firstResult['lon'].toString()) ?? 0.0,
          };
        }
      }
    } catch (e) {
      // Ignorar e retornar nulo em caso de erro de rede ou parsing
      return null;
    }
    return null;
  }
}