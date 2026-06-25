/// 习主席讲话爬虫 — jhsjk.people.cn
/// API:  testnew/result?form=706&else=501&page=N&source=2
///       返回列表 + 全文，每页 10 条，无需逐篇抓正文
/// 增量: cpc.people.com.cn/data/xjp/{YYYYMMDD}.json（每日新文章）
import 'dart:convert';
import 'package:http/http.dart' as http;

class XjpSpeech {
  final String articleId;
  final String title;
  final String source;
  final String date; // YYYY-MM-DD
  final String url;
  final String snippet;
  String content; // 全文（API 直接返回）

  XjpSpeech({
    required this.articleId,
    required this.title,
    required this.source,
    required this.date,
    required this.url,
    this.snippet = '',
    this.content = '',
  });

  Map<String, dynamic> toJson() => {
    'articleId': articleId, 'title': title, 'source': source,
    'date': date, 'url': url, 'snippet': snippet, 'content': content,
  };

  factory XjpSpeech.fromJson(Map<String, dynamic> json) => XjpSpeech(
    articleId: json['articleId'] ?? '',
    title: json['title'] ?? '',
    source: json['source'] ?? '',
    date: json['date'] ?? '',
    url: json['url'] ?? '',
    snippet: json['snippet'] ?? '',
    content: json['content'] ?? '',
  );
}

class XjpSpeechScraper {
  static const _apiBase = 'https://jhsjk.people.cn/testnew/result';
  static const _apiParams = 'form=706&else=501&source=2';
  static const _dateJsonBase = 'http://cpc.people.com.cn/data/xjp';
  static const _ua = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36';

  // ═══════════════════════════════════════════
  // 全量抓取（testnew/result API）
  // ═══════════════════════════════════════════
  Future<List<XjpSpeech>> fetchAll({
    void Function(int current, int total)? onProgress,
  }) async {
    final allItems = <XjpSpeech>[];
    final seen = <String>{};
    int page = 1;
    int total = 0;

    while (true) {
      try {
        final result = await _fetchApiPage(page);
        if (total == 0) total = result.total;

        for (final item in result.items) {
          if (seen.add(item.articleId)) {
            allItems.add(item);
          }
        }

        onProgress?.call(allItems.length, total);

        if (result.items.length < 10) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Retry once
        await Future.delayed(const Duration(seconds: 2));
        try {
          final result = await _fetchApiPage(page);
          if (total == 0) total = result.total;
          for (final item in result.items) {
            if (seen.add(item.articleId)) allItems.add(item);
          }
          onProgress?.call(allItems.length, total);
          if (result.items.length < 10) break;
          page++;
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (_) {
          if (allItems.isEmpty) rethrow;
          break;
        }
      }
    }

    allItems.sort((a, b) => b.date.compareTo(a.date));
    return allItems;
  }

  Future<({List<XjpSpeech> items, int total})> _fetchApiPage(int page) async {
    final url = '$_apiBase?$_apiParams&page=$page';
    final resp = await http.get(Uri.parse(url), headers: {
      'User-Agent': _ua,
      'Referer': 'https://jhsjk.people.cn/',
    }).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final data = json.decode(body) as Map<String, dynamic>;

    if (data['status'] != 'success') {
      throw Exception('API status: ${data['status']}');
    }

    final total = int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    final list = data['list'] as List<dynamic>? ?? [];
    final items = <XjpSpeech>[];

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final aid = item['article_id']?.toString() ?? '';
      final title = (item['title'] as String? ?? '').trim();
      final source = (item['origin_name'] as String? ?? '').trim();
      final date = (item['input_date'] as String? ?? '').substring(0, 10);
      final content = (item['newcontent'] as String? ?? '').trim();

      // Build URL
      final url = 'http://cpc.people.com.cn/n1/${date.replaceAll('-', '/')}/c64094-$aid.html';

      items.add(XjpSpeech(
        articleId: aid,
        title: title,
        source: source,
        date: date,
        url: url,
        snippet: content.length > 200 ? content.substring(0, 200) : content,
        content: content,
      ));
    }

    return (items: items, total: total);
  }

  // ═══════════════════════════════════════════
  // 日期 JSON 增量更新
  // ═══════════════════════════════════════════
  Future<List<XjpSpeech>> fetchByDate(String dateStr) async {
    final url = '$_dateJsonBase/$dateStr.json';
    final resp = await http.get(Uri.parse(url), headers: {
      'User-Agent': _ua,
    }).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) return [];

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final list = json.decode(body) as List<dynamic>;
    final items = <XjpSpeech>[];

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final articleUrl = item['url'] as String? ?? '';
      final idMatch = RegExp(r'c\d+-(\d+)\.html').firstMatch(articleUrl);
      final articleId = idMatch?.group(1) ?? '';

      var snippet = item['summary'] as String? ?? '';
      snippet = snippet.replaceAll(RegExp(r'\s+'), ' ').trim();

      items.add(XjpSpeech(
        articleId: articleId,
        title: (item['title'] as String? ?? '').trim(),
        source: item['origin_name'] as String? ?? '',
        date: (item['input_date'] as String? ?? '').substring(0, 10),
        url: articleUrl,
        snippet: snippet.length > 500 ? snippet.substring(0, 500) : snippet,
      ));
    }

    return items;
  }

  Future<List<XjpSpeech>> fetchRecentDays({int days = 3}) async {
    final now = DateTime.now();
    final allNew = <XjpSpeech>[];

    for (int i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      final dateStr =
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      final items = await fetchByDate(dateStr);
      allNew.addAll(items);
      if (i < days - 1) await Future.delayed(const Duration(milliseconds: 300));
    }

    return allNew;
  }

  /// 合并增量数据
  static List<XjpSpeech> mergeNew(List<XjpSpeech> existing, List<XjpSpeech> newItems) {
    final existingIds = existing.map((e) => e.articleId).toSet();
    final merged = List<XjpSpeech>.from(existing);

    for (final item in newItems) {
      if (item.articleId.isNotEmpty && !existingIds.contains(item.articleId)) {
        merged.add(item);
        existingIds.add(item.articleId);
      }
    }

    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }
}
