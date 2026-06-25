/// Web 端缓存实现 — localStorage
import 'dart:convert';
import 'dart:html' as html;

const _key = 'xjp_speech_cache';

Future<String> readXjpSpeechCache() async {
  return html.window.localStorage[_key] ?? '';
}

Future<void> writeXjpSpeechCache(String json) async {
  html.window.localStorage[_key] = json;
}

Future<String> readAndCleanXjpSpeechCache() async {
  final raw = html.window.localStorage[_key] ?? '';
  if (raw.isEmpty) return '';
  try {
    final items = List<Map<String, dynamic>>.from(json.decode(raw) as List);
    final now = DateTime.now();
    final fresh = items.where((item) {
      try {
        final d = DateTime.parse(item['date'] ?? '');
        return now.difference(d).inDays <= 180;
      } catch (_) { return false; }
    }).toList();
    if (fresh.length != items.length) {
      html.window.localStorage[_key] = json.encode(fresh);
    }
    return json.encode(fresh);
  } catch (_) {}
  return raw;
}
