import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/news_cache.dart';
import 'article_detail_screen.dart';

/// 政论文章列表页 —— 支持 先锋文汇 / 求是网评 等多源
class ArticleListScreen extends StatefulWidget {
  final String title;
  final String sourceKey;
  final Color accentColor;

  const ArticleListScreen({
    super.key,
    required this.title,
    required this.sourceKey,
    this.accentColor = const Color(0xFFE94560),
  });

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen> {
  List<_Article> _articles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });

    // Load cache first
    try {
      final cachedJson = await readNewsCache();
      if (cachedJson.isNotEmpty) {
        final cachedItems = jsonDecode(cachedJson) as List;
        final cached = cachedItems
            .where((e) => e['source'] == widget.sourceKey)
            .map((e) => _Article(
                  title: e['title'] ?? '',
                  date: e['publishDate'] ?? '',
                  articleUrl: e['url'] ?? '',
                  isTid: e['isTid'] == true,
                ))
            .toList();
        if (cached.isNotEmpty && mounted) {
          setState(() { _articles = cached; _loading = false; });
        }
      }
    } catch (_) {}

    // Fetch fresh
    try {
      final articles = widget.sourceKey == 'xianfeng_wenhui'
          ? await _fetchXianfengWenhui()
          : await _fetchQiushi();
      if (mounted) setState(() { _articles = articles; _loading = false; });
      _saveCache(articles);
    } catch (e) {
      if (_articles.isEmpty && mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  // ═══ 先锋文汇 ═══
  Future<List<_Article>> _fetchXianfengWenhui() async {
    final resp = await http.get(
      Uri.parse('https://tougao.12371.cn/wenhui.php'),
      headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

    final html = _fixEncoding(resp);
    final articles = <_Article>[];
    final linkRe = RegExp(r'gaojian\.php\?tid=(\d+)');
    final tids = linkRe.allMatches(html).toList();
    final blocks = html.split(RegExp(r'gaojian\.php\?tid=\d+'));

    for (int i = 1; i < blocks.length && i <= tids.length; i++) {
      final tid = tids[i - 1].group(1) ?? '';
      final block = blocks[i];
      final lines = block.split('\n');
      String? title;
      String? date;

      for (final line in lines) {
        final clean = line.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (clean.isEmpty) continue;
        final dm = RegExp(r'(\d{4}-\d{1,2}-\d{1,2})').firstMatch(clean);
        if (dm != null && date == null) { date = dm.group(1); continue; }
        if (title == null && clean.length >= 10 && clean.length <= 120 &&
            RegExp(r'[\u4e00-\u9fff]').hasMatch(clean) &&
            !clean.contains('先锋文汇') && !clean.contains('共产党员网') &&
            !clean.contains('积分') && !clean.contains('javascript')) {
          title = clean;
          continue;
        }
        if (title != null) break;
      }
      if (title != null) {
        articles.add(_Article(title: title, date: date ?? '', articleUrl: tid, isTid: true));
      }
    }
    return _dedup(articles);
  }

  // ═══ 求是网评 ═══
  Future<List<_Article>> _fetchQiushi() async {
    final resp = await http.get(
      Uri.parse('https://www.qstheory.cn/qswp.htm'),
      headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

    final html = _fixEncoding(resp);
    final articles = <_Article>[];
    final year = DateTime.now().year;

    // Pattern: <li><a href="YYYYMMDD/.../c.html">title</a> ... <span>MM-DD</span></li>
    final itemRe = RegExp(
      r'<a[^>]*href="((\d{8})/[^"]+?\.html)"[^>]*>\s*([^<]{8,120})\s*</a>'
      r'[\s\S]{0,200}?'
      r'<span>(\d{2}-\d{2})</span>',
      multiLine: true,
    );
    for (final m in itemRe.allMatches(html)) {
      final href = m.group(1) ?? '';
      final title = (m.group(3) ?? '').trim();
      final mmdd = m.group(4) ?? '';
      if (title.length < 8 || title.length > 120) continue;
      final date = '$year-$mmdd';
      final fullUrl = 'https://www.qstheory.cn/$href';
      articles.add(_Article(title: title, date: date, articleUrl: fullUrl, isTid: false));
    }
    return _dedup(articles);
  }

  List<_Article> _dedup(List<_Article> list) {
    final seen = <String>{};
    final result = <_Article>[];
    for (final a in list) {
      final key = a.title.substring(0, a.title.length.clamp(0, 10));
      if (!seen.contains(key)) { seen.add(key); result.add(a); }
    }
    return result;
  }

  Future<void> _saveCache(List<_Article> articles) async {
    try {
      final existingJson = await readNewsCache();
      final existing = existingJson.isNotEmpty ? jsonDecode(existingJson) as List : [];
      existing.removeWhere((e) => e['source'] == widget.sourceKey);
      for (final a in articles) {
        existing.add({
          'title': a.title, 'source': widget.sourceKey,
          'sourceName': widget.title, 'url': a.articleUrl,
          'summary': '', 'publishDate': a.date,
          'category': '政治', 'isTid': a.isTid,
        });
      }
      final now = DateTime.now();
      final fresh = existing.where((e) {
        try { return now.difference(DateTime.parse(e['publishDate'] ?? '')).inDays <= 30; }
        catch (_) { return true; }
      }).toList();
      await writeNewsCache(jsonEncode(fresh));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12), Text('加载失败', style: TextStyle(color: Colors.grey.shade500)),
                  TextButton(onPressed: _fetch, child: const Text('重试')),
                ]))
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _articles.length,
                    itemBuilder: (_, i) {
                      final a = _articles[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ArticleDetailScreen(
                              title: a.title, date: a.date, articleUrl: a.articleUrl, isTid: a.isTid,
                            ),
                          )),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: widget.accentColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(widget.title, style: TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w600, color: widget.accentColor)),
                                ),
                                const Spacer(),
                                if (a.date.isNotEmpty)
                                  Text(a.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              ]),
                              const SizedBox(height: 8),
                              Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _Article {
  final String title;
  final String date;
  final String articleUrl;
  final bool isTid;
  _Article({required this.title, required this.date, required this.articleUrl, this.isTid = false});
}
