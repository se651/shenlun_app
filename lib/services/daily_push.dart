import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';

/// 每日推送服务 — 从 CCTV 首页抓取今日新闻标题生成摘要
class DailyPushService {
  static const _cacheKey = 'daily_push_cache';

  /// 从 CCTV 首页抓取今日新闻标题
  static Future<List<String>> _fetchCCTVHeadlines() async {
    try {
      final resp = await http.get(
        Uri.parse('https://news.cctv.com/'),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];

      final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
      // Extract: <a href="...2026/MM/DD/...">title</a>
      final today = DateTime.now();
      final todayStr = '${today.year}/${today.month.toString().padLeft(2,'0')}/${today.day.toString().padLeft(2,'0')}';

      final titles = <String>[];
      final linkRe = RegExp(r'href="([^"]*?/(\d{4}/\d{2}/\d{2})/[^"]+?)"[^>]*>\s*([^<]{10,80})\s*</a>');
      for (final m in linkRe.allMatches(html)) {
        final url = m.group(1) ?? '';
        final date = m.group(2) ?? '';
        final title = m.group(3)?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
        if (title.length < 10 || title.length > 80) continue;
        if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) continue;
        titles.add(title);
        if (titles.length >= 15) break;
      }
      return titles;
    } catch (_) {
      return [];
    }
  }

  /// 生成/获取今日推送
  static Future<DailyPush> getDailyPush(String? apiKey) async {
    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final displayDate = '${today.month}月${today.day}日';

    // 读缓存
    final db = DatabaseHelper();
    final cachedStr = await db.getSetting(_cacheKey);
    if (cachedStr.isNotEmpty) {
      try {
        final cached = DailyPush.fromJson(jsonDecode(cachedStr));
        if (cached.date == dateKey) return cached;
      } catch (_) {}
    }

    // 抓取今日央视新闻标题
    final headlines = await _fetchCCTVHeadlines();
    String content;
    if (headlines.isNotEmpty) {
      content = headlines.map((h) => '• $h').join('\n');
    } else {
      content = '今日暂无新闻推送，请稍后再试。';
    }

    // AI 生成摘要
    String theme = '今日新闻';
    // 无 AI 时每个标题一行
    String summary = headlines.isNotEmpty ? headlines.take(6).map((h) => '• $h').join('\n') : content;
    Color bgColor = const Color(0xFF1A1A2E);
    String quote = _randomQuote();

    if (apiKey != null && apiKey.isNotEmpty && headlines.length >= 3) {
      try {
        final response = await http.post(
          Uri.parse('https://api.deepseek.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'deepseek-chat',
            'messages': [
              {'role': 'system', 'content': '你是央视新闻编辑。根据以下今日新闻标题，写一段150字以内的新闻摘要，像新闻联播口播一样流畅自然，突出3-4个最重要的新闻点。每一条新闻单独一行，用"• "开头。再选一个主题色（#E94560红/#4A90D9蓝/#2ECC71绿/#F5A623橙/#A29BFE紫）。输出JSON：{"summary":"摘要","color":"#RRGGBB"}'},
              {'role': 'user', 'content': content.length > 2000 ? content.substring(0, 2000) : content},
            ],
            'temperature': 0.5,
            'max_tokens': 400,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final ai = data['choices']?[0]?['message']?['content'] as String? ?? '';
          final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(ai);
          if (jsonMatch != null) {
            final parsed = jsonDecode(jsonMatch.group(0)!);
            summary = (parsed['summary'] ?? summary).replaceAll('；', '；\n• ');
            bgColor = _parseColor(parsed['color']?.toString() ?? '');
          }
        }
      } catch (_) {}
    }

    final push = DailyPush(
      date: displayDate,
      theme: theme,
      summary: summary,
      bgColor: bgColor,
      quote: quote,
    );

    try { await db.setSetting(_cacheKey, jsonEncode(push.toJson())); } catch (_) {}

    return push;
  }

  static Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF1A1A2E);
    }
  }

  static String _randomQuote() {
    const quotes = [
      '学如逆水行舟，不进则退。',
      '天道酬勤，功不唐捐。',
      '日拱一卒，功不唐捐。',
      '千里之行，始于足下。',
      '星光不问赶路人，时光不负有心人。',
      '行而不辍，未来可期。',
      '心中有光，脚下有路。',
      '积微成著，久久为功。',
    ];
    return quotes[DateTime.now().day % quotes.length];
  }
}

class DailyPush {
  final String date;
  final String theme;
  final String summary;
  final Color bgColor;
  final String quote;

  DailyPush({
    required this.date,
    required this.theme,
    required this.summary,
    required this.bgColor,
    required this.quote,
  });

  Map<String, dynamic> toJson() => {
    'date': date, 'theme': theme, 'summary': summary,
    'color': '#${bgColor.value.toRadixString(16).substring(2)}',
    'quote': quote,
  };

  factory DailyPush.fromJson(Map<String, dynamic> json) => DailyPush(
    date: json['date'] ?? '',
    theme: json['theme'] ?? '',
    summary: json['summary'] ?? '',
    bgColor: Color(int.parse(json['color']?.toString().replaceFirst('#', '0xFF') ?? '0xFF1A1A2E')),
    quote: json['quote'] ?? '',
  );
}
