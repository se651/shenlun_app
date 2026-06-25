import 'package:flutter/material.dart';
import '../services/summary_practice.dart';
import '../scorer/ai_scorer.dart';
import '../database/db_helper.dart';

class SummaryPracticeScreen extends StatefulWidget {
  const SummaryPracticeScreen({super.key});
  @override
  State<SummaryPracticeScreen> createState() => _SummaryPracticeScreenState();
}

class _SummaryPracticeScreenState extends State<SummaryPracticeScreen> {
  final _practice = SummaryPracticeService();
  final _db = DatabaseHelper();
  SummaryExercise? _currentExercise;
  final _completedHashes = <int>{};
  bool _loading = true;
  bool _refreshing = false;
  String _selectedLevel = 'short';

  // 每个级别独立的答题状态
  final _answers = <String, String>{};
  final _submitted = <String, bool>{};
  final _scores = <String, _SummaryScore?>{};
  final _aiAnalyses = <String, SummaryAnalysisResult?>{};
  final _aiLoading = <String, bool>{};

  final _levels = const [
    {'id': 'short', 'name': '短句概括', 'desc': '30字内浓缩', 'icon': Icons.short_text_rounded},
    {'id': 'paragraph', 'name': '段落概括', 'desc': '50字内归纳', 'icon': Icons.format_quote_rounded},
    {'id': 'full', 'name': '全文概括', 'desc': '200字内总结', 'icon': Icons.article_rounded},
    {'id': 'outline', 'name': '提纲提炼', 'desc': '只写结构', 'icon': Icons.list_alt_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  String _statusMsg = '';

  Future<void> _initAndLoad() async {
    await _practice.init();
    _statusMsg = _practice.errorMsg;
    // 加载已完成列表（从 question_id 解析 content hash）
    try {
      final db = await _db.database;
      if (db != null) {
        final rows = await db.rawQuery(
          "SELECT DISTINCT question_id FROM practice_records WHERE practice_mode LIKE 'summary_%'",
        );
        _completedHashes.clear();
        for (final r in rows) {
          final qid = r['question_id'] as String? ?? '';
          // 格式: summary_{hash}_{timestamp}
          if (qid.startsWith('summary_')) {
            final parts = qid.substring(8).split('_');
            if (parts.length >= 2) {
              final hash = int.tryParse(parts[0]) ?? 0;
              if (hash != 0) _completedHashes.add(hash);
            }
          }
        }
      }
    } catch (_) {}
    _loadExercise();
  }

  int _exerciseHash(SummaryExercise e) => e.content.hashCode;

  Future<void> _refreshArticles() async {
    setState(() => _refreshing = true);
    await _practice.refresh();
    _statusMsg = _practice.errorMsg;
    if (mounted) {
      setState(() => _refreshing = false);
      _loadExercise();
      if (_practice.errorMsg.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('素材已更新'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _loadExercise() {
    setState(() => _loading = true);
    SummaryExercise exercise;
    // 最多尝试 20 次，跳过已完成的题
    for (int attempt = 0; attempt < 20; attempt++) {
      switch (_selectedLevel) {
        case 'short': exercise = _practice.shortSentenceExercise(); break;
        case 'paragraph': exercise = _practice.paragraphExercise(); break;
        case 'full': exercise = _practice.fullArticleExercise(); break;
        case 'outline': exercise = _practice.outlineExercise(); break;
        default: exercise = _practice.shortSentenceExercise();
      }
      if (!_completedHashes.contains(_exerciseHash(exercise))) {
        setState(() { _currentExercise = exercise; _loading = false; });
        return;
      }
    }
    // 全部做完了
    setState(() { _currentExercise = null; _loading = false; });
  }

  void _switchLevel(String levelId) {
    setState(() => _selectedLevel = levelId);
    _loadExercise();
  }

  void _submitAnswer() {
    final answer = _answers[_selectedLevel] ?? '';
    if (answer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入答案')),
      );
      return;
    }

    final exercise = _currentExercise!;
    final score = _scoreSummary(answer, exercise);

    setState(() {
      _submitted[_selectedLevel] = true;
      _scores[_selectedLevel] = score;
    });

    // 保存练习记录
    final levelName = _levels.firstWhere((l) => l['id'] == _selectedLevel)['name'] as String;
    final contentHash = _exerciseHash(exercise);
    _db.savePracticeRecord({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'question_id': 'summary_${contentHash}_${exercise.id}',
      'user_answer': answer,
      'score': score.score,
      'score_breakdown': score.feedback,
      'suggestions': '',
      'scoring_mode': 'local',
      'practice_mode': 'summary_$levelName',
      'created_at': DateTime.now().toIso8601String(),
    });
    _completedHashes.add(contentHash);

    // 有 API key 时自动调 AI 分析
    _runAIAnalysis(answer, exercise);
  }

  Future<void> _runAIAnalysis(String userAnswer, SummaryExercise exercise) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      // 无 AI 时生成本地参考归纳
      final localRef = _buildLocalReference(exercise.content, exercise.level);
      if (mounted) {
        setState(() {
          _aiAnalyses[_selectedLevel] = SummaryAnalysisResult(
            referenceAnswer: localRef,
            gapAnalysis: '',
            techniqueBreakdown: '',
          );
        });
      }
      return;
    }

    setState(() => _aiLoading[_selectedLevel] = true);

    final levelName = _levels.firstWhere((l) => l['id'] == _selectedLevel)['name'] as String;
    final result = await AIScorer.analyzeSummary(
      apiKey: apiKey,
      originalText: exercise.content,
      userAnswer: userAnswer,
      levelName: levelName,
    );

    if (mounted) {
      setState(() {
        _aiAnalyses[_selectedLevel] = result;
        _aiLoading[_selectedLevel] = false;
      });
    }
  }

  _SummaryScore _scoreSummary(String userAnswer, SummaryExercise exercise) {
    final userClean = _normalize(userAnswer);
    final materialClean = _normalize(exercise.content);
    final userLen = userClean.length;

    // 空答案 / 无效答案直接 0 分
    if (userLen < 5) {
      return _SummaryScore(score: 0, feedback: '作答过短或无实质内容，请认真概括', total: 5);
    }

    // 1. 提取材料关键词（2-4字高频中文词）
    final matKeywords = _extractKeywords(materialClean);
    if (matKeywords.isEmpty) {
      return _SummaryScore(score: 3, feedback: '材料解析失败，请换一题', total: 5);
    }

    // 2. 关键词命中率
    int matched = 0;
    final missed = <String>[];
    for (final kw in matKeywords) {
      if (userClean.contains(kw)) { matched++; }
      else { missed.add(kw); }
    }
    final hitRate = matched / matKeywords.length;

    // 3. 抄材料检测（5-gram 重叠率）
    double copyRate = _copyRatio(userClean, materialClean);

    // 4. 字数评分
    int lengthScore;
    String lengthNote;
    switch (exercise.level) {
      case 'short':
        if (userLen <= 30) { lengthScore = 2; lengthNote = '字数优秀'; }
        else if (userLen <= 50) { lengthScore = 1; lengthNote = '还可以更精简'; }
        else { lengthScore = 0; lengthNote = '太长了'; }
        break;
      case 'paragraph':
        if (userLen >= 20 && userLen <= 60) { lengthScore = 2; lengthNote = '字数恰当'; }
        else if (userLen >= 10 && userLen <= 100) { lengthScore = 1; lengthNote = '字数可优化'; }
        else { lengthScore = 0; lengthNote = '字数不合理'; }
        break;
      case 'full':
        if (userLen >= 60 && userLen <= 200) { lengthScore = 2; lengthNote = '字数恰当'; }
        else if (userLen >= 30 && userLen <= 300) { lengthScore = 1; lengthNote = '字数可优化'; }
        else { lengthScore = 0; lengthNote = '字数不合理'; }
        break;
      case 'outline':
        final hasNums = RegExp(r'[一二三四五12345][、.．]').hasMatch(userAnswer);
        if (hasNums && userLen >= 20) { lengthScore = 2; lengthNote = '结构清晰'; }
        else if (hasNums) { lengthScore = 1; lengthNote = '结构可更完整'; }
        else { lengthScore = 0; lengthNote = '需用序号列出要点'; }
        break;
      default:
        lengthScore = 1; lengthNote = '';
    }

    // 5. 综合评分（降低阈值，避免误判好答案）
    int score;
    String feedback;
    
    if (copyRate > 0.65) {
      score = 1;
      feedback = '⚠️ 抄材料过多，请用自己的话概括';
    } else if (hitRate >= 0.55 && lengthScore >= 1) {
      score = 5;
      feedback = '优秀！要点覆盖全面，概括精准';
    } else if (hitRate >= 0.40 && lengthScore >= 1) {
      score = 4;
      feedback = '良好，大部分要点命中';
    } else if (hitRate >= 0.25) {
      score = 3;
      feedback = '一般，部分要点遗漏';
    } else if (hitRate >= 0.10) {
      score = 2;
      feedback = '需加强，要点覆盖不足';
    } else {
      score = 1;
      feedback = '较弱，请重新阅读材料后作答';
    }

    // 修正：字数合适但命中低 → 说明用了自己话，加分
    if (lengthScore == 2 && hitRate < 0.40 && hitRate >= 0.20) { score = (score + 1).clamp(1, 5); feedback += '（用自己的话概括，虽然关键词命中不多）'; }
    // 修正：抄材料比例高但不到严重程度 → 轻微扣分
    if (copyRate > 0.40 && score > 2) { score -= 1; feedback += ' （注意提炼而非照搬）'; }

    final detail = '关键词：$matched/${matKeywords.length} 命中'
        '${missed.isNotEmpty ? "，遗漏：${missed.take(4).join("、")}${missed.length > 4 ? "等" : ""}" : ""}'
        '\n$lengthNote，${(copyRate*100).round()}% 内容与材料重复';

    return _SummaryScore(score: score.clamp(0, 5), feedback: feedback, total: 5);
  }

  static String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'[\s\n\r\t]+'), '')
        .replaceAll(RegExp(r'[，,。；;！!？?：:、""''【】《》（）()]'), ' ')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }

  static List<String> _extractKeywords(String text) {
    final words = <String>{};
    const stop = {'这是','一个','可以','进行','通过','对于','以及','为了','不是','没有','已经','还是','或者','但是','因为','所以','然而','目前','一定','需要','主要','其中','问题','方面','这个','他们','我们'};
    for (final m in RegExp(r'[\u4e00-\u9fff]{2,4}').allMatches(text)) {
      final w = m.group(0)!;
      if (!stop.contains(w) && w.length >= 2) words.add(w);
    }
    final sorted = words.toList()..sort((a, b) => b.length.compareTo(a.length));
    return sorted.take(15).toList();
  }

  /// 本地生成参考答案
  /// 核心思路：首句通常是主题/总领句，再提取其他句中与首句主题相关的高频词拼接
  /// 同时按各题型字数要求裁剪
  String _buildLocalReference(String material, String level) {
    int maxLen;
    switch (level) {
      case 'short': maxLen = 30; break;
      case 'paragraph': maxLen = 60; break;
      case 'full': maxLen = 200; break;
      default: maxLen = 300; break;
    }
    final sentences = material
        .replaceAll(RegExp(r'\n+'), '。')
        .split(RegExp(r'[。！？]'))
        .map((s) => s.trim())
        .where((s) => s.length >= 8)
        .toList();
    if (sentences.isEmpty) return material;
    if (sentences.length == 1) return sentences.first;

    final keywords = _extractKeywords(_normalize(material));
    if (keywords.isEmpty) return sentences.first;

    // 以首句为主题锚点，提取首句中的关键词作为"主题词"
    final firstClean = _normalize(sentences.first);
    final themeWords = keywords.where((kw) => firstClean.contains(kw)).toList();
    if (themeWords.isEmpty) {
      // 首句无关键词时，退回全段关键词
      themeWords.addAll(keywords.take(5));
    }

    // 计算每句与主题词的匹配度（而非全部关键词）
    final scored = sentences.map((s) {
      final clean = _normalize(s);
      int hits = 0;
      for (final tw in themeWords) {
        if (clean.contains(tw)) hits++;
      }
      return (sentence: s, score: hits, first: s == sentences.first);
    }).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));

    String result;
    switch (level) {
      case 'short':
        // 短句：取首句的核心部分（取前一半），不再追加其他句
        final firstHalf = sentences.first.length > 25
            ? sentences.first.substring(0, sentences.first.length ~/ 2)
            : sentences.first;
        result = _trimTrailing(firstHalf);
        break;
      case 'paragraph':
        // 段落：首句 + 得分最高的 1 句非首句
        final picked = <String>[sentences.first];
        for (final s in scored) {
          if (s.first) continue;
          picked.add(s.sentence);
          break;
        }
        result = picked.join('。');
        break;
      case 'outline':
        final items = <String>[sentences.first];
        int cnt = 1;
        for (final s in scored) {
          if (s.first) continue;
          items.add(s.sentence);
          cnt++;
          if (cnt >= 3) break;
        }
        result = items.asMap().entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
        break;
      case 'full':
      default:
        final picked = <String>[sentences.first];
        int added = 0;
        for (final s in scored) {
          if (s.first) continue;
          picked.add(s.sentence);
          added++;
          if (added >= 3) break;
        }
        result = picked.join('。');
    }

    // 字数裁剪
    if (result.length > maxLen && level != 'outline') {
      result = '${result.substring(0, maxLen)}…';
    }
    return result;
  }

  String _trimTrailing(String s) {
    // 去掉尾部不完整的半句
    final trimmed = s.replaceAll(RegExp(r'[，,、]\s*$'), '');
    return trimmed.isEmpty ? s : trimmed;
  }

  static double _copyRatio(String user, String material) {
    if (material.length < 10) return 0;
    const n = 5;
    if (user.length < n) return 0;
    final matGrams = <String>{};
    for (int i = 0; i <= material.length - n; i++) {
      matGrams.add(material.substring(i, i + n));
    }
    int copied = 0, total = 0;
    for (int i = 0; i <= user.length - n; i++) { total++; if (matGrams.contains(user.substring(i, i + n))) copied++; }
    return total > 0 ? copied / total : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('概括练习'), actions: [
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SummaryHistoryPage())),
          child: const Text('练习记录', style: TextStyle(fontSize: 13)),
        ),
      ]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('练习模式', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: _levels.map((level) {
              final selected = _selectedLevel == level['id'];
              return GestureDetector(
                onTap: () => _switchLevel(level['id'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF4ECDC4) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? const Color(0xFF4ECDC4) : Colors.grey.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(level['icon'] as IconData, size: 16, color: selected ? Colors.white : const Color(0xFF4ECDC4)),
                    const SizedBox(width: 6),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(level['name'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.black87)),
                      Text(level['desc'] as String, style: TextStyle(fontSize: 10, color: selected ? Colors.white70 : Colors.grey)),
                    ]),
                  ]),
                ),
              );
            }).toList()),
            if (_statusMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(_statusMsg, style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                  ]),
                ),
              ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (_currentExercise == null) ...[
              const Padding(padding: EdgeInsets.all(40), child: Column(children: [
                Icon(Icons.check_circle, size: 48, color: Color(0xFF4ECDC4)),
                SizedBox(height: 12),
                Text('当前模式题目已全部完成', style: TextStyle(fontSize: 15, color: Colors.grey)),
                SizedBox(height: 4),
                Text('切换其他模式或查看练习记录', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ])),
            ] else ...[
              // 材料
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(_currentExercise!.source, style: const TextStyle(fontSize: 11, color: Color(0xFFE94560)))),
                    const Spacer(),
                    GestureDetector(
                      onTap: _refreshing ? null : _refreshArticles,
                      child: _refreshing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFFE94560)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(_currentExercise!.content, style: const TextStyle(fontSize: 15, height: 1.8)),
                  if (_currentExercise!.hint != null) ...[
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF9CA24).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [
                      const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFF9CA24)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_currentExercise!.hint!, style: const TextStyle(fontSize: 13, color: Color(0xFFB8860B)))),
                    ])),
                  ],
                ]),
              ),
              const SizedBox(height: 16),

              // 答题区
              if (_submitted[_selectedLevel] != true) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    maxLines: 6,
                    onChanged: (v) => _answers[_selectedLevel] = v,
                    decoration: InputDecoration(
                      hintText: '在这里写下你的概括...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
                  onPressed: _submitAnswer,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                  child: const Text('提交评分', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                )),
              ],

              // 评分结果
              if (_submitted[_selectedLevel] == true && _scores[_selectedLevel] != null) ...[
                const SizedBox(height: 16),
                _buildScoreCard(_scores[_selectedLevel]!),
                // AI 分析
                if (_aiLoading[_selectedLevel] == true) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('AI 分析中…', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ]),
                  ),
                ],
                if (_aiAnalyses[_selectedLevel] != null) ...[
                  const SizedBox(height: 16),
                  _buildAIAnalysisCard(_aiAnalyses[_selectedLevel]!),
                ],
                // 答案对比
                if (_submitted[_selectedLevel] == true) ...[
                  const SizedBox(height: 16),
                  _buildCompareTabs(
                    _answers[_selectedLevel] ?? '',
                    _aiAnalyses[_selectedLevel]?.referenceAnswer ?? '',
                    _aiAnalyses[_selectedLevel] != null,
                  ),
                ],
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildCompareTabs(String userAnswer, String refAnswer, bool hasAI) {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          const TabBar(
            labelColor: Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFE94560),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [Tab(text: '我的答案'), Tab(text: '参考答案')],
          ),
          SizedBox(
            height: 200,
            child: TabBarView(children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(userAnswer.isEmpty ? '（未作答）' : userAnswer, style: const TextStyle(fontSize: 14, height: 1.8)),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(refAnswer, style: const TextStyle(fontSize: 14, height: 1.8)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildScoreCard(_SummaryScore s) {
    final Color color;
    final String emoji;
    if (s.score >= 5) { color = const Color(0xFF4ECDC4); emoji = '🎉'; }
    else if (s.score >= 4) { color = const Color(0xFFA29BFE); emoji = '👍'; }
    else if (s.score >= 3) { color = const Color(0xFFF9CA24); emoji = '📝'; }
    else { color = const Color(0xFFE94560); emoji = '💪'; }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.1), color.withOpacity(0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${s.score}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: color)),
          Text(' / ${s.total} 分', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        Text(s.feedback, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 36, child: OutlinedButton(
          onPressed: () {
            setState(() {
              _submitted.remove(_selectedLevel);
              _answers.remove(_selectedLevel);
              _scores.remove(_selectedLevel);
              _aiAnalyses.remove(_selectedLevel);
              _aiLoading.remove(_selectedLevel);
            });
            _loadExercise();
          },
          style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text('换一题再练', style: TextStyle(fontSize: 13)),
        )),
      ]),
    );
  }

  Widget _buildAIAnalysisCard(SummaryAnalysisResult analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 参考答案
        const Row(children: [
          Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4ECDC4)),
          SizedBox(width: 6),
          Text('AI 参考答案', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.2))),
          child: Text(analysis.referenceAnswer, style: const TextStyle(fontSize: 14, height: 1.7)),
        ),
        const SizedBox(height: 20),
        // 差距分析
        if (analysis.gapAnalysis.isNotEmpty) ...[
          const Row(children: [
            Icon(Icons.compare_arrows, size: 18, color: Color(0xFFE94560)),
            SizedBox(width: 6),
            Text('差距分析', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE94560).withOpacity(0.15))),
            child: Text(analysis.gapAnalysis, style: const TextStyle(fontSize: 13, height: 1.7)),
          ),
        ],
        const SizedBox(height: 20),
        // 归纳技巧
        if (analysis.techniqueBreakdown.isNotEmpty) ...[
          const Row(children: [
            Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFF9CA24)),
            SizedBox(width: 6),
            Text('归纳技巧', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF9CA24).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.2))),
            child: Text(analysis.techniqueBreakdown, style: const TextStyle(fontSize: 13, height: 1.7)),
          ),
        ],
      ]),
    );
  }
}

class _SummaryScore {
  final int score;
  final String feedback;
  final int total;
  _SummaryScore({required this.score, required this.feedback, required this.total});
}

/// 概括练习历史记录页
class _SummaryHistoryPage extends StatefulWidget {
  @override
  State<_SummaryHistoryPage> createState() => _SummaryHistoryPageState();
}

class _SummaryHistoryPageState extends State<_SummaryHistoryPage> with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper();
  late TabController _tabCtrl;
  List<_SummaryGroup> _groups = [];
  List<Map<String, String>> _aiExercises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final db = await _db.database;
      if (db == null) { if (mounted) setState(() => _loading = false); return; }
      final records = await db.rawQuery('''
        SELECT * FROM practice_records
        WHERE practice_mode LIKE 'summary_%'
        ORDER BY created_at DESC LIMIT 200
      ''');
      final map = <String, _SummaryGroup>{};
      for (final r in records) {
        final qid = r['question_id'] as String? ?? '';
        final mode = r['practice_mode'] as String? ?? '';
        final levelName = mode.replaceFirst('summary_', '');
        if (!map.containsKey(qid)) {
          map[qid] = _SummaryGroup(questionId: qid, levelName: levelName);
        }
        map[qid]!.attempts.add(r);
      }
      for (final g in map.values) {
        g.attempts.sort((a, b) {
          return (a['created_at'] as String? ?? '').compareTo(b['created_at'] as String? ?? '');
        });
      }
      // 加载 AI 出题缓存
      final svc = SummaryPracticeService();
      _aiExercises = await svc.aiExercises;
      if (mounted) setState(() { _groups = map.values.toList(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('概括练习记录'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFF1A1A2E),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE94560),
          tabs: const [Tab(text: '我的练习'), Tab(text: 'AI 出题')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                // Tab 1: 我的练习
                _groups.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('暂无概括练习记录', style: TextStyle(color: Colors.grey.shade400)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _groups.length,
                        itemBuilder: (_, i) => _buildItem(_groups[i]),
                      ),
                // Tab 2: AI 出题
                _aiExercises.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_awesome, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('暂无 AI 出题记录', style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(height: 4),
                        Text('接入 AI Key 后刷新即可生成', style: TextStyle(fontSize: 12, color: Colors.grey.shade300)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _aiExercises.length,
                        itemBuilder: (_, i) {
                          final e = _aiExercises[i];
                          final level = e['level'] ?? '';
                          return Dismissible(
                            key: Key('ai_$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) async {
                              final svc = SummaryPracticeService();
                              await svc.removeAIExercise(i);
                              _aiExercises.removeAt(i);
                              setState(() {});
                            },
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text({'short':'短句','paragraph':'段落','full':'全文','outline':'提纲'}[level] ?? level,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFFA29BFE))),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFA29BFE)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(e['material'] ?? '', style: const TextStyle(fontSize: 13, height: 1.6), maxLines: 5, overflow: TextOverflow.ellipsis),
                                  const Divider(height: 20),
                                  const Text('参考答案', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4ECDC4))),
                                  const SizedBox(height: 4),
                                  Text(e['answer'] ?? '', style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey.shade700)),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }

  Widget _buildItem(_SummaryGroup group) {
    final count = group.attempts.length;
    final last = group.attempts.last;

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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(group.levelName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4ECDC4))),
            ),
            const Spacer(),
            Text('作答 $count 次', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 8),
            Text(last['score'].toString() + ' 分', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(last['user_answer']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(last['created_at'].toString().substring(0, 16),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
        ]),
        children: [
          // Tab 切换各次作答
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: group.attempts.length,
              itemBuilder: (_, i) {
                final r = group.attempts[i];
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                  child: Text('第${i + 1}次 ${r['score']}分', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // 最后一次的详情
          Text(group.attempts.last['user_answer']?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}

class _SummaryGroup {
  final String questionId;
  final String levelName;
  final List<Map<String, dynamic>> attempts = [];
  _SummaryGroup({required this.questionId, required this.levelName});
}
