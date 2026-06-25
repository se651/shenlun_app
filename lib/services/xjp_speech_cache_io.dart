/// 原生端缓存实现 — dart:io File
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

const _fileName = 'xjp_speech_cache.json';

Future<String> _cachePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/$_fileName';
}

Future<String> readXjpSpeechCache() async {
  try {
    final path = await _cachePath();
    final file = File(path);
    if (await file.exists()) return await file.readAsString();
  } catch (_) {}
  return '';
}

Future<void> writeXjpSpeechCache(String json) async {
  try {
    final path = await _cachePath();
    await File(path).writeAsString(json);
  } catch (_) {}
}

/// 读取并清理超过 180 天的旧讲话
Future<String> readAndCleanXjpSpeechCache() async {
  try {
    final path = await _cachePath();
    final file = File(path);
    if (!await file.exists()) return '';
    final jsonStr = await file.readAsString();
    final items = _parseItems(jsonStr);
    final now = DateTime.now();
    final fresh = items.where((item) {
      try {
        final d = DateTime.parse(item['date'] ?? '');
        return now.difference(d).inDays <= 180;
      } catch (_) { return false; }
    }).toList();
    if (fresh.length != items.length) {
      await file.writeAsString(json.encode(fresh));
    }
    return json.encode(fresh);
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
