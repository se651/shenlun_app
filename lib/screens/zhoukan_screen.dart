import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/news_scraper.dart';
import '../services/news_cache.dart';
import '../database/db_helper.dart';
import '../services/journal_service.dart';
import '../services/news_cache.dart';
import 'news_screen.dart' show NewsDetailScreen;

class ZhoukanScreen extends StatefulWidget {
  const ZhoukanScreen({super.key});

  @override
  State<ZhoukanScreen> createState() => _ZhoukanScreenState();
}

class _ZhoukanScreenState extends State<ZhoukanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scraper = NewsScraper();
  bool _loading = true;
  DateTime _banyeDate = DateTime.now();

  final Map<String, List<NewsItem>> _data = {
    'banyuetan': [],
    'tiantianxuexi': [],
    'yangshikuaiping': [],
    'rexuexi': [],
  };

  static const _tabs = [
    {'key': 'banyuetan', 'label': '半月谈评论', 'color': Color(0xFF8B0000)},
    {'key': 'tiantianxuexi', 'label': '天天学习', 'color': Color(0xFFE94560)},
    {'key': 'yangshikuaiping', 'label': '央视快评', 'color': Color(0xFF4A90D9)},
    {'key': 'rexuexi', 'label': '热解读', 'color': Color(0xFFF5A623)},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 先读缓存
    try {
      final cache = await readNewsCache();
      if (cache.isNotEmpty) {
        for (final item in NewsScraper.parseCache(cache)) {
          if (item.source == 'banyuetan_pl') {
            _data['banyuetan']!.add(item);
          } else if (item.source == 'cctv_ttxx') {
            _data['tiantianxuexi']!.add(item);
          } else if (item.source == 'cctv_yskp') {
            _data['yangshikuaiping']!.add(item);
          } else if (item.source == 'cctv_rjd') {
            _data['rexuexi']!.add(item);
          }
        }
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {}

    // 实时抓取半月谈
    try {
      final byt = await _scraper.fetchBanyuetan();
      if (byt.isNotEmpty) {
        _data['banyuetan'] = byt;
        _saveBanyuetanCache();
      }
    } catch (_) {}

    // 实时抓取央视
    try {
      final fresh = await _scraper.fetchZhoukan();
      if (fresh['tiantianxuexi']!.isNotEmpty ||
          fresh['yangshikuaiping']!.isNotEmpty ||
          fresh['rexuexi']!.isNotEmpty) {
        _data['tiantianxuexi'] = fresh['tiantianxuexi']!;
        _data['yangshikuaiping'] = fresh['yangshikuaiping']!;
        _data['rexuexi'] = fresh['rexuexi']!;
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
    // AI 生成央视摘要
    final allItems = [
      ..._data['tiantianxuexi']!,
      ..._data['yangshikuaiping']!,
      ..._data['rexuexi']!,
    ];
    await NewsScraper.generateAISummaries(allItems);
    if (mounted) setState(() {});
  }

  Future<void> _saveBanyuetanCache() async {
    try {
      final raw = await readNewsCache();
      final all = raw.isNotEmpty ? jsonDecode(raw) as List : [];
      all.removeWhere((e) => e['source'] == 'banyuetan_pl');
      for (final item in _data['banyuetan']!) {
        all.add(item.toJson());
      }
      await writeNewsCache(jsonEncode(all));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新闻周刊'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF1A1A2E),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: _tabs.map((t) => Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: t['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(t['label'] as String),
                  ],
                ),
              )).toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _tabs.map((tab) {
                final key = tab['key'] as String;
                final items = _data[key] ?? [];
                final accentColor = tab['color'] as Color;
                if (key == 'banyuetan') return _buildBanyuetanTab(items);
                return items.isEmpty
                    ? _buildEmpty()
                    : _buildList(items, accentColor);
              }).toList(),
            ),
    );
  }

  Widget _buildBanyuetanTab(List<NewsItem> allItems) {
    // Filter by selected date
    final dateKey = '${_banyeDate.year}-${_banyeDate.month.toString().padLeft(2,'0')}-${_banyeDate.day.toString().padLeft(2,'0')}';
    final items = allItems.where((e) => e.publishDate == dateKey).toList();

    return Column(children: [
      // Date picker
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF8B0000).withOpacity(0.05),
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 16, color: Color(0xFF8B0000)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _banyeDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _banyeDate = picked);
            },
            child: Text(
              '$dateKey${_isToday(_banyeDate) ? ' (今天)' : ''}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8B0000)),
            ),
          ),
          const Spacer(),
          if (!_isToday(_banyeDate))
            GestureDetector(
              onTap: () => setState(() => _banyeDate = DateTime.now()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF8B0000).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Text('回到今天', style: TextStyle(fontSize: 11, color: Color(0xFF8B0000))),
              ),
            ),
        ]),
      ),
      // Article list
      Expanded(
        child: items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.article_outlined, size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                Text('$dateKey 暂无评论', style: TextStyle(color: Colors.grey.shade400)),
              ]))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return _buildBanyuetanCard(item);
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _buildBanyuetanCard(NewsItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => NewsDetailScreen(item: item, scraper: _scraper),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0000).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('评论', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF8B0000))),
              ),
              const Spacer(),
              Text(item.publishDate, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 8),
            SelectableText(item.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
            if (item.summary.isNotEmpty && item.summary != item.title) ...[
              const SizedBox(height: 6),
              SelectableText(item.summary, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5), maxLines: 3),
            ],
          ]),
        ),
      ),
    );
  }

  bool _isToday(DateTime d) => d.year == DateTime.now().year && d.month == DateTime.now().month && d.day == DateTime.now().day;

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.article_outlined, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('暂无内容', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重新加载'),
          onPressed: () {
            setState(() => _loading = true);
            _load();
          },
        ),
      ]),
    );
  }

  Future<void> _runAIAnalysis(NewsItem item) async {
    final db = DatabaseHelper();
    final apiKey = await db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置 DeepSeek API Key')));
      return;
    }
    var dialogActive = true;
    showDialog(context: context, barrierDismissible: true, builder: (_) => const Center(child: CircularProgressIndicator()))
        .whenComplete(() => dialogActive = false);
    try {
      final content = await _scraper.fetchArticleContent(item.url);
      final prompt = '你是申论备考专家。请分析以下时政新闻，提取2-3个申论考点，用50字以内总结核心要点，帮助申论备考。\n\n标题：${item.title}\n内容：${content.isNotEmpty ? content.substring(0, (content.length).clamp(0, 1500)) : item.summary}';
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $apiKey'},
        body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'system','content':'你是申论辅导专家。回复简洁，200字以内。'},{'role':'user','content':prompt}],'temperature':0.5,'max_tokens':300}),
      ).timeout(const Duration(seconds: 20));
      if (dialogActive) { Navigator.pop(context); dialogActive = false; }
      if (r.statusCode == 200) {
        final ans = jsonDecode(r.body)['choices'][0]['message']['content'] as String;
        _showAIResult(context, item.title, ans);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI分析失败')));
      }
    } catch (_) {
      if (dialogActive) { Navigator.pop(context); dialogActive = false; }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI分析失败')));
    }
  }

  void _showAIResult(BuildContext ctx, String title, String analysis) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFFA29BFE), size: 18), SizedBox(width: 6), Text('AI 分析', style: TextStyle(fontSize: 16))]),
      content: SingleChildScrollView(child: SelectableText(analysis, style: const TextStyle(fontSize: 14, height: 1.8))),
      actions: [
        TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: analysis)); Navigator.pop(ctx); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制'))); }, child: const Text('复制')),
        TextButton(onPressed: () async {
          final now = DateTime.now();
          await JournalService.add(JournalEntry(id: now.millisecondsSinceEpoch.toString(), date: '${now.year}-${now.month.toString().padLeft(2,"0")}-${now.day.toString().padLeft(2,"0")}', content: '【AI分析】$title\n\n$analysis', createdAt: now.toIso8601String()));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已加入积累本')));
        }, child: const Text('加入积累本')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    ));
  }

  Widget _buildList(List<NewsItem> items, Color accentColor) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _load();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NewsDetailScreen(
                      item: item,
                      scraper: _scraper,
                    ),
                  ));
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (item.category == '政治'
                                ? const Color(0xFFE94560)
                                : const Color(0xFF4A90D9)).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(item.category,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: item.category == '政治'
                                      ? const Color(0xFFE94560)
                                      : const Color(0xFF4A90D9))),
                        ),
                        const SizedBox(width: 8),
                        Text(item.sourceName,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        const Spacer(),
                        if (item.publishDate.isNotEmpty)
                          Text(item.publishDate.length >= 10
                                  ? item.publishDate.substring(5, 10)
                                  : item.publishDate,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                      ]),
                      const SizedBox(height: 8),
                      Text(item.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (item.content.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SelectableText(item.content,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
                            maxLines: 3,
                            ),
                      ] else if (item.summary.isNotEmpty && item.summary != item.title) ...[
                        const SizedBox(height: 6),
                        Text(item.summary,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        GestureDetector(
                          onTap: () => _runAIAnalysis(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.auto_awesome, size: 12, color: Color(0xFFA29BFE)),
                              SizedBox(width: 4),
                              Text('AI分析', style: TextStyle(fontSize: 11, color: Color(0xFFA29BFE))),
                            ]),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
