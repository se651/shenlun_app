import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/news_cache.dart';
import 'article_detail_screen.dart';

/// 《红旗文稿》 — 年→期→文章
class HqwgMagazineScreen extends StatefulWidget {
  const HqwgMagazineScreen({super.key});
  @override
  State<HqwgMagazineScreen> createState() => _HqwgMagazineScreenState();
}

class _HqwgMagazineScreenState extends State<HqwgMagazineScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  final _issues = <int, List<_Issue>>{};
  static const _years = [2026, 2025, 2024, 2023, 2022, 2021, 2020];

  static const _yearUrls = {
    2026: 'https://www.qstheory.cn/20260113/11ddf212afec465699ae06eed4fcdc3f/c.html',
    2025: 'https://www.qstheory.cn/20250113/c8b766e961a44312a3ea2e17c9464330/c.html',
    2024: 'http://www.qstheory.cn/dukan/hqwg/2024-01/16/c_1130060821.htm',
    2023: 'http://www.qstheory.cn/dukan/hqwg/2023-01/12/c_1129278546.htm',
    2022: 'http://www.qstheory.cn/dukan/hqwg/2022-01/11/c_1128251581.htm',
    2021: 'http://www.qstheory.cn/dukan/hqwg/2021-01/11/c_1126969436.htm',
    2020: 'http://www.qstheory.cn/dukan/hqwg/2020-01/11/c_1125447121.htm',
  };

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _years.length, vsync: this);
    for (final y in _years) _issues[y] = [];
    _fetch();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    // Read cache
    try {
      final raw = await readNewsCache();
      if (raw.isNotEmpty) {
        final items = jsonDecode(raw) as List;
        for (final y in _years) {
          _issues[y] = items.where((e) => e['source'] == 'hqwg_$y').map((e) => _Issue(
            title: e['title'] ?? '', url: e['url'] ?? '', date: e['publishDate'] ?? '',
          )).toList();
        }
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {}

    // Fetch fresh
    for (final y in _years) {
      try {
        final fresh = await _scrapeYear(y);
        if (fresh.isNotEmpty) _issues[y] = fresh;
      } catch (_) {}
    }
    _saveCache();
    if (mounted) setState(() => _loading = false);
  }

  Future<List<_Issue>> _scrapeYear(int year) async {
    final url = _yearUrls[year]!;
    final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);

    // Find all plain text issue numbers: 《红旗文稿》2026年第1期
    final plainNums = <String>{};
    for (final m in RegExp(r'《红旗文稿》\s*' + year.toString() + r'年第(\d+)期(?:\s*</strong>)?').allMatches(html)) {
      plainNums.add(m.group(1)!);
    }

    // Find all linked issues with href
    final linkMap = <String, String>{};
    final linkRe = RegExp(r'<a[^>]*href="([^"]+?)"[^>]*>(?:<strong>)?\s*《红旗文稿》\s*' + year.toString() + r'年第(\d+)期');
    for (final m in linkRe.allMatches(html)) {
      final href = m.group(1) ?? '';
      final num = m.group(2) ?? '';
      var full = href;
      if (full.startsWith('//')) full = 'https:$full';
      if (!full.startsWith('http')) full = 'https://www.qstheory.cn$full';
      linkMap[num] = full;
    }

    // Build issue list: prefer links, fall back to plain text
    final list = <_Issue>[];
    for (final num in plainNums) {
      final link = linkMap[num];
      list.add(_Issue(
        title: '${year}年第$num期',
        url: link ?? url,
        date: '$year-$num',
      ));
    }
    list.sort((a, b) => int.parse(b.title.split('第')[1].replaceAll('期', ''))
        .compareTo(int.parse(a.title.split('第')[1].replaceAll('期', ''))));
    return list;
  }

  Future<void> _saveCache() async {
    try {
      final raw = await readNewsCache();
      final all = raw.isNotEmpty ? jsonDecode(raw) as List : [];
      all.removeWhere((e) => (e['source'] as String?)?.startsWith('hqwg_') == true);
      for (final y in _years) {
        for (final i in _issues[y]!) {
          all.add({'title': i.title, 'source': 'hqwg_$y', 'url': i.url, 'publishDate': i.date, 'category': '政治'});
        }
      }
      await writeNewsCache(jsonEncode(all));
    } catch (_) {}
  }

  Future<List<_Article>> _fetchArticles(String issueUrl) async {
    final resp = await http.get(Uri.parse(issueUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final articles = <_Article>[];
    final re = RegExp(r'<a[^>]*href="([^"]+?/c\.html)"[^>]*>\s*(.{4,120}?)\s*</a>');
    for (final m in re.allMatches(html)) {
      var title = (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&emsp;', '').replaceAll('&ensp;', '').trim();
      if (title.length < 4 || title.length > 120) continue;
      if (title == '【网站声明】' || title == '理论资源导航') continue;
      final full = m.group(1)!.startsWith('http') ? m.group(1)! : 'https://www.qstheory.cn${m.group(1)}';
      articles.add(_Article(title: title, url: full));
    }
    return articles.where((a) => a.title.length >= 4).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('红旗文稿'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch)],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(36), child: Container(
          color: const Color(0xFFCC0000),
          child: TabBar(
            controller: _tab, isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white, indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: _years.map((y) => Tab(text: '$y')).toList(),
          ),
        )),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(
        controller: _tab,
        children: _years.map((y) {
          final issues = _issues[y] ?? [];
          return RefreshIndicator(onRefresh: _fetch, child: ListView.builder(
            padding: const EdgeInsets.all(16), itemCount: issues.length,
            itemBuilder: (_, i) => _buildIssueCard(issues[i]),
          ));
        }).toList(),
      ),
    );
  }

  Widget _buildIssueCard(_Issue issue) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openIssue(issue),
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFCC0000).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.menu_book, color: Color(0xFFCC0000), size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Text(issue.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ])),
      ),
    );
  }

  void _openIssue(_Issue issue) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _IssueDetailScreen(issue: issue, fetcher: _fetchArticles)));
  }
}

class _IssueDetailScreen extends StatefulWidget {
  final _Issue issue;
  final Future<List<_Article>> Function(String) fetcher;
  const _IssueDetailScreen({required this.issue, required this.fetcher});
  @override
  State<_IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<_IssueDetailScreen> {
  List<_Article> _articles = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final a = await widget.fetcher(widget.issue.url);
    if (mounted) setState(() { _articles = a; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.issue.title)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        padding: const EdgeInsets.all(16), itemCount: _articles.length,
        itemBuilder: (_, i) {
          final a = _articles[i];
          return Card(margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleDetailScreen(title: a.title, date: widget.issue.date, articleUrl: a.url, isTid: false))),
            borderRadius: BorderRadius.circular(10),
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFCC0000), shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Text(a.title, style: const TextStyle(fontSize: 14, height: 1.4))),
            ])),
          ));
        },
      ),
    );
  }
}

class _Issue { final String title, url, date; _Issue({required this.title, required this.url, required this.date}); }
class _Article { final String title, url; _Article({required this.title, required this.url}); }
