import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/graph_utils.dart';

class GraphCacheService {
  static const String _cacheDateKey = 'transport_graph_cache_date_v2';
  static const String _cacheBuiltAtKey = 'transport_graph_cache_built_at_v2';
  static const String _cacheFileName = 'transport_graph_cache_v2.json';

  Future<bool> isCacheValidForToday() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_cacheDateKey);
    return savedDate != null && savedDate == _todayStamp();
  }

  Future<DateTime?> getCacheBuiltAt() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_cacheDateKey);
    final builtAtText = prefs.getString(_cacheBuiltAtKey);
    if (savedDate == null || savedDate != _todayStamp()) {
      return null;
    }

    if (builtAtText == null) {
      return null;
    }

    final builtAt = DateTime.tryParse(builtAtText);
    if (builtAt == null) {
      return null;
    }

    return builtAt;
  }

  Future<TransportGraph?> loadGraphIfFresh() async {
    if (!await isCacheValidForToday()) {
      await clearInvalidCache();
      return null;
    }

    final file = await _getCacheFile();
    if (!await file.exists()) {
      await clearInvalidCache();
      return null;
    }

    try {
      final content = await file.readAsString();
      final payload = jsonDecode(content);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid graph cache root payload.');
      }
      return TransportGraph.fromJson(payload);
    } catch (error) {
      debugPrint('Falha ao carregar cache do grafo: $error');
      await clearInvalidCache();
      return null;
    }
  }

  Future<void> saveGraphForToday(TransportGraph graph) async {
    final prefs = await SharedPreferences.getInstance();
    final file = await _getCacheFile();

    try {
      await file.writeAsString(jsonEncode(graph.toJson()), flush: true);
      await prefs.setString(_cacheDateKey, _todayStamp());
      await prefs.setString(_cacheBuiltAtKey, DateTime.now().toIso8601String());
    } catch (error) {
      debugPrint('Falha ao salvar cache do grafo: $error');
      rethrow;
    }
  }

  Future<void> clearInvalidCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheDateKey);
    await prefs.remove(_cacheBuiltAtKey);

    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('Falha ao limpar cache do grafo: $error');
    }
  }

  Future<File> _getCacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_cacheFileName');
  }

  String _todayStamp() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
