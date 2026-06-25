/// 重要会议内容刷新服务 — 联网获取最新会议资讯 + AI分析
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:html/parser.dart' as parser;
import 'package:path_provider/path_provider.dart';
import '../database/db_helper.dart';

class MeetingRefreshService {
  static const _base = 'https://www.zuzhirenshi.com';

  static String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  /// 抓取组织人事网最新会议相关文章列表
  static Future<List<Map<String, String>>> fetchLatest() async {
    final results = <Map<String, String>>[];
    try {
      final ioClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;
      final client = IOClient(ioClient);
      try {
        final resp = await client.get(
          Uri.parse(_base),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
        ).timeout(const Duration(seconds: 12));

        if (resp.statusCode != 200) return results;

        final html = _fixEncoding(resp);
        final doc = parser.parse(html);
        final links = doc.querySelectorAll('a[href]');

        for (final el in links) {
          final href = el.attributes['href'] ?? '';
          final title = el.text.trim();
          if (title.length < 10 || title.length > 200) continue;
          if (!_isMeetingRelated(title)) continue;

          final fullUrl = Uri.parse(_base).resolve(href).toString();
          results.add({
            'title': title,
            'url': fullUrl,
            'date': _extractDate(title) ?? '',
            'source': 'meeting_refresh',
          });
          if (results.length >= 20) break;
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return results;
  }

  /// 判断文章标题是否与重要会议相关
  static bool _isMeetingRelated(String title) {
    final keywords = [
      '会议', '大会', '全会', '座谈会', '研讨会',
      '中央', '部署', '讲话', '指示', '批示',
      '政治局', '国务院', '常务会议', '深化改革',
      '经济工作', '农村工作', '生态', '环保',
      '科技', '创新', '人才', '教育', '医疗',
    ];
    return keywords.any((kw) => title.contains(kw));
  }

  /// 从标题提取日期
  static String? _extractDate(String text) {
    final m = RegExp(r'(\d{4})[年-](\d{1,2})[月-](\d{1,2})').firstMatch(text);
    if (m != null) {
      return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
    }
    return null;
  }

  /// AI 分析会议标题列表
  static Future<String> aiAnalyze(String apiKey, List<String> titles) async {
    final prompt = '''你是申论备考专家。以下是最新发布的重要会议相关文章标题列表。请据此分析：

1. 【近期会议动态】从标题中识别近期有哪些重要会议或政策发布（2-3条）
2. 【申论命题方向】这些会议可能涉及哪些申论考点
3. 【备考建议】针对这些动态的备考建议

标题列表：
${titles.map((t) => '- $t').join('\n')}

请直接给出分析，300字以内，条理清晰。''';

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
            {'role': 'system', 'content': '你是申论备考专家，擅长从时政动态中提炼申论考点。'},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 600,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return '';
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 加载缓存
  static Future<List<Map<String, dynamic>>> loadCache() async {
    try {
      final db = DatabaseHelper();
      final json = await db.getSetting('meeting_refresh_cache');
      if (json.isEmpty) return [];
      final list = jsonDecode(json) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// 保存缓存
  static Future<void> saveCache(List<Map<String, String>> items) async {
    try {
      final db = DatabaseHelper();
      final all = await loadCache();
      all.removeWhere((e) => e['source'] == 'meeting_refresh');
      for (final item in items) {
        all.insert(0, item);
      }
      if (all.length > 50) all.removeRange(50, all.length);
      await db.setSetting('meeting_refresh_cache', jsonEncode(all));
    } catch (_) {}
  }
}
