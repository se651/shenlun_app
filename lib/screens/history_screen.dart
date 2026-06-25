import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../scorer/ai_scorer.dart';
import 'question_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = DatabaseHelper();
  final _scrollCtrl = ScrollController();
  List<_QuestionGroup> _groups = [];
  bool _loading = true;

  void _openQuestionDetail(_QuestionGroup group) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionDetailScreen(
      questionId: group.questionId,
      questionType: group.questionType,
    )));
  }

  Future<bool> _confirmDeleteGroup(int i) async {
    final group = _groups[i];
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除练习记录'),
        content: Text('确定删除「${group.title}」的全部 ${group.attempts.length} 次练习记录？题目仍保留在题库中。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (result == true) {
      await _db.deleteAllPracticeRecords(group.questionId);
      _groups.removeAt(i);
      setState(() {});
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await _db.database;
      if (db == null) { if (mounted) setState(() => _loading = false); return; }
      final records = await db.rawQuery('''
        SELECT pr.*, q.title, q.question_type, q.region, q.year, q.reference_answer
        FROM practice_records pr
        LEFT JOIN questions q ON pr.question_id = q.id
        WHERE pr.score IS NOT NULL AND pr.practice_mode NOT LIKE 'summary_%'
        ORDER BY pr.created_at DESC LIMIT 300
      ''');
      // 按 question_id 分组
      final map = <String, _QuestionGroup>{};
      for (final r in records) {
        final qid = r['question_id'] as String? ?? '';
        if (!map.containsKey(qid)) {
          map[qid] = _QuestionGroup(
            questionId: qid,
            title: r['title'] as String? ?? '',
            questionType: r['question_type'] as String? ?? '',
            referenceAnswer: r['reference_answer'] as String? ?? '',
          );
        }
        map[qid]!.attempts.add(r);
      }
      // 组内按时间正序（最早在前）
      for (final g in map.values) {
        g.attempts.sort((a, b) {
          final ta = a['created_at'] as String? ?? '';
          final tb = b['created_at'] as String? ?? '';
          return ta.compareTo(tb);
        });
      }
      if (mounted) setState(() { _groups = map.values.toList(); _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史习题')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('暂无练习记录', style: TextStyle(color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) => Dismissible(
                    key: Key(_groups[i].questionId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) => _confirmDeleteGroup(i),
                    child: _buildGroupCard(_groups[i]),
                  ),
                ),
    );
  }

  Widget _buildGroupCard(_QuestionGroup group) {
    final first = group.attempts.first;
    final last = group.attempts.last;
    final lastScore = last['score'] as int? ?? 0;
    final count = group.attempts.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: lastScore > 0 ? const Color(0xFF4ECDC4).withOpacity(0.1) : const Color(0xFFE94560).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$lastScore 分', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: lastScore > 0 ? const Color(0xFF4ECDC4) : const Color(0xFFE94560))),
            ),
            const SizedBox(width: 8),
            Text(group.questionType, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const Spacer(),
            Text('作答 $count 次', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 4),
          Text(group.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(last['created_at'].toString().substring(0, 16),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
        ]),
        children: [
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, height: 34, child: OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('查看题目详情', style: TextStyle(fontSize: 12)),
            onPressed: () => _openQuestionDetail(group),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)),
          )),
          const SizedBox(height: 8),
          _AttemptTabs(group: group),
        ],
      ),
    );
  }
}

/// Tab 切换查看各次作答
class _AttemptTabs extends StatefulWidget {
  final _QuestionGroup group;
  const _AttemptTabs({required this.group});

  @override
  State<_AttemptTabs> createState() => _AttemptTabsState();
}

class _AttemptTabsState extends State<_AttemptTabs> {
  int _selectedIdx = 0;
  bool _comparing = false;
  int _compareA = 0;
  int _compareB = 0;
  Map<String, String>? _compareResult;

  String? _tryGet(Map<String, dynamic> map, String key) {
    try { return map[key] as String?; } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final attempts = group.attempts;
    final r = attempts[_selectedIdx];
    final answer = r['user_answer'] as String? ?? '';
    final score = r['score'] as int? ?? 0;
    final mode = r['scoring_mode'] as String? ?? 'local';
    final time = r['created_at']?.toString().substring(0, 16) ?? '';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tab 栏
      SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: List.generate(attempts.length, (i) {
            final sel = i == _selectedIdx;
            return GestureDetector(
              onTap: () => setState(() => _selectedIdx = i),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF1A1A2E) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('第${i + 1}次 ${attempts[i]['score']}分',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade600)),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: 10),
      // 分数 + 模式 + 时间
      Row(children: [
        Text('$score 分', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: mode == 'ai' ? const Color(0xFFA29BFE).withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
          child: Text(mode == 'ai' ? '🤖 AI' : '📝 本地', style: TextStyle(fontSize: 10, color: mode == 'ai' ? const Color(0xFFA29BFE) : Colors.grey.shade500)),
        ),
        const Spacer(),
        Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ]),
      const SizedBox(height: 8),
      // 答案内容
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text(answer.isEmpty ? '（无答案内容）' : answer,
            style: const TextStyle(fontSize: 13, height: 1.6)),
      ),
      // AI 参考答案 (try-catch for old DB without column)
      if (_tryGet(r, 'ai_answer')?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Row(children: [const Icon(Icons.auto_awesome, size: 13, color: Color(0xFFA29BFE)), const SizedBox(width: 4), const Text('AI 参考答案', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA29BFE)))]),
        const SizedBox(height: 4),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
          child: SelectableText(_tryGet(r, 'ai_answer')!, style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
      ],
      // AI 评析
      if (_tryGet(r, 'ai_analysis')?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Row(children: [const Icon(Icons.analytics_outlined, size: 13, color: Color(0xFF00B894)), const SizedBox(width: 4), const Text('AI 评析', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00B894)))]),
        const SizedBox(height: 4),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF00B894).withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
          child: SelectableText(_tryGet(r, 'ai_analysis')!, style: const TextStyle(fontSize: 12, height: 1.6)),
        ),
      ],
      // 对比按钮（≥2 次作答时显示）
      if (attempts.length >= 2) ...[
        const SizedBox(height: 12),
        if (_comparing)
          _buildCompareSelector(attempts)
        else if (_compareResult != null)
          _buildCompareResult()
        else
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _comparing = true),
              icon: const Icon(Icons.compare_arrows, size: 16),
              label: const Text('AI 对比分析', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFA29BFE), side: const BorderSide(color: Color(0xFFA29BFE)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
      ],
    ]);
  }

  Widget _buildCompareSelector(List<Map<String, dynamic>> attempts) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('选择两次作答进行对比', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          _compareChip('A', _compareA),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('vs', style: TextStyle(color: Colors.grey))),
          _compareChip('B', _compareB),
          const Spacer(),
          SizedBox(
            height: 30,
            child: ElevatedButton(
              onPressed: _compareA == _compareB ? null : _runCompare,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA29BFE), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('开始', style: TextStyle(fontSize: 11)),
            ),
          ),
        ]),
        TextButton(onPressed: () => setState(() => _comparing = false), child: const Text('取消', style: TextStyle(fontSize: 11))),
      ]),
    );
  }

  Widget _compareChip(String label, int idx) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (label == 'A') _compareA = (_compareA + 1) % widget.group.attempts.length;
          else _compareB = (_compareB + 1) % widget.group.attempts.length;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Text('$label: 第${idx + 1}次', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Future<void> _runCompare() async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置 DeepSeek API Key')));
      return;
    }

    setState(() => _comparing = false);

    final a1 = widget.group.attempts[_compareA]['user_answer'] as String? ?? '';
    final a2 = widget.group.attempts[_compareB]['user_answer'] as String? ?? '';
    final t1 = widget.group.attempts[_compareA]['created_at']?.toString().substring(0, 16) ?? '';
    final t2 = widget.group.attempts[_compareB]['created_at']?.toString().substring(0, 16) ?? '';

    // 显示加载状态
    setState(() => _compareResult = {'progress': 'AI 分析中…', 'issues': ''});

    final result = await AIScorer.compareAttempts(
      apiKey: apiKey,
      answer1: a1, time1: t1,
      answer2: a2, time2: t2,
      questionTitle: widget.group.title,
      questionType: widget.group.questionType,
      referenceAnswer: widget.group.referenceAnswer.isNotEmpty ? widget.group.referenceAnswer : null,
    );

    if (mounted) setState(() => _compareResult = result);
  }

  Widget _buildCompareResult() {
    final r = _compareResult!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.compare_arrows, size: 16, color: Color(0xFF4ECDC4)),
          const SizedBox(width: 6),
          const Text('AI 对比分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() { _compareResult = null; _compareA = 0; _compareB = 0; }),
            child: const Icon(Icons.close, size: 16, color: Colors.grey),
          ),
        ]),
        if ((r['progress'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r['progress']!, style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
        if ((r['issues'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
            child: Text(r['issues']!, style: const TextStyle(fontSize: 13, height: 1.6)),
          ),
        ],
      ]),
    );
  }
}

class _QuestionGroup {
  final String questionId;
  final String title;
  final String questionType;
  final String referenceAnswer;
  final List<Map<String, dynamic>> attempts = [];

  _QuestionGroup({
    required this.questionId,
    required this.title,
    required this.questionType,
    required this.referenceAnswer,
  });
}
