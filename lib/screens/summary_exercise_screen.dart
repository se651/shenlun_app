import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/web_data_loader.dart';
import 'summary_history_screen.dart';

/// 概括与分析 — 根据领导留言板素材练习概括+对策能力
class SummaryExerciseScreen extends StatefulWidget {
  const SummaryExerciseScreen({super.key});
  @override State<SummaryExerciseScreen> createState() => _SummaryExerciseScreenState();
}

class _SummaryExerciseScreenState extends State<SummaryExerciseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map<String, dynamic>? _currentItem;
  bool _editMode = false;
  String _tool = 'none';
  final List<_Stroke> _strokes = [];
  final List<_Highlight> _highlights = [];
  _Stroke? _cur;
  bool _loading = true;
  int _summaryLimit = 0;
  int _counterLimit = 0;
  int _replySummaryLimit = 0;
  final _summaryCtrl = TextEditingController();
  final _countermeasureCtrl = TextEditingController();
  bool _summarySubmitted = false;
  bool _counterSubmitted = false;
  String _summaryResult = '';
  String _counterResult = '';
  bool _scoring = false;
  bool _genning = false;
  String _replyAnalysis = '';
  String _summaryAI = '';
  String _counterAI = '';
  String _replySummaryAI = '';
  final _replySummaryCtrl = TextEditingController();
  bool _replySubmitted = false;
  String _replySummaryResult = '';

  static const _categories = ['30-50字', '50-200字', '200字以上'];
  static const _catLabels = ['短篇', '中篇', '长篇'];

  @override void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() { if (!_tab.indexIsChanging) _loadRandom(); });
    _loadRandom();
  }

  @override void dispose() {
    _tab.dispose();
    _summaryCtrl.dispose();
    _countermeasureCtrl.dispose();
    _replySummaryCtrl.dispose();
    _cachedDb?.close();
    super.dispose();
  }

  Database? _cachedDb;

  Future<Database?> _openBoardDb() async {
    if (_cachedDb != null) return _cachedDb;
    try {
      final data = await rootBundle.load('assets/leader_board.db');
      final dir = await getDatabasesPath();
      final path = p.join(dir, 'leader_board_temp.db');
      if (!File(path).existsSync()) {
        await File(path).writeAsBytes(data.buffer.asUint8List());
      }
      _cachedDb = await openDatabase(path, readOnly: true);
      return _cachedDb;
    } catch (_) { return null; }
  }

  Future<void> _loadRandom() async {
    setState(() => _loading = true);
    _resetAnswers();
    if (kIsWeb) {
      final all = await WebDataLoader().loadLeaderBoard();
      final filtered = all.where((r) => r['category'] == _categories[_tab.index]).toList();
      if (filtered.isNotEmpty) { filtered.shuffle(); _currentItem = filtered.first; }
    } else {
      final db = await _openBoardDb();
      if (db == null) { if (mounted) setState(() => _loading = false); return; }
      final rows = await db.rawQuery(
        'SELECT comment, reply, department, has_reply FROM leader_replies WHERE category = ? ORDER BY RANDOM() LIMIT 1',
        [_categories[_tab.index]],
      );
      if (rows.isNotEmpty) _currentItem = rows.first;
    }
    // 先给基于长度的默认值
    _setDefaultLimits();
    if (mounted) setState(() => _loading = false);
    await _generateLimits();
  }

  void _setDefaultLimits() {
    final clen = (_currentItem?['comment'] as String?)?.length ?? 0;
    if (clen == 0) return;
    _summaryLimit = (clen * 0.2).round().clamp(20, 200);
    _counterLimit = (clen * 0.3).round().clamp(30, 300);
    _replySummaryLimit = (clen * 0.25).round().clamp(20, 200);
  }

  Future<void> _generateLimits() async {
    final comment = _currentItem?['comment'] as String? ?? '';
    if (comment.isEmpty) return;
    final key = await DatabaseHelper().getSetting('deepseek_api_key');
    if (key.isEmpty) return;
    try {
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({
          'model':'deepseek-chat','messages':[{'role':'user','content':'根据留言长度计算合理的概括、对策、回复概括字数限制。只返回JSON不要其他文字。\n留言(${comment.length}字)：$comment\n\n{"summary":数字,"counter":数字,"reply":数字}'}],
          'temperature':0.1,'max_tokens':80,
        }),
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final c = jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String? ?? '';
        final m = RegExp(r'\{[^}]+\}').firstMatch(c);
        if (m != null) {
          final d = jsonDecode(m.group(0)!);
          if (mounted) setState(() {
            _summaryLimit = (d['summary'] as int?)?.clamp(20, 200) ?? _summaryLimit;
            _counterLimit = (d['counter'] as int?)?.clamp(30, 300) ?? _counterLimit;
            _replySummaryLimit = (d['reply'] as int?)?.clamp(20, 200) ?? _replySummaryLimit;
          });
        }
      }
    } catch (_) {}
  }

  void _resetAnswers() {
    _summaryCtrl.clear(); _countermeasureCtrl.clear(); _replySummaryCtrl.clear();
    _summarySubmitted = false; _counterSubmitted = false; _replySubmitted = false;
    _summaryResult = ''; _counterResult = ''; _replyAnalysis = ''; _replySummaryResult = '';
    _summaryAI = ''; _counterAI = ''; _replySummaryAI = '';
  }

  Future<void> _genAI(String type) async {
    setState(() => _genning = true);
    final key = await DatabaseHelper().getSetting('deepseek_api_key');
    if (key.isEmpty) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置API Key'))); setState(() => _genning = false); } return; }
    
    final comment = _currentItem?['comment'] as String? ?? '';
    String prompt;
    String target;
    if (type == 'summary') {
      prompt = '你是申论专家。请用${_summaryLimit}字以内概括以下内容：\n$comment';
      target = '_summaryAI';
    } else if (type == 'counter') {
      prompt = '你是申论专家。请针对以下问题提出${_counterLimit}字以内的对策建议：\n$comment';
      target = '_counterAI';
    } else {
      final reply = _currentItem?['reply'] as String? ?? '';
      prompt = '请用${_replySummaryLimit}字以内概括以下官方回复：\n$reply';
      target = '_replySummaryAI';
    }
    
    try {
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'user','content':prompt}],'temperature':0.5,'max_tokens':300}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final ans = jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String? ?? '';
        if (mounted) setState(() {
          if (target == '_summaryAI') _summaryAI = ans;
          else if (target == '_counterAI') _counterAI = ans;
          else _replySummaryAI = ans;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _genning = false);
  }

  Future<void> _scoreSummary() async {
    final text = _summaryCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _scoring = true);
    final result = await _aiScore(
      '你是一名申论专家。请对以下概括进行评分（0-100）并给出30字内的点评。\n'
      '原文：${_currentItem?['comment'] ?? ''}\n'
      '用户概括：$text\n'
      '请严格用JSON格式回复：{"score": 数字, "comment": "评语"}',
    );
    _saveRecord('summary_exercise_概括', text, result);
    if (mounted) setState(() { _summaryResult = result; _summarySubmitted = true; _scoring = false; });
  }

  Future<void> _scoreCountermeasure() async {
    final text = _countermeasureCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _scoring = true);
    final result = await _aiScore(
      '你是一名申论专家。请对以下对策建议进行评分（0-100）并给出30字内的点评。\n'
      '原文：${_currentItem?['comment'] ?? ''}\n'
      '用户对策：$text\n'
      '请严格用JSON格式回复：{"score": 数字, "comment": "评语"}',
    );
    _saveRecord('summary_exercise_对策', text, result);
    if (mounted) setState(() { _counterResult = result; _counterSubmitted = true; _scoring = false; });
  }

  Future<void> _analyzeReply() async {
    setState(() => _scoring = true);
    final result = await _aiScore(
      '分析以下政府回复的要点和亮点（100字内）：\n'
      '回复内容：${_currentItem?['reply'] ?? ''}',
    );
    if (mounted) setState(() { _replyAnalysis = result; _scoring = false; });
  }

  Future<void> _scoreReplySummary() async {
    final text = _replySummaryCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _scoring = true);
    final result = await _aiScore(
      '你是一名申论专家。请对以下回复概括进行评分（0-100）并给出30字内的点评。\n'
      '回复原文：${_currentItem?['reply'] ?? ''}\n'
      '用户概括：$text\n'
      '请严格用JSON格式回复：{"score": 数字, "comment": "评语"}',
    );
    _saveRecord('summary_exercise_概括回复', text, result);
    if (mounted) setState(() { _replySummaryResult = result; _replySubmitted = true; _scoring = false; });
  }

  void _saveRecord(String practiceMode, String answer, String result) {
    try {
      final scoreMatch = RegExp(r'得分(\d+)').firstMatch(result);
      final score = scoreMatch != null ? int.tryParse(scoreMatch.group(1)!) : null;
      final commentMatch = RegExp(r'· (.+)$').firstMatch(result);
      final comment = commentMatch?.group(1) ?? '';
      final now = DateTime.now();
      DatabaseHelper().savePracticeRecord({
        'id': '${practiceMode}_${now.millisecondsSinceEpoch}',
        'question_id': _currentItem?['id'] ?? practiceMode,
        'user_answer': answer,
        'score': score,
        'suggestions': result,
        'practice_mode': practiceMode,
        'created_at': now.toIso8601String(),
      });
    } catch (_) {}
  }

  Future<String> _aiScore(String prompt) async {
    final db = DatabaseHelper();
    final key = await db.getSetting('deepseek_api_key');
    if (key.isEmpty) return '{"score":0,"comment":"请先设置API Key"}';
    try {
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({
          'model':'deepseek-chat','messages':[{'role':'user','content':prompt}],
          'temperature':0.3,'max_tokens':200,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final content = jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String? ?? '';
        final m = RegExp(r'\{[^}]+\}').firstMatch(content);
        final json = m?.group(0);
        if (json != null) {
          final d = jsonDecode(json);
          return '得分${d['score'] ?? '?'} · ${d['comment'] ?? ''}';
        }
        return content;
      }
    } catch (_) {}
    return '评分失败，请重试';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('概括与分析'),
        actions: [IconButton(icon: const Icon(Icons.history), tooltip: '练习历史', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SummaryHistoryScreen())))],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(36), child: Container(
          color: const Color(0xFF1A1A2E),
          child: TabBar(controller: _tab, labelColor: Colors.white, unselectedLabelColor: Colors.white54,
            indicatorColor: const Color(0xFFE94560),
            tabs: List.generate(3, (i) => Tab(text: _catLabels[i])),
          ),
        )),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_currentItem == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('暂无题目', style: TextStyle(color: Colors.grey)),
        TextButton(onPressed: _loadRandom, child: const Text('换一题')),
      ]));
    }
    final comment = _currentItem!['comment'] as String? ?? '';
    final reply = _currentItem!['reply'] as String? ?? '';
    final hasReply = (_currentItem!['has_reply'] as int? ?? 0) == 1 && reply.isNotEmpty && !reply.contains('无实质回复');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 原文
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.article, size: 16, color: Colors.amber), const SizedBox(width: 6),
              const Text('原文', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(),
              _buildAnnoToggle(),
              const SizedBox(width: 6),
              TextButton.icon(icon: const Icon(Icons.refresh, size: 14), label: const Text('换一题', style: TextStyle(fontSize: 12)), onPressed: _loadRandom),
            ]),
            const SizedBox(height: 8),
            if (_editMode) _buildAnnotatableText(comment) else SelectableText(comment, style: const TextStyle(fontSize: 14, height: 1.7)),
          ]),
        ),
        const SizedBox(height: 20),
        _buildSection('一、概括', '请用简洁的语言概括原文核心内容', _summaryCtrl, _scoreSummary, _summaryLimit, onGenAI: () => _genAI('summary'), aiAnswer: _summaryAI),
        if (_summarySubmitted && _summaryResult.isNotEmpty)
          _buildScoreCard(_summaryResult),
        const SizedBox(height: 16),
        // 二、对策
        _buildSection('二、对策', '请针对原文提出的问题给出对策建议', _countermeasureCtrl, _scoreCountermeasure, _counterLimit, onGenAI: () => _genAI('counter'), aiAnswer: _counterAI),
        if (_counterSubmitted && _counterResult.isNotEmpty)
          _buildScoreCard(_counterResult),
        if (_counterSubmitted) ...[
          const SizedBox(height: 16),
          if (hasReply) ...[
            // 官方回复
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.check_circle, size: 16, color: Colors.green), const SizedBox(width: 6), const Text('官方回复', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green)), const Spacer(),
                  _buildAnnoToggle(),
                ]),
                const SizedBox(height: 8),
                if (_editMode) _buildAnnotatableText(reply) else SelectableText(reply, style: const TextStyle(fontSize: 13, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 16),
            _buildSection('三、概括回复', '请概括官方回复的核心要点', _replySummaryCtrl, _scoreReplySummary, _replySummaryLimit, onGenAI: () => _genAI('reply'), aiAnswer: _replySummaryAI),
            if (_replySubmitted && _replySummaryResult.isNotEmpty)
              _buildScoreCard(_replySummaryResult),
            const SizedBox(height: 8),
            // AI分析回复（可选）
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, color: Color(0xFFA29BFE)),
              label: const Text('AI 分析官方回复', style: TextStyle(color: Color(0xFFA29BFE))),
              onPressed: _scoring ? null : _analyzeReply,
            ),
            if (_replyAnalysis.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                child: Text('📊 $_replyAnalysis', style: const TextStyle(fontSize: 13, height: 1.6)),
              ),
            ],
          ] else
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: const Text('（本题暂无官方回复）', style: TextStyle(color: Colors.grey))),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildSection(String title, String hint, TextEditingController ctrl, VoidCallback onScore, int wordLimit, {VoidCallback? onGenAI, String aiAnswer = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('限制 $wordLimit 字', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl, maxLines: 4, maxLength: wordLimit,
        style: const TextStyle(fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(12),
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SizedBox(height: 40, child: ElevatedButton(
            onPressed: (_scoring || _genning) ? null : onScore,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: _scoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('提交评分', style: TextStyle(fontSize: 14)),
          )),
        ),
        if (onGenAI != null) ...[
          const SizedBox(width: 8),
          SizedBox(height: 40, child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFA29BFE)),
            label: const Text('AI 答案', style: TextStyle(fontSize: 12, color: Color(0xFFA29BFE))),
            onPressed: _genning ? null : onGenAI,
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
        ],
      ]),
      if (_genning) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
      if (aiAnswer.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
          child: SelectableText('🤖 $aiAnswer', style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
      ],
    ]);
  }

  Widget _buildAnnoToggle() {
    return GestureDetector(
      onTap: () => setState(() { _editMode = !_editMode; _tool = 'none'; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _editMode ? const Color(0xFFE94560) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(_editMode ? '退出标注' : '标注', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _editMode ? Colors.white : const Color(0xFF333333))),
      ),
    );
  }

  Widget _buildAnnotatableText(String text) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Toolbar
      Row(children: [
        _toolBtn('🖊️', 'pen'),
        const SizedBox(width: 6),
        _toolBtn('🟡', 'yellow'),
        const SizedBox(width: 6),
        _toolBtn('🔴', 'red'),
        const SizedBox(width: 10),
        if (_strokes.isNotEmpty || _highlights.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() { _strokes.clear(); _highlights.clear(); }),
            child: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
          ),
      ]),
      const SizedBox(height: 6),
      // Annotation area
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: GestureDetector(
          onPanStart: _tool == 'pen' ? (d) { _cur = _Stroke(const Color(0xCCE94560)); _cur!.points.add(d.localPosition); } : null,
          onPanUpdate: _tool == 'pen' ? (d) { _cur?.points.add(d.localPosition); setState(() {}); } : null,
          onPanEnd: _tool == 'pen' ? (d) { if (_cur != null && _cur!.points.length > 1) _strokes.add(_cur!); _cur = null; setState(() {}); } : null,
          onTapUp: (_tool == 'yellow' || _tool == 'red') ? (d) {
            setState(() { _highlights.add(_Highlight(d.localPosition.dx - 50, d.localPosition.dy - 10, 100, 22, _tool == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700))); });
          } : null,
          child: CustomPaint(
            painter: _AnnoPainter(strokes: _strokes, highlights: _highlights),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.7)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _toolBtn(String emoji, String mode) {
    final active = _tool == mode;
    return GestureDetector(
      onTap: () => setState(() => _tool = active ? 'none' : mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE94560).withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? const Color(0xFFE94560) : Colors.grey.shade300, width: 1),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildScoreCard(String result) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
        child: Text('📝 $result', style: const TextStyle(fontSize: 13, height: 1.5)),
      ),
    );
  }
}

class _Stroke {
  final Color color;
  final List<Offset> points = [];
  _Stroke(this.color);
}

class _Highlight {
  final double x, y, w, h;
  final Color color;
  _Highlight(this.x, this.y, this.w, this.h, this.color);
}

class _AnnoPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<_Highlight> highlights;
  _AnnoPainter({required this.strokes, required this.highlights});

  @override
  void paint(Canvas canvas, Size size) {
    for (final h in highlights) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(h.x, h.y, h.w, h.h), const Radius.circular(2)),
          Paint()..color = h.color);
    }
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final path = Path();
      path.moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, Paint()..color = s.color..strokeWidth = 2..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
