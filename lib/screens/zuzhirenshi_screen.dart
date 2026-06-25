import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart' show compute;
import '../services/news_cache.dart';

class ZuzhirenshiScreen extends StatefulWidget {
  const ZuzhirenshiScreen({super.key});

  @override
  State<ZuzhirenshiScreen> createState() => _ZuzhirenshiScreenState();
}

class _ZuzhirenshiScreenState extends State<ZuzhirenshiScreen>
    with SingleTickerProviderStateMixin {
  static const _base = 'https://www.zuzhirenshi.com';

  late TabController _tabController;
  bool _loading = true;
  String? _error;

  List<_ZzArticle> _partyArticles = [];
  List<_ZzArticle> _cadreArticles = [];
  List<_ZzArticle> _talentArticles = [];
  List<_ZzArticle> _socialArticles = [];

  static const _tabs = ['党建', '干部', '人才', '人社'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCached();
    _fetchAll();
  }

  String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<http.Response> _httpGet(String url) async {
    final ioClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    final client = IOClient(ioClient);
    try {
      return await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 12));
    } finally {
      client.close();
    }
  }

  Future<void> _loadCached() async {
    try {
      final json = await readNewsCache();
      if (json.isEmpty) return;
      final items = jsonDecode(json) as List;
      final zzItems = items
          .where((e) => e['source'] == 'zuzhirenshi')
          .map((e) => _ZzArticle(
                title: e['title'] ?? '',
                url: e['url'] ?? '',
                date: e['publishDate'] ?? '',
                section: e['section'] ?? '',
              ))
          .toList();
      if (zzItems.isNotEmpty && mounted) {
        setState(() {
          _partyArticles = zzItems.where((a) => a.section == '党建').toList();
          _cadreArticles = zzItems.where((a) => a.section == '干部').toList();
          _talentArticles = zzItems.where((a) => a.section == '人才').toList();
          _socialArticles = zzItems.where((a) => a.section == '人社').toList();
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAll() async {
    setState(() { _loading = true; _error = null; });

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

        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

        final html = _fixEncoding(resp);
        final extracted = await compute(_parseArticles, html);

        setState(() {
          _partyArticles = extracted.where((a) => a.section == '党建').toList();
          _cadreArticles = extracted.where((a) => a.section == '干部').toList();
          _talentArticles = extracted.where((a) => a.section == '人才').toList();
          _socialArticles = extracted.where((a) => a.section == '人社').toList();
          _loading = false;
        });
        _saveCache(extracted);
      } finally {
        client.close();
      }
    } catch (e) {
      if (_partyArticles.isEmpty && mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _saveCache(List<_ZzArticle> items) async {
    try {
      final json = await readNewsCache();
      final existing = json.isNotEmpty ? jsonDecode(json) as List : <dynamic>[];
      existing.removeWhere((e) => e['source'] == 'zuzhirenshi');
      for (final item in items) {
        existing.add({
          'title': item.title,
          'url': item.url,
          'publishDate': item.date,
          'source': 'zuzhirenshi',
          'section': item.section,
        });
      }
      await writeNewsCache(jsonEncode(existing));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中国组织人事报'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: const Color(0xFFE94560),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE94560),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_partyArticles),
                    _buildList(_cadreArticles),
                    _buildList(_talentArticles),
                    _buildList(_socialArticles),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('加载失败', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _fetchAll, child: const Text('重试')),
      ]),
    );
  }

  Widget _buildList(List<_ZzArticle> articles) {
    if (articles.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text('暂无文章\n下拉刷新试试', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _fetchAll,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新'),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: articles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final a = articles[i];
          return ListTile(
            title: Text(a.title, style: const TextStyle(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(a.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('原文链接: ${a.url}'), duration: const Duration(seconds: 2)),
              );
            },
          );
        },
      ),
    );
  }
}

/// 后台 isolate 解析 HTML
List<_ZzArticle> _parseArticles(String html) {
  final doc = parser.parse(html);
  doc.querySelectorAll('script, style, nav, header, footer, aside, iframe').forEach((e) => e.remove());

  final articles = <_ZzArticle>[];
  final links = doc.querySelectorAll('a[href]');

  for (final el in links) {
    final href = el.attributes['href'] ?? '';
    final title = el.text.trim();
    if (title.length < 8 || title.length > 200) continue;
    if (!RegExp(r'[一-鿿]').hasMatch(title)) continue;
    if (!href.contains('zuzhirenshi.com')) continue;

    final section = _detectSection(title);
    if (section == null) continue;

    final date = _extractDate(title);
    final fullUrl = href.startsWith('http') ? href : 'https://www.zuzhirenshi.com$href';

    articles.add(_ZzArticle(title: title, url: fullUrl, date: date, section: section));
    if (articles.length >= 80) break;
  }
  return articles;
}

String? _detectSection(String title) {
  if (title.contains('党建') || title.contains('党员') || title.contains('党组织') || title.contains('党委')) return '党建';
  if (title.contains('干部') || title.contains('领导') || title.contains('任免') || title.contains('选拔')) return '干部';
  if (title.contains('人才') || title.contains('引进') || title.contains('培养')) return '人才';
  if (title.contains('社保') || title.contains('医保') || title.contains('养老') || title.contains('就业') || title.contains('人社')) return '人社';
  return null;
}

String _extractDate(String text) {
  final m = RegExp(r'(\d{4})[年-](\d{1,2})[月-](\d{1,2})').firstMatch(text);
  if (m != null) {
    return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
  }
  return '';
}

class _ZzArticle {
  final String title;
  final String url;
  final String date;
  final String section;
  const _ZzArticle({required this.title, required this.url, required this.date, required this.section});
}
