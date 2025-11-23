import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/logradouro.dart';

class StorageService {
  static const String _favoritesKey = 'favorite_routes';

  Future<void> saveFavorite(
    String name,
    Logradouro origin,
    Logradouro destination,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];

    Map<String, dynamic> newFavorite = {
      'name': name,
      'origin': origin.toJson(),
      'destination': destination.toJson(),
    };

    favorites.add(jsonEncode(newFavorite));
    await prefs.setStringList(_favoritesKey, favorites);
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];

    return favorites
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> removeFavorite(int index) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];

    if (index >= 0 && index < favorites.length) {
      favorites.removeAt(index);
      await prefs.setStringList(_favoritesKey, favorites);
    }
  }
}
