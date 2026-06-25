import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';
import 'question_detail_screen.dart';

/// 套卷练习 — 复用 QuestionDetailScreen 排版，加前后翻题 + AI 评分
class PaperPracticeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String paperName;
  final String? paperId;
  const PaperPracticeScreen({super.key, required this.questions, required this.paperName, this.paperId});
  @override State<PaperPracticeScreen> createState() => _State();
}

class _State extends State<PaperPracticeScreen> {
  int _i = 0;
  bool _done = false;
  bool _busy = false;
  final _scores = <int, _AI>{};
  List<String>? _alz;
  final _ansCtrls = <int, TextEditingController>{};
  List<Map<String, dynamic>> _answerHistory = [];
  int _historyIdx0 = 0;
  int _historyIdx1 = -1;
  String? _compareResult;

  @override void dispose() { for (final c in _ansCtrls.values) c.dispose(); super.dispose(); }

  void _next() => _i < widget.questions.length - 1 ? setState(() => _i++) : _finish();

  Future<void> _finish() async {
    setState(() { _done = true; _busy = true; });
    final db = DatabaseHelper(); final key = await db.getSetting('deepseek_api_key');
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final ans = _getAns(i);
      if (ans.isEmpty) { _scores[i] = _AI(0, '未作答'); continue; }
      if (key.isEmpty) { _scores[i] = _AI(ans.length > 20 ? 70 : 30, '请设置 API Key'); continue; }
      try {
        final p = '申论阅卷专家。评分0-100，20字评语。\n题型:${q['question_type']}\n【材料+题】\n${_trim(q['content'] as String? ?? '', 2000)}\n【参考】\n${_trim(q['reference_answer'] as String? ?? '', 1000)}\n【作答】\n$ans\nJSON:{"score":数字,"comment":"评语"}';
        final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
          headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
          body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'system','content':'只返回JSON'},{'role':'user','content':p}],'temperature':0.3,'max_tokens':150}),
        ).timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final t = (jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String?) ?? '';
          final m = RegExp(r'\{[^}]+\}').firstMatch(t);
          if (m != null) { final d = jsonDecode(m.group(0)!); _scores[i] = _AI(d['score']??60, d['comment']??''); continue; }
        }
      } catch (_) {}
      _scores[i] = _AI(60, '评分失败');
    }
    if (mounted) setState(() => _busy = false);
    // 完成套卷后保存答题历史
    if (widget.paperId != null) {
      final db = DatabaseHelper();
      await db.addPaperToHistory(widget.paperId!);
      await _saveAnswerHistory();
      _answerHistory = await db.getPaperAnswerHistory(widget.paperId!);
      _historyIdx0 = _answerHistory.length - 1;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveAnswerHistory() async {
    if (widget.paperId == null) return;
    final db = DatabaseHelper();
    final now = DateTime.now().toIso8601String().substring(0, 16);
    final answers = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      answers.add({
        'question_index': i + 1,
        'title': q['title'] ?? '第${i+1}题',
        'type': q['question_type'] ?? '',
        'answer': _getAns(i),
        'score': _scores[i]?.score ?? 0,
        'comment': _scores[i]?.comment ?? '',
        'alz': _alz != null && i < _alz!.length ? _alz![i] : '',
      });
    }
    final history = await db.getPaperAnswerHistory(widget.paperId!);
    history.add({
      'time': now,
      'answers': answers,
    });
    await db.savePaperAnswerHistory(widget.paperId!, history);
  }

  Future<void> _loadHistory() async {
    if (widget.paperId == null) return;
    _answerHistory = await DatabaseHelper().getPaperAnswerHistory(widget.paperId!);
    _historyIdx0 = _answerHistory.isNotEmpty ? _answerHistory.length - 1 : 0;
  }

  String _getAns(int i) {
    return _ansCtrls[i]?.text.trim() ?? '';
  }

  String _trim(String s, int n) => s.length > n ? s.substring(0, n) : s;

  Widget _buildHistorySection(int qi) {
    final history = _answerHistory;
    if (_historyIdx0 < 0 || _historyIdx0 >= history.length) return const SizedBox.shrink();
    final attempt = history[_historyIdx0];
    final answers = (attempt['answers'] as List?) ?? [];
    Map<String, dynamic>? ans;
    for (final a in answers) {
      if ((a['question_index'] ?? 0) == qi + 1) { ans = a as Map<String, dynamic>; break; }
    }
    if (ans == null) return const SizedBox.shrink();
    final prevAns = (ans['answer'] as String?) ?? '';
    final prevScore = ans['score'] ?? 0;
    final prevComment = (ans['comment'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, size: 14, color: Color(0xFFF9CA24)),
          const SizedBox(width: 6),
          const Text('历史作答', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF9CA24))),
          const Spacer(),
          if (history.length > 1)
            Row(children: [
              GestureDetector(
                onTap: () => setState(() { _historyIdx0 = (_historyIdx0 - 1).clamp(0, history.length - 1); }),
                child: const Icon(Icons.chevron_left, size: 18, color: Colors.grey),
              ),
              GestureDetector(
                onTap: () => setState(() { _historyIdx1 = _historyIdx0; }),
                onLongPress: () => setState(() { _historyIdx1 = -1; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _historyIdx1 == _historyIdx0 ? const Color(0xFF6C5CE7).withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_historyIdx0 + 1}/${history.length}${_historyIdx1 == _historyIdx0 ? ' ✓' : ''}',
                    style: TextStyle(fontSize: 11, color: _historyIdx1 == _historyIdx0 ? const Color(0xFF6C5CE7) : Colors.grey),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() { _historyIdx0 = (_historyIdx0 + 1).clamp(0, history.length - 1); }),
                child: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ),
            ]),
        ]),
        Text('${attempt['time'] ?? ''}  ·  $prevScore分', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Text(prevAns.isEmpty ? '(未作答)' : prevAns, style: TextStyle(fontSize: 13, height: 1.6, color: prevAns.isEmpty ? Colors.grey : Colors.black87)),
        ),
        if (prevComment.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('💬 $prevComment', style: const TextStyle(fontSize: 12, color: Color(0xFF6C5CE7), height: 1.5))),
      ]),
    );
  }

  /// AI 对比两次作答
  Future<void> _compareAnswers() async {
    if (_historyIdx1 < 0 || _historyIdx1 == _historyIdx0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择对比的第二次作答（长按某次历史）')));
      return;
    }
    setState(() => _busy = true);
    final db = DatabaseHelper();
    final key = await db.getSetting('deepseek_api_key');
    if (key.isEmpty) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请设置API Key'))); setState(() => _busy = false); }
      return;
    }
    try {
      final a0 = _answerHistory[_historyIdx0];
      final a1 = _answerHistory[_historyIdx1];
      final prompt = '''申论辅导专家。对比用户对同一套卷的两次作答，指出进步之处和仍存在的问题。
第1次 (${a0['time']}):
${_formatHistoryAnswers(a0)}
第2次 (${a1['time']}):
${_formatHistoryAnswers(a1)}
请简要分析：1.进步点 2.仍存在的问题 3.下一步建议。200字以内。''';
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'user','content':prompt}],'temperature':0.5,'max_tokens':400}),
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        _compareResult = (jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String?) ?? '分析失败';
      }
    } catch (_) { _compareResult = '分析失败'; }
    if (mounted) setState(() => _busy = false);
  }

  String _formatHistoryAnswers(Map<String, dynamic> attempt) {
    final answers = (attempt['answers'] as List?) ?? [];
    return answers.map((a) => '${a['title']} (${a['type']}): ${a['answer'] ?? '(空)'}').join('\n');
  }

  /// AI 生成答案（按需调用）
  Future<String> _generateAnswer(Map<String, dynamic> q) async {
    final db = DatabaseHelper();
    final key = await db.getSetting('deepseek_api_key');
    if (key.isEmpty) return '';
    final content = (q['content'] as String?) ?? '';
    final qType = (q['question_type'] as String?) ?? '';
    // 提取题目文字
    final idx = content.lastIndexOf('作答要求');
    final qText = idx >= 0 ? content.substring(idx) : content.substring(content.length - 500 > 0 ? content.length - 500 : 0);
    try {
      final prompt = '申论阅卷专家。请为以下申论题生成参考答案（点式作答��分条列出要点）：\n题型：$qType\n【题目】\n${_trim(qText, 3000)}\n请生成参考答案：';
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({
          'model':'deepseek-chat','messages':[{'role':'user','content':prompt}],
          'temperature':0.5,'max_tokens':800,
        }),
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        return (jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String?) ?? '';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _result();

    final q = widget.questions[_i];
    if (!_ansCtrls.containsKey(_i)) _ansCtrls[_i] = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: Text('${_i + 1}/${widget.questions.length}  ${q['title'] ?? ''}  ·  ${q['question_type'] ?? ''}')),
      body: QuestionDetailScreen(
        key: ValueKey(q['id']),
        questionId: q['id'] as String,
        questionType: (q['question_type'] as String?) ?? '',
        sharedAnswerCtrl: _ansCtrls[_i],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            if (_i > 0) OutlinedButton(onPressed: () => setState(() => _i--), child: const Text('上一题')),
            const Spacer(),
            FilledButton(onPressed: _next, child: Text(_i < widget.questions.length - 1 ? '下一题' : '完成并评分')),
          ]),
        ),
      ),
    );
  }

  int _extractScore(Map<String, dynamic> q) {
    // From score_hint field
    final hint = q['score_hint'];
    if (hint is int && hint > 0) return hint;
    if (hint is String) { final p = int.tryParse(hint); if (p != null && p > 0) return p; }
    // From question text
    final content = (q['content'] as String?) ?? '';
    final m = RegExp(r'（(\d+)分）').firstMatch(content.substring(content.length - 300 > 0 ? content.length - 300 : 0));
    if (m != null) { final p = int.tryParse(m.group(1)!); if (p != null && p > 0) return p; }
    return 20; // default
  }

  /// 归一化分值，确保每套卷满分100
  List<int> _normalizeScores() {
    final raw = widget.questions.map((q) => _extractScore(q)).toList();
    final sum = raw.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) return List.filled(raw.length, 100 ~/ raw.length);
    if (sum == 100) return raw;
    // 按比例缩放到100
    return raw.map((s) => (s / sum * 100).round()).toList();
  }

  Widget _result() {
    // 加载历史
    if (_answerHistory.isEmpty && widget.paperId != null) {
      _loadHistory();
    }
    final normScores = _normalizeScores();
    int totalScore = 0;
    int maxTotal = 100;
    for (int i = 0; i < widget.questions.length; i++) {
      final s = _scores[i]?.score ?? 0;
      final maxS = normScores[i];
      totalScore += (s / 100.0 * maxS).round();
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.paperName)),
      body: _busy
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('AI 评分中...')]))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF4A4A6E)]), borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  const Text('练习完成', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text('$totalScore / $maxTotal', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800)),
                  Text('满分100 · ${widget.questions.length} 题 · AI评分', style: const TextStyle(color: Colors.white54)),
                ])),
              const SizedBox(height: 12),
              OutlinedButton.icon(icon: const Icon(Icons.auto_awesome, color: Color(0xFFA29BFE)), label: Text(_alz == null ? 'AI 逐题评析' : '刷新评析', style: const TextStyle(color: Color(0xFFA29BFE))), onPressed: _busy ? null : _runAlz),
              const SizedBox(height: 16),
              ...List.generate(widget.questions.length, (i) {
                final q = widget.questions[i]; final r = _scores[i]; final s = r?.score ?? 0;
                final maxS = normScores[i];
                final ref = (q['reference_answer'] as String?) ?? '';
                return Card(margin: const EdgeInsets.only(bottom: 8), child: ExpansionTile(
                  leading: CircleAvatar(backgroundColor: s >= 70 ? Colors.green.shade100 : s >= 50 ? Colors.orange.shade100 : Colors.red.shade100, radius: 14, child: Text('$s', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s >= 70 ? Colors.green : s >= 50 ? Colors.orange : Colors.red))),
                  title: Text('${q['title']??''} [${q['question_type']??''}] ($maxS分)', style: const TextStyle(fontSize: 13)),
                  subtitle: (r?.comment??'').isNotEmpty ? Text(r!.comment, style: const TextStyle(fontSize:11)) : null,
                  children: [
                    // 历史答案切换
                    if (_answerHistory.isNotEmpty) _buildHistorySection(i),
                    if (ref.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Divider(),
                          Row(children: [
                            const Icon(Icons.menu_book, size: 14, color: Color(0xFF4ECDC4)),
                            const SizedBox(width: 6),
                            const Text('参考答案', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4ECDC4))),
                          ]),
                          const SizedBox(height: 6),
                          Text(ref, style: const TextStyle(fontSize: 13, height: 1.7)),
                        ]),
                      ),
                    if (_alz != null && i < _alz!.length) _AlzToggle(alzText: _alz![i]),
                  ],
                ));
              }),
              // AI 对比两次作答
              if (_answerHistory.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.compare_arrows, color: Color(0xFF6C5CE7)),
                      label: Text('对比 ${_historyIdx1 >= 0 ? '' : '(长按选第二次)'}', style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 12)),
                      onPressed: _busy ? null : _compareAnswers,
                    ),
                    if (_compareResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                          child: Text('📊 $_compareResult', style: const TextStyle(fontSize: 12, height: 1.6)),
                        ),
                      ),
                  ]),
                ),
              // AI 补全答案按钮
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome, color: Color(0xFFE94560)),
                label: const Text('AI 补全参考答案', style: TextStyle(color: Color(0xFFE94560))),
                onPressed: _busy ? null : () async {
                  setState(() => _busy = true);
                  final db = DatabaseHelper();
                  for (int i = 0; i < widget.questions.length; i++) {
                    final q = widget.questions[i];
                    // 只补没有答案的
                    final existing = (q['reference_answer'] as String?) ?? '';
                    if (existing.isNotEmpty && existing.length > 20) continue;
                    final ans = await _generateAnswer(q);
                    if (ans.isNotEmpty) {
                      await db.setPaperQuestionAnswer(q['id'] as String, ans);
                      q['reference_answer'] = ans;
                    }
                  }
                  if (mounted) setState(() => _busy = false);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('返回')),
            ]),
    );
  }

  Future<void> _runAlz() async {
    setState(() => _busy = true);
    final db = DatabaseHelper(); final key = await db.getSetting('deepseek_api_key');
    if (key.isEmpty) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置 API Key'))); setState(() => _busy = false); } return; }
    _alz = [];
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      try {
        final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'), headers: {'Content-Type':'application/json','Authorization':'Bearer $key'}, body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'system','content':'申论辅导专家，200字分析得分点和改进建议'},{'role':'user','content':'题型:${q['question_type']}\n【参考】\n${_trim(q['reference_answer'] as String? ?? '', 1500)}'}],'temperature':0.5,'max_tokens':300})).timeout(const Duration(seconds: 20));
        _alz!.add(r.statusCode == 200 ? ((jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String?) ?? '分析失败') : '分析失败');
      } catch (_) { _alz!.add('分析失败'); }
      if (mounted && i % 2 == 0) setState(() {});
    }
    if (mounted) setState(() => _busy = false);
  }
}

class _AI { final int score; final String comment; _AI(this.score, this.comment); }

/// 评析切换：全文 / 要点框架
class _AlzToggle extends StatefulWidget {
  final String alzText;
  const _AlzToggle({required this.alzText});
  @override State<_AlzToggle> createState() => _AlzToggleState();
}

class _AlzToggleState extends State<_AlzToggle> {
  bool _fullText = false;

  String get _framework {
    // 要点框架：提取每行首句
    final lines = widget.alzText.split(RegExp(r'[\n。；]'));
    final points = <String>[];
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.length < 4) continue;
      if (line.startsWith('#')) { points.add(line); continue; }
      points.add('• $line');
    }
    return points.isNotEmpty ? points.join('\n') : widget.alzText;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🔍 评析', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _fullText = !_fullText),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _fullText ? const Color(0xFF4ECDC4) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_fullText ? '全文' : '要点', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _fullText ? Colors.white : Colors.grey.shade700)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(_fullText ? widget.alzText : _framework, style: const TextStyle(fontSize: 12, height: 1.6)),
      ]),
    );
  }
}