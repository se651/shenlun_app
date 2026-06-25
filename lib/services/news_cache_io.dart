/// 原生端缓存实现 — dart:io File
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> _cachePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/news_cache.json';
}

Future<String> readNewsCache() async {
  try {
    final path = await _cachePath();
    final file = File(path);
    if (await file.exists()) return await file.readAsString();
  } catch (_) {}
  return '';
}

Future<void> writeNewsCache(String json) async {
  try {
    final path = await _cachePath();
    await File(path).writeAsString(json);
  } catch (_) {}
}

/// 读取并清理超过 15 天的旧新闻
Future<String> readAndCleanNewsCache() async {
  try {
    final path = await _cachePath();
    final file = File(path);
    if (!await file.exists()) return '';
    final jsonStr = await file.readAsString();
    final items = _parseItems(jsonStr);
    final now = DateTime.now();
    final fresh = items.where((item) {
      try {
        final d = DateTime.parse(item['publishDate'] ?? '');
        return now.difference(d).inDays <= 15;
      } catch (_) { return false; }
    }).toList();
    if (fresh.length != items.length) {
      await file.writeAsString(_toJson(fresh));
    }
    return _toJson(fresh);
  } catch (_) {}
  return '';
}

List<Map<String, dynamic>> _parseItems(String jsonStr) {
  try {
    final list = json.decode(jsonStr) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {}
  return [];
}

String _toJson(List<Map<String, dynamic>> items) {
  return json.encode(items);
}
