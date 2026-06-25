/// Web 端缓存实现 — localStorage
import 'dart:convert';
import 'dart:html' as html;

const _key = 'news_cache';

Future<String> readNewsCache() async {
  return html.window.localStorage[_key] ?? '';
}

Future<void> writeNewsCache(String json) async {
  html.window.localStorage[_key] = json;
}

/// 读取并清理超过 15 天的旧新闻
Future<String> readAndCleanNewsCache() async {
  final raw = html.window.localStorage[_key] ?? '';
  if (raw.isEmpty) return '';
  try {
    final items = List<Map<String, dynamic>>.from(json.decode(raw) as List);
    final now = DateTime.now();
    final fresh = items.where((item) {
      try {
        final d = DateTime.parse(item['publishDate'] ?? '');
        return now.difference(d).inDays <= 15;
      } catch (_) { return false; }
    }).toList();
    if (fresh.length != items.length) {
      html.window.localStorage[_key] = json.encode(fresh);
    }
    return json.encode(fresh);
  } catch (_) {}
  return raw;
}
