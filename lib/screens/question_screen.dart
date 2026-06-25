import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'question_list_screen.dart';
import 'question_detail_screen.dart';
import 'paper_practice_screen.dart';
import 'paper_library_screen.dart';

class QuestionScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;
  const QuestionScreen({super.key, this.onNavigateToTab});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  Map<String, int> _typeStats = {};
  String _region = '全部';
  bool _paperMode = false;
  bool _xuandiaoOnly = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = DatabaseHelper();
      final stats = _paperMode
          ? (_region == '全部'
              ? await db.getPaperTypeStats()
              : await db.getPaperTypeStatsByRegion(_region))
          : (_region == '全部'
              ? await db.getQuestionTypeStats()
              : await db.getQuestionTypeStatsByRegion(_region));
      if (mounted) setState(() => _typeStats = stats);
    } catch (_) {}
  }

  void _setRegion(String r) {
    setState(() => _region = r);
    _loadStats();
  }

  int _count(String type) => _typeStats[type] ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('题库', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(_paperMode ? '按套卷浏览' : '2015-2025 申论真题 · 按题型刷题',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ])),
                // 套卷开关
                Column(children: [
                  const Text('套卷', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Switch(
                    value: _paperMode,
                    activeColor: const Color(0xFF4ECDC4),
                    onChanged: (v) => setState(() { _paperMode = v; _loadStats(); }),
                  ),
                ]),
              ]),
              const SizedBox(height: 12),
              // 搜索栏（套卷模式隐藏）
              if (!_paperMode)
                TextField(
                decoration: InputDecoration(
                  hintText: '搜索题目材料…',
                  prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
                  ),
                ),
                style: const TextStyle(fontSize: 14),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuestionListScreen(
                        questionType: '全部题型',
                        keyword: v.trim(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // 地区筛选（套卷模式：全部/国考/省考/选调生 平级）
              if (_paperMode)
                Row(children: [
                  ...['全部', '国考', '省考', '选调生'].map((r) {
                    final sel = _region == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _setRegion(r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFF1A1A2E) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? const Color(0xFF1A1A2E) : Colors.grey.shade200),
                          ),
                          child: Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                              color: sel ? Colors.white : Colors.grey.shade600)),
                        ),
                      ),
                    );
                  }),
                ])
              else
                // 分题型模式：全部/国考/省考
                Row(children: [
                  ...['全部', '国考', '省考'].map((r) {
                    final sel = _region == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _setRegion(r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFF1A1A2E) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? const Color(0xFF1A1A2E) : Colors.grey.shade200),
                          ),
                          child: Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                              color: sel ? Colors.white : Colors.grey.shade600)),
                        ),
                      ),
                    );
                  }),
                ]),
              const SizedBox(height: 8),
              Expanded(
                child: _paperMode
                    ? PaperLibraryScreen(key: ValueKey(_region), filter: _region)
                    : ListView(
                  children: [
                    _buildCard('概括归纳', '概括材料核心观点与问题本质', Icons.summarize_rounded, const Color(0xFF4ECDC4)),
                    _buildCard('综合分析', '多角度解读材料，评析与逻辑推理', Icons.psychology_rounded, const Color(0xFFA29BFE)),
                    _buildCard('提出对策', '针对问题设计可行解决方案', Icons.lightbulb_rounded, const Color(0xFFF9CA24)),
                    _buildCard('应用文写作', '公文写作、简报、讲话稿等', Icons.description_rounded, const Color(0xFF6C5CE7)),
                    _buildCard('文章论述（大作文）', '议论文写作，自拟题目论述观点', Icons.article_rounded, const Color(0xFFE94560)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String title, String desc, IconData icon, Color color) {
    // Aggregate all 应用文 sub-types under one card
    int count;
    if (title == '应用文写作') {
      count = 0;
      for (final e in _typeStats.entries) {
        if (e.key.contains('应用文')) count += e.value;
      }
    } else if (title == '文章论述（大作文）') {
      count = _count('文章论述（大作文）');
    } else {
      count = _count(title);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            if (title == '应用文写作') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionListScreen(questionType: '应用文', region: _region != '全部' ? _region : null)));
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionListScreen(questionType: title, region: _region != '全部' ? _region : null)));
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Text('$count 题', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PaperListView extends StatefulWidget {
  final bool xuandiaoOnly;
  final String region;
  const _PaperListView({required this.xuandiaoOnly, required this.region});
  @override
  State<_PaperListView> createState() => _PaperListViewState();
}

class _PaperListViewState extends State<_PaperListView> {
  List<Map<String, dynamic>> _papers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PaperListView old) {
    super.didUpdateWidget(old);
    if (old.xuandiaoOnly != widget.xuandiaoOnly || old.region != widget.region) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = DatabaseHelper();
    _papers = await db.getPaperList(
      region: widget.region == '全部' ? null : widget.region,
      examCategory: widget.xuandiaoOnly ? '选调生' : null,
    );
    if (mounted) setState(() => _loading = false);
  }

  void _startPaper(String paperId, String paperTitle) async {
    final db = DatabaseHelper();
    final questions = await db.getPaperQuestions(paperId);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PaperPracticeScreen(questions: questions, paperName: paperTitle),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_papers.isEmpty) return Center(child: Text('暂无试卷', style: TextStyle(color: Colors.grey.shade400)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _papers.length,
      itemBuilder: (_, i) {
        final p = _papers[i];
        final year = p['year'];
        final region = p['region'] ?? '';
        final subtype = (p['exam_subtype'] as String?) ?? '';
        final label = '$year $region${subtype.isNotEmpty ? ' $subtype' : ''}';
        final count = p['question_count'];
        final paperId = p['paper_id'] as String;
        final paperTitle = p['paper_title'] as String? ?? '';
        // Build compact type labels
        final rawTypes = (p['types'] as String?) ?? '';
        final typeSet = <String>{};
        for (var t in rawTypes.split(',')) {
          final trimmed = t.trim();
          if (trimmed.isNotEmpty) typeSet.add(trimmed);
        }
        final typeAbbr = <String, String>{
          '概括归纳': '概括', '综合分析': '分析', '提出对策': '对策',
          '应用文写作': '应用文', '文章论述（大作文）': '大作文',
        };
        final typeLabels = typeSet.map((t) => typeAbbr[t] ?? t).toList();
        final typeStr = typeLabels.isNotEmpty ? typeLabels.join('·') : '';
        final subtitle = '$count 题${typeStr.isNotEmpty ? '  |  $typeStr' : ''}';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('练习', style: TextStyle(fontSize: 12)),
                onPressed: () => _startPaper(paperId, paperTitle.isNotEmpty ? paperTitle : label),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
            ]),
          ),
        );
      },
    );
  }
}


