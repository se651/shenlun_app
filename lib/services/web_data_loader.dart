/// Web 数据加载 — sqflite 不可用时的降级方案
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class WebDataLoader {
  static WebDataLoader? _instance;
  factory WebDataLoader() => _instance ??= WebDataLoader._();
  WebDataLoader._();

  final Map<String, List<Map<String, dynamic>>> _cache = {};

  Future<List<Map<String, dynamic>>> loadLeaderBoard() => _load('assets/leader_board.json');
  Future<List<Map<String, dynamic>>> loadCommentaryContent() => _load('assets/commentary_content.json');
  Future<List<Map<String, dynamic>>> loadCommentaryDb() => _load('assets/commentary_db.json');
  Future<List<Map<String, dynamic>>> loadGovDocs() async {
    final docs = await _load('assets/gov_docs.json');
    // Add sequential ID for compatibility
    for (int i = 0; i < docs.length; i++) {
      docs[i]['id'] = i + 1;
    }
    return docs;
  }

  Future<List<Map<String, dynamic>>> _load(String path) async {
    if (_cache.containsKey(path)) return _cache[path]!;
    try {
      final jsonStr = await rootBundle.loadString(path);
      final data = json.decode(jsonStr) as List<dynamic>;
      _cache[path] = data.cast<Map<String, dynamic>>();
      return _cache[path]!;
    } catch (_) {
      return [];
    }
  }

  void clear() => _cache.clear();
}
