/// 新闻抓取服务 v3 — 高成功率版
/// 源：人民网 RSS + 新华网 RSS（优先）+ 新华网 HTML（兜底）
/// 每 URL 自动重试 1 次，20s 总超时，HTML 解析在后台 isolate
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import '../database/db_helper.dart';

/// 新闻条目
class NewsItem {
  final String title;
  final String category;
  final String source;
  final String sourceName;
  final String url;
  String summary;
  final String publishDate;
  String content; // full article content (lazy-loaded)

  NewsItem({
    required this.title,
    required this.category,
    required this.source,
    required this.sourceName,
    required this.url,
    this.summary = '',
    this.publishDate = '',
    this.content = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title, 'category': category, 'source': source,
    'sourceName': sourceName, 'url': url, 'summary': summary,
    'publishDate': publishDate,
  };

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
    title: json['title'] ?? '',
    category: json['category'] ?? '',
    source: json['source'] ?? '',
    sourceName: json['sourceName'] ?? '',
    url: json['url'] ?? '',
    summary: json['summary'] ?? json['title'] ?? '',
    publishDate: json['publishDate'] ?? '',
  );
}

/// Top-level parser for compute() isolate — avoids blocking the UI thread
List<NewsItem> _parseXinhuaHtml(String html) {
  final doc = parser.parse(html);
  doc.querySelectorAll('script, style, nav, header, footer, aside, iframe').forEach((e) => e.remove());

  final items = <NewsItem>[];
  final links = doc.querySelectorAll('a[href]');
  final today = DateTime.now();

  for (final el in links) {
    final href = el.attributes['href'] ?? '';
    final dateMatch = RegExp(r'/(\d{4})(\d{2})(\d{2})/').firstMatch(href) ??
                      RegExp(r'/(\d{4})-(\d{2})/(\d{2})/').firstMatch(href);
    if (dateMatch == null) continue;
    if (!href.contains('news.cn') && !href.contains('xinhuanet.com')) continue;
    if (href.contains('/video/') || href.contains('/photo/')) continue;

    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    final pubDate = '$year-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';

    final d = DateTime(year, month, day);
    if (today.difference(d).inDays > 15) continue;

    var title = el.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.length < 10 || title.length > 200) continue;
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) continue;

    final fullUrl = href.startsWith('http') ? href : 'https://www.news.cn$href';

    items.add(NewsItem(
      title: title,
      category: NewsScraper._classify(title, source: 'xinhua'),
      source: 'xinhua', sourceName: '新华网',
      url: fullUrl, summary: title, publishDate: pubDate,
    ));
    if (items.length >= 60) break;
  }
  return items;
}

class NewsScraper {
  static const _politicalKw = [
    '习近平', '总书记', '国务院', '政治局', '人大', '政协', '外交部', '国防',
    '改革', '党建', '法治', '反腐败', '政策', '立法', '行政',
    '中央', '省委', '市委', '干部', '巡视', '纪委', '监察',
    '外交', '主权', '领土', '军队', '安全', '治理',
    '委员长', '总理', '部长', '党代会', '全会', '两会', '讲话', '指示',
    '中国特色社会主义', '新时代', '十四五', '十五五', '规划纲要',
  ];

  static const _livelihoodKw = [
    '教育', '医疗', '养老', '住房', '就业', '收入', '消费',
    '环境', '污染', '社保', '扶贫', '脱贫', '医保',
    '交通', '食品', '药品', '安全', '社区', '农村', '农业',
    '农民工', '残疾人', '低保', '救助', '慈善', '志愿者',
    '疫苗', '医院', '学校', '幼儿园', '保障房', '公积金',
    '菜篮子', '物价', '房价', '高温', '暴雨', '防汛', '天气',
    '考试', '高考', '中考', '招生', '假期', '春运', '旅游',
    '居民', '儿童', '老人', '患者', '小区', '公园',
  ];

  static String _classify(String title, {String source = ''}) {
    final t = title;
    for (final kw in _politicalKw) {
      if (t.contains(kw)) return '政治';
    }
    for (final kw in _livelihoodKw) {
      if (t.contains(kw)) return '民生';
    }
    return '综合';
  }

  static int _daysAgo(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return 9999;
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      return DateTime.now().difference(d).inDays;
    } catch (_) {
      return 9999;
    }
  }

  static String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  static double _titleSimilarity(String a, String b) {
    if (a.length < 3 || b.length < 3) return 0;
    final minLen = a.length < b.length ? a.length : b.length;
    int same = 0;
    for (int i = 0; i < minLen; i++) {
      if (a[i] == b[i]) same++;
    }
    return same / (a.length > b.length ? a.length : b.length);
  }

  // ═══════════════════════════════════════════
  // URL 重试包装：首次失败后等 1s 再试一次
  // ═══════════════════════════════════════════
  Future<http.Response?> _fetchWithRetry(Uri uri, {int retries = 1, int timeoutSec = 15}) async {
    for (int i = 0; i <= retries; i++) {
      try {
        final resp = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
        }).timeout(Duration(seconds: timeoutSec));
        if (resp.statusCode == 200) return resp;
      } catch (_) {}
      if (i < retries) await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  // ═══════════════════════════════════════════
  // 人民网 RSS（4 路径 + 重试）
  // ═══════════════════════════════════════════
  Future<List<NewsItem>> _scrapePeopleRss() async {
    final urls = [
      'https://www.people.com.cn/rss/politics.xml',
      'http://www.people.com.cn/rss/politics.xml',
      'http://politics.people.com.cn/rss/politics.xml',
      'http://politics.people.com.cn/rss/GB/1024/index.xml',
    ];
    for (final url in urls) {
      final resp = await _fetchWithRetry(Uri.parse(url));
      if (resp == null) continue;

      final body = _fixEncoding(resp);
      final items = <NewsItem>[];
      final itemRe = RegExp(r'<item>(.*?)</item>', dotAll: true);
      for (final m in itemRe.allMatches(body)) {
        final xml = m.group(1)!;
        final tm = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>', dotAll: true).firstMatch(xml);
        final lm = RegExp(r'<link>(.*?)</link>').firstMatch(xml);
        final dm = RegExp(r'<pubDate>(.*?)</pubDate>').firstMatch(xml);
        if (tm == null || lm == null) continue;

        var title = tm.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (title.length < 8 || title.length > 200) continue;

        final link = lm.group(1)!.trim();
        String? pubDate;
        if (dm != null) pubDate = dm.group(1)!.trim();

        items.add(NewsItem(
          title: title,
          category: _classify(title, source: 'people'),
          source: 'people', sourceName: '人民网',
          url: link, summary: title, publishDate: pubDate ?? '',
        ));
        if (items.length >= 80) break;
      }
      // Dedup
      final seen = <String>{};
      items.removeWhere((item) {
        final key = item.title.trim() + '|' + item.url.hashCode.toString();
        if (seen.contains(key)) return true;
        seen.add(key);
        return false;
      });
      if (items.isNotEmpty) return items;
    }
    return [];
  }

  // ═══════════════════════════════════════════
  // 新华网 RSS（优先，轻量可靠）
  // ═══════════════════════════════════════════
  Future<List<NewsItem>> _scrapeXinhuaRss() async {
    final urls = [
      'http://www.news.cn/politics/xhll.xml',
      'http://www.xinhuanet.com/politics/xhll.xml',
      'http://www.news.cn/rss/politics.xml',
    ];
    for (final url in urls) {
      final resp = await _fetchWithRetry(Uri.parse(url), timeoutSec: 12);
      if (resp == null) continue;

      final body = _fixEncoding(resp);
      if (!body.contains('<item>') && !body.contains('<entry>')) continue;

      final items = <NewsItem>[];
      final itemRe = RegExp(r'<(?:item|entry)>(.*?)</(?:item|entry)>', dotAll: true);
      for (final m in itemRe.allMatches(body)) {
        final xml = m.group(1)!;
        final tm = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>', dotAll: true).firstMatch(xml)
            ?? RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(xml);
        final lm = RegExp(r'<link>(.*?)</link>').firstMatch(xml)
            ?? RegExp(r'<link\s+href="(.*?)"').firstMatch(xml);
        final dm = RegExp(r'<pubDate>(.*?)</pubDate>').firstMatch(xml)
            ?? RegExp(r'<published>(.*?)</published>').firstMatch(xml);
        if (tm == null) continue;

        var title = tm.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (title.length < 8 || title.length > 200) continue;

        var link = lm?.group(1)?.trim() ?? '';
        var pubDate = dm?.group(1)?.trim() ?? '';

        items.add(NewsItem(
          title: title,
          category: _classify(title, source: 'xinhua'),
          source: 'xinhua', sourceName: '新华网',
          url: link, summary: title, publishDate: pubDate,
        ));
        if (items.length >= 60) break;
      }
      if (items.isNotEmpty) return items;
    }
    return [];
  }

  // ═══════════════════════════════════════════
  // 新华网 HTML 抓取（RSS 不可用时兜底）
  // ═══════════════════════════════════════════
  Future<List<NewsItem>> _scrapeXinhuaHtml() async {
    for (final url in [
      'https://www.xinhuanet.com/politics/',
      'http://www.xinhuanet.com/politics/',
      'https://www.news.cn/politics/',
    ]) {
      final resp = await _fetchWithRetry(Uri.parse(url), timeoutSec: 12);
      if (resp == null) continue;

      final html = _fixEncoding(resp);
      if (html.length > 500000) continue; // skip huge pages

      // Parse HTML in a background isolate to avoid UI jank
      final items = await compute(_parseXinhuaHtml, html);
      if (items.isNotEmpty) return items;
    }
    return [];
  }

  // ═══════════════════════════════════════════
  // 主抓取方法（三源并发：人民网RSS + 新华网RSS + 新华网HTML兜底）
  // ═══════════════════════════════════════════
  Future<List<NewsItem>> fetchAll() async {
    List<List<NewsItem>> results;
    try {
      results = await Future.wait([
        _scrapePeopleRss(),
        _scrapeXinhuaRss(),
        _scrapeXinhuaHtml(),
      ]).timeout(const Duration(seconds: 20));
    } catch (_) {
      // Timeout or error: return empty, caller will show cached data
      return [];
    }

    final all = <NewsItem>[];
    for (final list in results) {
      all.addAll(list);
    }

    // Filter: last 15 days only
    final filtered = all.where((item) {
      return _daysAgo(item.publishDate) <= 15;
    }).toList();

    // Dedup by full title
    final seenTitles = <String>{};
    final deduped = <NewsItem>[];
    for (final item in filtered) {
      final key = item.title.trim();
      if (seenTitles.contains(key)) continue;
      seenTitles.add(key);
      deduped.add(item);
    }

    // Sort by date desc
    deduped.sort((a, b) => b.publishDate.compareTo(a.publishDate));
    return deduped;
  }

  /// AI 批量为新闻生成摘要
  static Future<void> generateAISummaries(List<NewsItem> items) async {
    final db = DatabaseHelper();
    final apiKey = await db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) return;
    for (final item in items) {
      if (item.content.isNotEmpty && item.content.length > 20) continue;
      try {
        final prompt = '用50字以内摘要以下新闻核心内容，只输出摘要：${item.title}';
        final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
          headers: {'Content-Type':'application/json','Authorization':'Bearer $apiKey'},
          body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'user','content':prompt}],'temperature':0.3,'max_tokens':100}),
        ).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          item.content = (jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String?) ?? '';
          item.summary = item.content;
        }
      } catch (_) {}
    }
  }

  /// 解析缓存的 JSON 字符串为 NewsItem 列表
  /// 抓取半月谈评论
  Future<List<NewsItem>> fetchBanyuetan({int page = 1}) async {
    final items = <NewsItem>[];
    try {
      final url = page == 1
          ? 'http://www.banyuetan.org/byt/banyuetanpinglun/index.html'
          : 'http://www.banyuetan.org/byt/banyuetanpinglun/index_$page.html';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return items;
      final html = _fixEncoding(resp);

      // Structure: <li><h3><a href="...">TITLE</a></h3><p>SUMMARY</p><span class="tag3">DATE</span>
      final articleRe = RegExp(
        r'<a[^>]*href="([^"]*banyuetan[^"]*)"[^>]*>\s*(.{8,200}?)\s*</a>\s*</h3>\s*<p>\s*([\s\S]{20,300}?)\s*</p>\s*<span[^>]*>(\d{4}-\d{2}-\d{2})',
        multiLine: true,
      );

      for (final m in articleRe.allMatches(html)) {
        final href = m.group(1) ?? '';
        var title = (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
        var summary = (m.group(3) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final pubDate = m.group(4) ?? '';

        title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
        summary = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (title.length < 8 || title.length > 150) continue;
        if (summary.isEmpty) summary = title;

        items.add(NewsItem(
          title: title,
          category: '时政',
          source: 'banyuetan_pl',
          sourceName: '半月谈评论',
          url: href.startsWith('http') ? href : 'http://www.banyuetan.org$href',
          summary: summary,
          publishDate: pubDate,
        ));
      }

      // Dedup by title
      final seen = <String>{};
      items.removeWhere((item) {
        if (seen.contains(item.title)) return true;
        seen.add(item.title);
        return false;
      });
    } catch (_) {}
    return items;
  }

  static List<NewsItem> parseCache(String jsonStr) {
    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 清理超过 15 天的缓存项
  static List<NewsItem> cleanCache(List<NewsItem> items) {
    return items.where((item) => _daysAgo(item.publishDate) <= 15).toList();
  }

  // ═══════════════════════════════════════════
  // 兼容旧接口
  // ═══════════════════════════════════════════

  /// 获取文章正文（保留段落结构）
  Future<String> fetchArticleContent(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return '';

      final htmlText = _fixEncoding(resp);
      final doc = parser.parse(htmlText);

      // Remove junk
      doc.querySelectorAll(
        'script, style, nav, header, footer, aside, iframe, noscript, '
        '.nav, .header, .footer, .sidebar, .menu, .comment, .share, .recommend, '
        '.related, .ad, .banner, .copyright, .breadcrumb, .pagination'
      ).forEach((e) => e.remove());

      // Try known article selectors
      final articleSels = [
        '#rm_txt_zw', '.rm_txt', '.box_con', '.show_text', '.text_con', '.art_con',  // 人民网
        '#detailContent', '#articleEdit', '.detail-content', '.article-content',       // 新华网
        '.content_txt', '.cnt_bd', '#text_area', '.article-text',                      // 央视网
        '.highlight', '.article-con', '.text-con',                                     // 求是网
        '.article', '.content', '.main-content', '#article-content', '.post-content',
        '.post-body', '.entry-content', '.news-content', '[class*=\"article\"]',
      ];

      // Find the best content container
      String? bestText;
      for (final sel in articleSels) {
        final el = doc.querySelector(sel);
        if (el == null) continue;

        // Extract <p> children to preserve paragraph structure
        final paragraphs = el.querySelectorAll('p');
        if (paragraphs.isNotEmpty) {
          final parts = <String>[];
          for (final p in paragraphs) {
            final t = p.text.trim();
            if (t.isNotEmpty && t.length > 5) parts.add(t);
          }
          if (parts.length >= 2) {
            bestText = parts.join('\n\n');
            break;
          }
        }

        // Fallback: use container text
        final t = el.text.trim();
        if (t.length >= 200) {
          bestText = t;
          break;
        }
      }

      // Fallback: all <p> tags in body
      if (bestText == null || bestText.length < 100) {
        final allParagraphs = doc.querySelectorAll('p');
        final parts = <String>[];
        for (final p in allParagraphs) {
          final t = p.text.trim();
          if (t.length > 8) parts.add(t);
        }
        if (parts.isNotEmpty) {
          bestText = parts.join('\n\n');
        }
      }

      // Last resort: body text
      if (bestText == null || bestText.length < 100) {
        final body = doc.querySelector('body');
        if (body != null) {
          bestText = body.text.trim();
        }
      }

      if (bestText != null && bestText.isNotEmpty) {
        // Clean up excessive whitespace but preserve paragraph breaks
        bestText = bestText.replaceAll(RegExp(r'[ \t]+'), ' ');
        bestText = bestText.replaceAll(RegExp(r'\n{3,}'), '\n\n');
        return bestText.length > 8000 ? bestText.substring(0, 8000) : bestText;
      }
    } catch (_) {}
    return '';
  }

  // ═══════════════════════════════════════════
  // 新闻周刊 — 央视三个栏目
  // ═══════════════════════════════════════════
  Future<Map<String, List<NewsItem>>> fetchZhoukan() async {
    final result = <String, List<NewsItem>>{
      'tiantianxuexi': [],
      'yangshikuaiping': [],
      'rexuexi': [],
    };

    await Future.wait([
      _fetchColumn('https://search.cctv.com/search.php?qtext=%E5%A4%A9%E5%A4%A9%E5%AD%A6%E4%B9%A0&type=web', 'tiantianxuexi', result),
      _fetchColumn('https://search.cctv.com/search.php?qtext=%E5%A4%AE%E8%A7%86%E5%BF%AB%E8%AF%84&type=web', 'yangshikuaiping', result),
      _fetchColumn('https://search.cctv.com/search.php?qtext=%E7%83%AD%E8%A7%A3%E8%AF%BB&type=web', 'rexuexi', result),
    ]);

    return result;
  }

  Future<void> _fetchColumn(String url, String key, Map<String, List<NewsItem>> result) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;

      final html = _fixEncoding(resp);
      final doc = parser.parse(html);
      final items = <NewsItem>[];

      // CCTV search: grab title from <a> + date from 发布时间：
      final linkDateRe = RegExp(
        r'<a[^>]*href="([^"]*(?:cctv\.com|news\.cn)[^"]*)"[^>]*>'
        r'([\s\S]{8,1200}?)'
        r'</a>'
        r'([\s\S]{0,300}?)'
        r'发布时间：(\d{4}-\d{2}-\d{2})',
        multiLine: true,
      );

      for (final m in linkDateRe.allMatches(html)) {
        final href = m.group(1) ?? '';
        var title = (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final pubDate = m.group(4) ?? '';
        var desc = (m.group(3) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();

        title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (title.length < 8 || title.length > 300) continue;
        if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) continue;
        if (_daysAgo(pubDate) > 30) continue;
        if (title.contains('加载中') || title.contains('搜索排行榜') ||
            title == '在这里读懂更多' || title == '央视网新闻') continue;

        items.add(NewsItem(
          title: title,
          category: _classify(title, source: 'cctv'),
          source: 'cctv_$key',
          sourceName: key == 'tiantianxuexi' ? '天天学习' : key == 'yangshikuaiping' ? '央视快评' : '热解读',
          url: href.startsWith('http') ? href : 'https://$href',
          summary: desc.isNotEmpty && desc.length > 10 ? desc : title,
          publishDate: pubDate,
        ));
      }

      // Dedup
      final deduped = <NewsItem>[];
      for (final item in items) {
        bool dup = false;
        for (final existing in deduped) {
          if (_titleSimilarity(item.title, existing.title) > 0.4) {
            dup = true;
            break;
          }
        }
        if (!dup) deduped.add(item);
      }

      if (deduped.isNotEmpty) {
        result[key] = deduped;
      }
    } catch (_) {}
  }
}
