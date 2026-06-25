import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../database/db_helper.dart';
import '../services/news_scraper.dart';
import '../services/journal_service.dart';
import '../services/news_cache.dart';
import 'zhoukan_screen.dart';

/// 顶层函数 — 供 compute() 在后台 isolate 执行 JSON 编解码
List<dynamic> _decodeJsonList(String jsonStr) => jsonDecode(jsonStr) as List<dynamic>;
String _encodeJsonList(dynamic data) => jsonEncode(data);

/// 后台 isolate：解析缓存 JSON 并剔除超过 15 天的条目
List<NewsItem> _parseAndCleanCache(String jsonStr) {
  try {
    final items = NewsScraper.parseCache(jsonStr);
    final now = DateTime.now();
    return items.where((item) {
      try {
        final parts = item.publishDate.split('-');
        if (parts.length != 3) return false;
        final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        return now.difference(d).inDays <= 15;
      } catch (_) {
        return false;
      }
    }).toList();
  } catch (_) {
    return [];
  }
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late DateTime _selectedDate;
  String _activeFilter = '全部';
  bool _loading = false;
  String? _errorMsg;
  final _scraper = NewsScraper();

  // 缓存
  final Map<String, List<NewsItem>> _newsCache = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadCache();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchNews();
    });
  }

  Future<void> _loadCache() async {
    try {
      // 读取本地缓存文件（纯文本，无 JSON 解析，不阻塞主线程）
      String jsonStr = await readNewsCache();
      if (jsonStr.isEmpty) {
        // 首次启动：从打包的 assets 读取种子数据
        jsonStr = await rootBundle.loadString('assets/news_cache.json');
      }
      if (jsonStr.isEmpty) return;
      // 所有 JSON 解析 + 15 天清理 全部在后台 isolate
      final cached = await compute(_parseAndCleanCache, jsonStr);
      for (final item in cached) {
        _newsCache.putIfAbsent(item.publishDate, () => []).add(item);
      }
    } catch (_) {
      // 缓存不可用则忽略
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _saveCache() async {
    try {
      final now = DateTime.now();

      // Read existing cache to preserve entries from other modules
      final existingJson = await readNewsCache();
      final existing = existingJson.isNotEmpty ? await compute(_decodeJsonList, existingJson) : <dynamic>[];

      // Purge stale entries: people-source AND >15 days old
      existing.removeWhere((e) => e['source'] == 'people');
      existing.removeWhere((e) {
        try {
          final parts = (e['publishDate'] as String? ?? '').split('-');
          if (parts.length != 3) return true;
          final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          return now.difference(d).inDays > 15;
        } catch (_) {
          return true;
        }
      });

      // Add current news items
      for (final entry in _newsCache.entries) {
        for (final item in entry.value) {
          try {
            final parts = item.publishDate.split('-');
            final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            if (now.difference(d).inDays > 15) continue;
          } catch (_) { continue; }
          existing.add({
            'title': item.title, 'category': item.category,
            'source': item.source, 'sourceName': item.sourceName,
            'url': item.url, 'summary': item.summary,
            'publishDate': item.publishDate,
          });
        }
      }
      await writeNewsCache(await compute(_encodeJsonList, existing));
    } catch (_) {}
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  List<NewsItem> _getNewsForDate(DateTime date) => _newsCache[_dateKey(date)] ?? [];

  List<NewsItem> get _filteredNews {
    final items = _getNewsForDate(_selectedDate);
    if (_activeFilter == '全部') return items;
    return items.where((n) => n.category == _activeFilter).toList();
  }

  String _todayKey() => _dateKey(DateTime.now());

  Future<void> _fetchNews() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final items = await _scraper.fetchAll();
      if (items.isNotEmpty) {
        final byDate = <String, List<NewsItem>>{};
        for (final item in items) {
          final dateKey = item.publishDate.isNotEmpty ? item.publishDate : _todayKey();
          byDate.putIfAbsent(dateKey, () => []).add(item);
        }
        // 合并爬取结果到已有缓存（保留旧日期数据）
        for (final e in byDate.entries) {
          // 按标题去重合并
          final existing = _newsCache[e.key] ?? [];
          final existingTitles = existing.map((x) => x.title).toSet();
          for (final item in e.value) {
            if (!existingTitles.contains(item.title)) {
              existing.add(item);
              existingTitles.add(item.title);
            }
          }
          _newsCache[e.key] = existing;
        }
        await _saveCache();
        // 今天确实没新闻时，跳到最新有缓存的日期
        final todayKey = _todayKey();
        if (!_newsCache.containsKey(todayKey) && _newsCache.isNotEmpty) {
          final latest = _newsCache.keys.toList()..sort((a, b) => b.compareTo(a));
          try {
            final parts = latest.first.split('-');
            final latestDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            if (latestDate != _selectedDate) {
              setState(() => _selectedDate = latestDate);
            }
          } catch (_) {}
        }
      } else {
        _errorMsg = '抓取失败，下拉刷新重试';
      }
    } catch (e) {
      _errorMsg = '网络不可用，下拉刷新重试';
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isWithin30Days(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    return diff >= 0 && diff < 30;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 29)),
      lastDate: now,
      helpText: '选择日期查看时政',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A1A2E),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && _isWithin30Days(picked)) {
      final key = _dateKey(picked);
      final isToday = picked.day == DateTime.now().day &&
          picked.month == DateTime.now().month &&
          picked.year == DateTime.now().year;
      if (!isToday && !_newsCache.containsKey(key)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该日期无缓存数据，仅可查看今日新闻'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('时政新闻',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('政治 · 民生 — 申论素材积累',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  // 新闻周刊入口
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZhoukanScreen())),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_stories, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('新闻周刊', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E).withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${_selectedDate.day}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日 ${_weekdayLabel(_selectedDate.weekday)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isToday ? '今天 · 最近 30 天可查' : '最近 30 天可查',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_loading)
                      const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      GestureDetector(
                        onTap: _fetchNews,
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4ECDC4).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.refresh_rounded, color: Color(0xFF4ECDC4), size: 18),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94560).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: Color(0xFFE94560), size: 18),
                    ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildFilterChip('全部'),
                  const SizedBox(width: 8),
                  _buildFilterChip('政治'),
                  const SizedBox(width: 8),
                  _buildFilterChip('民生'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('${_filteredNews.length} 条新闻',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  if (_loading) ...[
                    const SizedBox(width: 8),
                    Text('抓取中...',
                        style: TextStyle(fontSize: 11, color: const Color(0xFF4ECDC4))),
                  ],
                  if (_errorMsg != null && !_loading) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMsg!,
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade600),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredNews.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.newspaper, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            _newsCache.containsKey(_dateKey(_selectedDate))
                                ? '当日无此类新闻'
                                : _errorMsg ?? '下拉刷新获取今日时政新闻',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredNews.length,
                      itemBuilder: (context, index) {
                        final item = _filteredNews[index];
                        final isPolitical = item.category == '政治';
                        final catColor = isPolitical ? const Color(0xFFE94560) : const Color(0xFF4A90D9);
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
                              onTap: () => _showNewsDetail(item),
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: catColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(item.category,
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: catColor)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(item.sourceName,
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                        const Spacer(),
                                        if (item.publishDate.isNotEmpty)
                                          Text(_formatPubDate(item.publishDate),
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(item.title,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                        maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final selected = _activeFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFF1A1A2E) : Colors.grey.shade200),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: selected ? Colors.white : Colors.grey.shade600,
            )),
      ),
    );
  }

  void _showNewsDetail(NewsItem item) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => NewsDetailScreen(item: item, scraper: _scraper),
    ));
  }

  String _weekdayLabel(int weekday) {
    return ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
  }

  String _formatPubDate(String date) {
    if (date.length >= 10) return date.substring(5, 10);
    return date;
  }
}

/// 新闻详情——全屏阅读页
class NewsDetailScreen extends StatefulWidget {
  final NewsItem item;
  final NewsScraper scraper;
  const NewsDetailScreen({super.key, required this.item, required this.scraper});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  String _fullContent = '';
  bool _loadingContent = false;
  String _aiAnalysis = '';
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.content.isNotEmpty) {
      _fullContent = widget.item.content;
    } else if (widget.item.url.isNotEmpty) {
      _fetchContent();
    }
  }

  Future<void> _fetchContent() async {
    setState(() => _loadingContent = true);
    final content = await widget.scraper.fetchArticleContent(widget.item.url);
    if (mounted) setState(() { _fullContent = content; _loadingContent = false; });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _cleanContent(String text) {
    final tailPatterns = [
      '责任编辑', '责编', '编辑：', '编辑:',
      '热门排行', '推荐阅读', '相关新闻', '延伸阅读',
      '猜你喜欢', '为您推荐', '版权声明', '免责声明',
      '分享到', '本文来源', '阅读原文', '查看原文', '返回首页',
    ];
    for (final kw in tailPatterns) {
      final idx = text.indexOf('\n$kw');
      if (idx > text.length * 0.4) { text = text.substring(0, idx); break; }
      final idx2 = text.indexOf(kw);
      if (idx2 > text.length * 0.6) { text = text.substring(0, idx2); break; }
    }
    text = text.replaceAll(RegExp(r'[（(](?:责编|责任编辑|作者系|作者为|作者)[：:：].*?[）)]'), '');
    final lines = text.split('\n');
    final clean = <String>[];
    for (final line in lines) {
      final s = line.trim();
      if (s.isEmpty) { clean.add(''); continue; }
      if (RegExp(r'(?:本报|新华社|光明日报|人民日报|中新网|央视网).*?电[（(（]').hasMatch(s) && s.length < 60) continue;
      if (RegExp(r'^\d{1,2}月\d{1,2}日电').hasMatch(s) && s.length < 60) continue;
      if (RegExp(r'^本报(?:讯|综合)').hasMatch(s) && s.length < 40) continue;
      if (RegExp(r'^(?:记者|通讯员|实习生|本报记者|光明日报记者|新华社记者)\s*[：:：]?').hasMatch(s) && s.length < 30) continue;
      if (RegExp(r'^(?:来源|作者|原(?:标)?题)[：:]').hasMatch(s)) continue;
      if (RegExp(r'来源[：:].*$').hasMatch(s) && s.length < 40) continue;
      if (RegExp(r'^\d{4}[-/年]\d{1,2}[-/月]\d{1,2}').hasMatch(s) && s.length < 35) continue;
      if (RegExp(r'^(?:分享|转发|收藏|点赞)').hasMatch(s)) continue;
      if (s == '扫码' || (s.startsWith('关注') && s.length < 20)) continue;
      if (RegExp(r'^(?:图为|图片|资料图片|新华社发)').hasMatch(s)) continue;
      if (RegExp(r'^【.*】$').hasMatch(s) && s.length < 20) continue;
      if (RegExp(r'^[\d\s\.\-,，、;；:：|/]+$').hasMatch(s) && s.length < 15) continue;
      if (RegExp(r'^(?:阅读原文|查看原文|返回|了解更多)').hasMatch(s) && s.length < 20) continue;
      clean.add(s);
    }
    var result = clean.join('\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    final finalLines = result.split('\n');
    final start = finalLines.indexWhere((l) => l.trim().length >= 10 && RegExp(r'[\u4e00-\u9fff]').hasMatch(l));
    final end = finalLines.lastIndexWhere((l) => l.trim().length >= 10 && RegExp(r'[\u4e00-\u9fff]').hasMatch(l));
    if (start > 0 || (end >= 0 && end < finalLines.length - 1)) {
      result = finalLines.sublist(start.clamp(0, finalLines.length), (end + 1).clamp(0, finalLines.length)).join('\n').trim();
    }
    final paragraphs = result.split('\n\n');
    final indented = paragraphs.map((p) {
      if (p.trim().isEmpty) return p;
      return p.split('\n').map((line) => '\u3000\u3000$line').join('\n');
    });
    return indented.join('\n\n').trim();
  }

  static const _highlightBlue = Color(0xFF1565C0);
  static final _hlRegex = RegExp(
    '系统思维|辩证思维|底线思维|战略思维|历史思维|法治思维|精准思维|'
    '问题导向|目标导向|结果导向|系统观念|'
    '新发展理念|新发展格局|新发展阶段|高质量发展|新质生产力|'
    '中国式现代化|供给侧结构性改革|国内大循环|国内国际双循环|共同富裕|'
    '以人民为中心|全过程人民民主|'
    '主体地位|主导作用|核心地位|基础性作用|决定性意义|战略支撑|'
    '根本保证|根本遵循|行动指南|必由之路|最大底气|最大优势|'
    '乡村振兴|区域协调发展|新型城镇化|高水平对外开放|'
    '科技自立自强|现代化产业体系|新型工业化|制造强国|质量强国|网络强国|数字中国|'
    '人才强国|教育强国|科技强国|农业强国|贸易强国|航天强国|交通强国|'
    '生态文明|美丽中国|碳达峰|碳中和|绿色低碳|'
    '绿水青山就是金山银山|人与自然和谐共生|'
    '全面从严治党|党的自我革命|两个确立|两个维护|四个意识|四个自信|'
    '八项规定|反腐败斗争|不敢腐不能腐不想腐|'
    '法治中国|法治政府|法治社会|全面依法治国|'
    '科学立法|严格执法|公正司法|全民守法|'
    '总体国家安全观|平安中国|国家安全体系和能力现代化|'
    '人类命运共同体|全球发展倡议|全球安全倡议|全球文明倡议|'
    '共建一带一路|共商共建共享|互利共赢|'
    r'突破\d+[万亿亿个项]|达到\d+[万亿亿个项]|超过\d+[万亿亿个项]|增长\d+[%％]'
  );

  List<TextSpan> _buildContentSpans(String cleaned) {
    const base = TextStyle(fontSize: 16, height: 2.0, letterSpacing: 0.5, color: Colors.black87);
    const hl = TextStyle(fontSize: 16, height: 2.0, letterSpacing: 0.5, color: _highlightBlue, fontWeight: FontWeight.w600);
    const punc = '。！？；，、\n';
    final raw = _hlRegex.allMatches(cleaned).toList();
    if (raw.isEmpty) return [TextSpan(text: cleaned, style: base)];
    final intervals = <List<int>>[];
    for (final m in raw) {
      var s = m.start, e = m.end;
      var left = s;
      while (left > 0 && !punc.contains(cleaned[left - 1])) left--;
      var right = e;
      while (right < cleaned.length && !punc.contains(cleaned[right])) right++;
      if (intervals.isNotEmpty && left <= intervals.last[1] + 1) {
        intervals.last[1] = right;
      } else {
        intervals.add([left, right]);
      }
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final iv in intervals) {
      if (iv[0] > cursor) spans.add(TextSpan(text: cleaned.substring(cursor, iv[0]), style: base));
      spans.add(TextSpan(text: cleaned.substring(iv[0], iv[1]), style: hl));
      cursor = iv[1];
    }
    if (cursor < cleaned.length) spans.add(TextSpan(text: cleaned.substring(cursor), style: base));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.sourceName), actions: [
        IconButton(
          icon: _aiLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 20),
          tooltip: 'AI 分析',
          onPressed: _aiLoading ? null : _runAIAnalysis,
        ),
        IconButton(
          icon: const Icon(Icons.bookmark_add_outlined, size: 20),
          tooltip: '加入积累本',
          onPressed: () async {
            final content = _fullContent.isNotEmpty ? _cleanContent(_fullContent) : item.summary;
            final now = DateTime.now();
            final entry = JournalEntry(
              id: now.millisecondsSinceEpoch.toString(),
              date: '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
              content: '【${item.title}】\n$content',
              tags: [item.category],
              createdAt: now.toIso8601String(),
            );
            await JournalService.add(entry);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)),
            );
          },
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.6)),
          const SizedBox(height: 20),
          if (_loadingContent)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
          if (!_loadingContent && _fullContent.isNotEmpty)
            SelectableText.rich(
              TextSpan(children: _buildContentSpans(_cleanContent(_fullContent))),
              contextMenuBuilder: (ctx, state) => _buildContextMenu(ctx, state),
            ),
          if (!_loadingContent && _fullContent.isEmpty) ...[
            if (item.summary.isNotEmpty && item.summary != item.title)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF8F9FC), borderRadius: BorderRadius.circular(12)),
                  child: SelectableText(item.summary, style: const TextStyle(fontSize: 15, height: 2.0, color: Colors.black87)),
                ),
              ),
            const SizedBox(height: 12),
            Text(item.url.isNotEmpty ? '可访问原文查看完整内容' : '暂无正文内容',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            if (item.url.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('访问原文'),
                  onPressed: () => _launchUrl(item.url),
                ),
              ),
          ],
          // AI 分析结果
          if (_aiAnalysis.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFA29BFE), Color(0xFF6C5CE7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('AI 分析', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: SelectableText(_aiAnalysis, style: const TextStyle(fontSize: 14, height: 1.8)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final entry = JournalEntry(
                        id: now.millisecondsSinceEpoch.toString(),
                        date: '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
                        content: '【AI分析】${widget.item.title}\n\n$_aiAnalysis',
                        tags: ['AI分析', widget.item.category],
                        createdAt: now.toIso8601String(),
                      );
                      await JournalService.add(entry);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AI 分析已加入积累本'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                      child: const Text('+ 加入积累本', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ]),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextMenu(BuildContext ctx, EditableTextState state) {
    return AdaptiveTextSelectionToolbar(
      anchors: state.contextMenuAnchors,
      children: [
        TextButton(
          onPressed: () => state.copySelection(SelectionChangedCause.toolbar),
          child: const Text('复制', style: TextStyle(color: Colors.black)),
        ),
        TextButton(
          onPressed: () async {
            final selected = state.textEditingValue.selection.textInside(state.textEditingValue.text);
            if (selected.isNotEmpty) {
              final now = DateTime.now();
              final entry = JournalEntry(
                id: now.millisecondsSinceEpoch.toString(),
                date: '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
                content: selected,
                tags: ['摘抄'],
                createdAt: now.toIso8601String(),
              );
              await JournalService.add(entry);
              state.hideToolbar();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)),
              );
            }
          },
          child: const Text('加入积累本', style: TextStyle(color: Color(0xFFE94560))),
        ),
      ],
    );
  }

  Future<void> _runAIAnalysis() async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「我的」设置 DeepSeek API Key')),
      );
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final content = _fullContent.isNotEmpty ? _cleanContent(_fullContent) : widget.item.summary;
      final result = await _analyzeNews(apiKey, widget.item.title, content);
      if (mounted) setState(() { _aiAnalysis = result ?? 'AI 分析失败，请重试'; _aiLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _aiAnalysis = 'AI 分析失败，请重试'; _aiLoading = false; });
    }
  }

  Future<String?> _analyzeNews(String apiKey, String title, String content) async {
    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': '你是申论考试时政分析专家。请分析以下新闻，提取3-5个最核心要点和关键政策术语，适合申论备考使用。格式：先列出核心要点（每条用"•"开头），再列出关键术语。'},
          {'role': 'user', 'content': '标题：$title\n\n正文：${content.length > 2000 ? content.substring(0, 2000) : content}'},
        ],
        'temperature': 0.3,
        'max_tokens': 600,
      }),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data['choices']?[0]?['message']?['content'] as String?;
  }


}
