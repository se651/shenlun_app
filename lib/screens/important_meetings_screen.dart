import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../data/important_meetings.dart';
import '../data/new_concepts.dart';
import '../database/db_helper.dart';
import '../services/meeting_refresh_service.dart';
import '../services/mock_exam_generator.dart';
import '../services/mock_exam_service.dart';
import 'mock_exam_answer_screen.dart';

/// 重要会议 — 会议提要 + 聚焦重点 + 新兴概念 三栏（含联网刷新+AI分析+生成模拟题）
class ImportantMeetingsScreen extends StatefulWidget {
  const ImportantMeetingsScreen({super.key});

  @override
  State<ImportantMeetingsScreen> createState() => _ImportantMeetingsScreenState();
}

class _ImportantMeetingsScreenState extends State<ImportantMeetingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, String>> _latestArticles = [];
  bool _loadingArticles = true;
  String _aiAnalysis = '';
  bool _aiLoading = false;
  bool _generating = false;

  // 新兴概念 AI 分析
  String? _conceptAiAnalysis;
  bool _conceptAiLoading = false;
  int? _analyzingIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCached();
    _refresh();
  }

  Future<void> _loadCached() async {
    final cached = await MeetingRefreshService.loadCache();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _latestArticles.clear();
        for (final item in cached.take(20)) {
          _latestArticles.add({
            'title': item['title']?.toString() ?? '',
            'url': item['url']?.toString() ?? '',
            'date': item['date']?.toString() ?? '',
          });
        }
        _loadingArticles = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _loadingArticles = true);
    final items = await MeetingRefreshService.fetchLatest();
    if (items.isNotEmpty) {
      await MeetingRefreshService.saveCache(items);
      if (mounted) {
        setState(() {
          _latestArticles.clear();
          _latestArticles.addAll(items);
          _loadingArticles = false;
        });
        _tryAiAnalyze(items.map((e) => e['title'] ?? '').toList());
      }
    } else {
      if (mounted) setState(() => _loadingArticles = false);
    }
  }

  Future<void> _tryAiAnalyze(List<String> titles) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty || titles.length < 3) return;
    setState(() => _aiLoading = true);
    final result = await MeetingRefreshService.aiAnalyze(apiKey, titles);
    if (mounted) setState(() { _aiAnalysis = result; _aiLoading = false; });
  }

  /// 选择题型并生成模拟题
  Future<void> _showMockExamDialog(String topic, String content) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在「我的」页面设置 DeepSeek API Key')),
        );
      }
      return;
    }

    final selected = <String>{
      '概括归纳': false,
      '综合分析': false,
      '提出对策': false,
      '应用文': false,
      '大作文': false,
    };
    bool isFullSet = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.quiz, color: Color(0xFFE94560), size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            Text('选择要生成的题型（可多选）', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const Divider(height: 24),
            // 题型选择
            ...MockExamGenerator.questionTypeLabels.entries.map((e) {
              return CheckboxListTile(
                value: selected[e.key] ?? false,
                onChanged: isFullSet ? null : (v) => setDlgState(() => selected[e.key] = v ?? false),
                title: Text(e.value, style: const TextStyle(fontSize: 14)),
                activeColor: const Color(0xFFE94560),
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }),
            const Divider(),
            // 整套试卷
            CheckboxListTile(
              value: isFullSet,
              onChanged: (v) => setDlgState(() {
                isFullSet = v ?? false;
                if (isFullSet) {
                  for (final k in selected.keys) { selected[k] = true; }
                }
              }),
              title: const Text('📋 整套试卷（5题·100分·全题型覆盖）',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('概括归纳+综合分析+提出对策+应用文+大作文',
                  style: TextStyle(fontSize: 11)),
              activeColor: const Color(0xFFE94560),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('生成模拟题', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ),
          ]),
        ),
      ),
    );

    if (result != true) return;

    final types = isFullSet
        ? selected.keys.toList()
        : selected.entries.where((e) => e.value).map((e) => e.key).toList();
    if (types.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一种题型')),
      );
      return;
    }

    await _generateMockExam(topic, content, types, isFullSet);
  }

  Future<void> _generateMockExam(String topic, String content, List<String> types, bool isFullSet) async {
    setState(() => _generating = true);

    final exam = await MockExamGenerator.generate(
      topic: topic,
      content: content,
      types: types,
      isFullSet: isFullSet,
    );

    if (!mounted) return;
    setState(() => _generating = false);

    if (exam != null) {
      await MockExamService.save(exam);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MockExamAnswerScreen(exam: exam),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成失败，请检查网络和 API Key'), duration: Duration(seconds: 2)),
      );
    }
  }

  /// AI 深度剖析单个概念的申论考点
  Future<void> _analyzeConcept(int index) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在「我的」页面设置 DeepSeek API Key')),
        );
      }
      return;
    }

    final concept = newConcepts[index];
    setState(() { _analyzingIndex = index; _conceptAiLoading = true; });

    try {
      final prompt = '''你是申论辅导专家。请对以下新兴治理概念进行深度剖析，重点分析其申论考点：

概念：${concept.name}（${concept.subtitle}）
释义：${concept.meaning}
出处：${concept.source}
社会现象：${concept.socialPhenomenon}
政策链接：${concept.policyLink}
已有考点：${concept.examAngle}

请从以下角度补充深度分析（400字以内，条理清晰）：

1. 【核心命题点】这个概念最适合出什么类型的申论题？预测2-3个可能的出题角度
2. 【高分策略】作答时最容易丢分的点是什么？如何避开？
3. 【金句素材】提供3-4条可用于该主题的规范性表述或金句
4. 【拓展延伸】这个概念可以和哪些其他申论热点关联组合出题？''';

      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': '你是申论辅导专家，擅长从时政概念中深度挖掘命题角度和应试策略。回答要具体实用，不泛泛而谈。'},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 800,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200 || !mounted) {
        if (mounted) {
          setState(() { _analyzingIndex = null; _conceptAiLoading = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.statusCode == 401 ? 'API Key 无效' : 'AI 分析失败 (${response.statusCode})')),
          );
        }
        return;
      }

      final data = jsonDecode(response.body);
      final aiContent = data['choices']?[0]?['message']?['content'] as String?;
      if (mounted) {
        setState(() {
          _conceptAiAnalysis = aiContent;
          _analyzingIndex = null;
          _conceptAiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _analyzingIndex = null; _conceptAiLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is http.ClientException ? '网络连接失败' : '分析超时，请重试')),
        );
      }
    }
  }

  String _conceptContentForGen(NewConcept c) {
    return '''概念：${c.name}
释义：${c.meaning}
出处：${c.source}
社会现象：${c.socialPhenomenon}
政策链接：${c.policyLink}
考点：${c.examAngle}''';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Scaffold(
        appBar: AppBar(
          title: const Text('重要会议'),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFE94560),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: '会议提要'),
              Tab(text: '聚焦重点'),
              Tab(text: '新兴概念'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDigestTab(),
            _buildFocusTab(),
            _buildConceptsTab(),
          ],
        ),
      ),
      if (_generating)
        Container(
          color: Colors.black26,
          child: const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Color(0xFFE94560)),
                  SizedBox(height: 16),
                  Text('🤖 AI 正在生成模拟题...\n大题、材料都需要时间，请耐心等待', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  /// Tab1: 会议提要
  Widget _buildDigestTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final meeting in importantMeetingsData)
          _buildMeetingCard(meeting),
      ],
    );
  }

  Widget _buildMeetingCard(ImportantMeeting meeting) {
    final categoryLabel = meetingCategoryLabels[meeting.category] ?? meeting.category;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.event, color: Color(0xFF1A1A2E), size: 20),
        ),
        title: Text(meeting.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(categoryLabel, style: const TextStyle(fontSize: 10, color: Color(0xFFE94560))),
          ),
          const SizedBox(width: 8),
          Text(meeting.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              Text(meeting.summary, style: const TextStyle(fontSize: 13, height: 1.6)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.star, size: 14, color: Color(0xFFF9CA24)),
                    SizedBox(width: 4),
                    Text('申论要点', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB8860B))),
                  ]),
                  const SizedBox(height: 6),
                  Text(meeting.keyPoints, style: const TextStyle(fontSize: 13, height: 1.7)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Tab2: 聚焦重点
  Widget _buildFocusTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_aiAnalysis.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Text('🤖', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text('AI 会议分析', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                Text(_aiAnalysis, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (_aiLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          Row(children: [
            const Text('📰 最新会议动态', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          if (_loadingArticles)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
          if (!_loadingArticles && _latestArticles.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('暂无最新会议动态\n下拉刷新或检查网络连接', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ),
            ),
          ..._latestArticles.map((article) => _buildArticleCard(article)),
        ],
      ),
    );
  }

  Widget _buildArticleCard(Map<String, String> article) {
    final title = article['title'] ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        leading: const Icon(Icons.article_outlined, color: Color(0xFF1A1A2E)),
        title: Text(title, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(article['date'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.quiz, size: 16),
                label: const Text('生成模拟题', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE94560),
                  side: const BorderSide(color: Color(0xFFE94560)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showMockExamDialog(title, title),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab3: 新兴概念 — 释义/出处/例子/政策深度 + AI 申论考点剖析 + 生成模拟题
  Widget _buildConceptsTab() {
    return Column(children: [
      if (_conceptAiAnalysis != null)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('🤖', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('AI 深度申论分析', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            SelectableText(_conceptAiAnalysis!, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.7)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _conceptAiAnalysis = null),
                icon: const Icon(Icons.close, size: 14, color: Colors.white70),
                label: const Text('收起', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: newConcepts.length,
          itemBuilder: (ctx, i) => _buildConceptCard(i),
        ),
      ),
    ]);
  }

  Widget _buildConceptCard(int index) {
    final c = newConcepts[index];
    final isAnalyzing = _analyzingIndex == index;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE94560).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('${index + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE94560))),
          ),
        ),
        title: Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text(c.subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              _sectionLabel('📖 出处'),
              const SizedBox(height: 4),
              Text(c.source, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5)),
              const SizedBox(height: 12),
              _sectionLabel('📝 释义'),
              const SizedBox(height: 4),
              Text(c.meaning, style: const TextStyle(fontSize: 13, height: 1.7)),
              const SizedBox(height: 12),
              _sectionLabel('🔍 现象与事例'),
              const SizedBox(height: 4),
              Text(c.socialPhenomenon, style: const TextStyle(fontSize: 13, height: 1.7)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E).withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1A1A2E).withOpacity(0.08)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionLabel('🏛️ 政策深度'),
                  const SizedBox(height: 4),
                  Text(c.policyLink, style: const TextStyle(fontSize: 13, height: 1.7)),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: c.keywords.map((kw) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE94560).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(kw, style: const TextStyle(fontSize: 10, color: Color(0xFFE94560))),
                )).toList(),
              ),
              const SizedBox(height: 12),
              _sectionLabel('📋 申论考点'),
              const SizedBox(height: 4),
              Text(c.examAngle, style: const TextStyle(fontSize: 13, height: 1.7)),
              const SizedBox(height: 14),
              // 两个操作按钮
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: isAnalyzing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 14),
                    label: Text(isAnalyzing ? '分析中...' : 'AI 剖析考点', style: const TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE94560),
                      side: const BorderSide(color: Color(0xFFE94560)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: isAnalyzing ? null : () => _analyzeConcept(index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.quiz, size: 14),
                    label: const Text('生成模拟题', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4ECDC4),
                      side: const BorderSide(color: Color(0xFF4ECDC4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showMockExamDialog(c.name, _conceptContentForGen(c)),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF333333)));
  }
}
