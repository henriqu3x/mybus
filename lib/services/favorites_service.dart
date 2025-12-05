import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorito.dart';

class FavoritesService {
  // Singleton pattern
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  List<Favorito> _favorites = [];
  bool _initialized = false;
  bool _useSharedPreferences = false;

  static const String _fileName = 'favorites.json';
  static const String _prefsKey = 'favorites_data';

  // Initialize and load favorites from JSON
  Future<void> init() async {
    if (_initialized) return;
    await _loadFavorites();
    _initialized = true;
  }

  // Get all favorites
  Future<List<Favorito>> getFavorites() async {
    await init();
    return List.unmodifiable(_favorites);
  }

  // Get favorites by type
  Future<List<Favorito>> getFavoritesByType(FavoritoType type) async {
    await init();
    return _favorites.where((f) => f.tipo == type).toList();
  }

  // Check if an entity is favorited
  Future<bool> isFavorite(String entityId, FavoritoType type) async {
    await init();
    return _favorites.any((f) => f.entityId == entityId && f.tipo == type);
  }

  // Get favorite by entity ID and type
  Future<Favorito?> getFavoriteByEntity(String entityId, FavoritoType type) async {
    await init();
    try {
      return _favorites.firstWhere((f) => f.entityId == entityId && f.tipo == type);
    } catch (e) {
      return null;
    }
  }

  // Add a favorite
  Future<void> addFavorite(Favorito favorito) async {
    await init();
    
    // Check if already exists
    final exists = await isFavorite(favorito.entityId, favorito.tipo);
    if (exists) return;

    _favorites.add(favorito);
    await _saveFavorites();
  }

  // Remove a favorite by ID
  Future<void> removeFavorite(String favoritoId) async {
    await init();
    _favorites.removeWhere((f) => f.favoritoId == favoritoId);
    await _saveFavorites();
  }

  // Remove favorite by entity ID and type
  Future<void> removeFavoriteByEntity(String entityId, FavoritoType type) async {
    await init();
    _favorites.removeWhere((f) => f.entityId == entityId && f.tipo == type);
    await _saveFavorites();
  }

  // Toggle favorite (add if not exists, remove if exists)
  Future<bool> toggleFavorite(Favorito favorito) async {
    await init();
    
    final exists = await isFavorite(favorito.entityId, favorito.tipo);
    if (exists) {
      await removeFavoriteByEntity(favorito.entityId, favorito.tipo);
      return false; // Removed
    } else {
      await addFavorite(favorito);
      return true; // Added
    }
  }

  // Private: Get file path
  Future<String> _getFilePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/$_fileName';
    } catch (e) {
      print('Error getting application documents directory: $e');
      print('Falling back to SharedPreferences for storage');
      _useSharedPreferences = true;
      rethrow;
    }
  }

  // Private: Save favorites to JSON file
  Future<void> _saveFavorites() async {
    try {
      final jsonList = _favorites.map((f) => f.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      if (_useSharedPreferences) {
        // Use SharedPreferences as fallback
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonString);
      } else {
        try {
          final filePath = await _getFilePath();
          final file = File(filePath);
          await file.writeAsString(jsonString);
        } catch (e) {
          // If file system fails, fall back to SharedPreferences
          print('File system save failed, using SharedPreferences: $e');
          _useSharedPreferences = true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsKey, jsonString);
        }
      }
    } catch (e) {
      print('Error saving favorites: $e');
    }
  }

  // Private: Load favorites from JSON file
  Future<void> _loadFavorites() async {
    try {
      String? jsonString;
      
      // Try SharedPreferences first (faster and more reliable)
      final prefs = await SharedPreferences.getInstance();
      jsonString = prefs.getString(_prefsKey);
      
      if (jsonString != null) {
        _useSharedPreferences = true;
      } else {
        // Try file system if SharedPreferences is empty
        try {
          final filePath = await _getFilePath();
          final file = File(filePath);

          if (await file.exists()) {
            jsonString = await file.readAsString();
            // Migrate to SharedPreferences for future use
            await prefs.setString(_prefsKey, jsonString);
            _useSharedPreferences = true;
          }
        } catch (e) {
          print('File system load failed, using SharedPreferences: $e');
          _useSharedPreferences = true;
        }
      }

      if (jsonString == null || jsonString.isEmpty) {
        _favorites = [];
        return;
      }

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      _favorites = jsonList
          .map((json) => Favorito.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading favorites: $e');
      _favorites = [];
    }
  }

  // Clear all favorites (for testing/debugging)
  Future<void> clearAll() async {
    await init();
    _favorites.clear();
    await _saveFavorites();
  }
}
