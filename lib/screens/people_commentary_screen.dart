import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/news_cache.dart';
import 'article_detail_screen.dart';

class PeopleCommentaryScreen extends StatefulWidget {
  const PeopleCommentaryScreen({super.key});
  @override
  State<PeopleCommentaryScreen> createState() => _PeopleCommentaryScreenState();
}

class _PeopleCommentaryScreenState extends State<PeopleCommentaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  final _data = <String, List<_Article>>{};

  static final _srcs = <Map<String, dynamic>>[
    {'k': 'yishiping', 't': '壹时评', 'u': 'http://opinion.people.com.cn/GB/223228/index.html', 'c': const Color(0xFFE94560)},
    {'k': 'renminshiping', 't': '人民时评', 'u': 'http://opinion.people.com.cn/GB/8213/49160/49219/index.html', 'c': const Color(0xFF4A90D9)},
    {'k': 'dangjianping', 't': '党建评', 'u': 'http://opinion.people.com.cn/GB/441030/index.html', 'c': const Color(0xFFF5A623)},
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    for (final s in _srcs) _data[s['k']!] = [];
    _fetch();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    // 读缓存
    try {
      final raw = await readNewsCache();
      if (raw.isNotEmpty) {
        final items = jsonDecode(raw) as List;
        for (final s in _srcs) {
          _data[s['k']!] = items.where((e) => e['source'] == s['k'] && !(s['k'] == 'yishiping' && (e['title']?.contains('人民锐评') == true || e['title']?.contains('人民网观点') == true))).map((e) => _Article(t: e['title'] ?? '', d: e['publishDate'] ?? '', u: e['url'] ?? '')).toList();
        }
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {}

    // 实时抓取
    try {
      for (final s in _srcs) {
        final fresh = await _scrape(s['u']!, s['k']!);
        if (fresh.isNotEmpty) _data[s['k']!] = fresh;
      }
      await _save();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<List<_Article>> _scrape(String url, String sourceKey) async {
    final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final list = <_Article>[];
    final re = RegExp(r"""<a[^>]*href=['"]([^"'\s]+?\.html?)['"][^>]*>\s*([^<]{10,120})\s*</a>[\s\S]{0,200}?(\d{4}-\d{2}-\d{2})""");
    for (final m in re.allMatches(html)) {
      final href = m.group(1) ?? '';
      var title = (m.group(2) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final date = m.group(3) ?? '';
      if (title.length < 8 || title.length > 120 || !RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) continue;
      // 过滤：排除混入的其他栏目（如壹时评页面里的人民锐评）
      if (sourceKey == 'yishiping' && (title.contains('人民锐评') || title.contains('人民网观点'))) continue;
      final full = href.startsWith('http') ? href : 'http://opinion.people.com.cn$href';
      list.add(_Article(t: title, d: date, u: full));
    }
    final seen = <String>{};
    return list.where((a) { final k = a.t.substring(0, a.t.length.clamp(0, 10)); if (seen.contains(k)) return false; seen.add(k); return true; }).toList();
  }

  Future<void> _save() async {
    try {
      final raw = await readNewsCache();
      final all = raw.isNotEmpty ? jsonDecode(raw) as List : [];
      all.removeWhere((e) => _srcs.any((s) => s['k'] == e['source']));
      for (final s in _srcs) {
        for (final a in _data[s['k']]!) {
          all.add({'title': a.t, 'source': s['k'], 'sourceName': s['t'], 'url': a.u, 'summary': '', 'publishDate': a.d, 'category': '政治'});
        }
      }
      await writeNewsCache(jsonEncode(all));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('人民网评'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch)],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(44), child: Container(color: const Color(0xFFCC0000), child: TabBar(
          controller: _tab, labelColor: Colors.white, unselectedLabelColor: Colors.white54, indicatorColor: Colors.white, indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: _srcs.map((s) => Tab(text: s['t'] as String)).toList(),
        ))),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(
        controller: _tab,
        children: _srcs.map((s) {
          final items = _data[s['k']] ?? [];
          return RefreshIndicator(
            onRefresh: _fetch,
            child: items.isEmpty ? ListView(children: [Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('暂无内容', style: TextStyle(color: Colors.grey.shade400))))])
            : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) {
              final a = items[i]; final c = s['c'] as Color;
              return Card(margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleDetailScreen(title: a.t, date: a.d, articleUrl: a.u, isTid: false))),
                borderRadius: BorderRadius.circular(12),
                child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(s['t'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c))),
                    const Spacer(), Text(a.d, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  ]),
                  const SizedBox(height: 8), Text(a.t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ])),
              ));
            }),
          );
        }).toList(),
      ),
    );
  }
}

class _Article { final String t, d, u; _Article({required this.t, required this.d, required this.u}); }
