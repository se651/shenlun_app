import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/db_helper.dart';
import '../services/web_data_loader.dart';
import 'summary_history_screen.dart';

/// 简评学习 — 用问政陕西素材写简评，AI 打分 + 对比原简评
class CommentaryExerciseScreen extends StatefulWidget {
  const CommentaryExerciseScreen({super.key});
  @override State<CommentaryExerciseScreen> createState() => _CommentaryExerciseScreenState();
}

class _CommentaryExerciseScreenState extends State<CommentaryExerciseScreen> {
  Map<String, dynamic>? _article;
  String? _reference;
  bool _submitted = false;
  bool _scoring = false;
  bool _genning = false;
  String _result = '';
  String _aiAnswer = '';
  final _ctrl = TextEditingController();
  bool _editMode = false;
  String _tool = 'none';
  final List<_Stroke> _strokes = [];
  final List<_Highlight> _highlights = [];
  _Stroke? _cur;

  static const _wordLimit = 200;

  @override void dispose() { _ctrl.dispose(); _cachedContentDb?.close(); _cachedCommentDb?.close(); super.dispose(); }

  Database? _cachedContentDb;
  Database? _cachedCommentDb;

  Future<Database?> _openDb(String asset) async {
    if (asset.contains('content') && _cachedContentDb != null) return _cachedContentDb;
    if (asset.contains('commentary_db') && _cachedCommentDb != null) return _cachedCommentDb;
    try {
      final data = await rootBundle.load('assets/$asset');
      final dir = await getDatabasesPath();
      final dbDir = Directory(dir);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      final path = p.join(dir, '${asset}_temp.db');
      if (!File(path).existsSync()) {
        await File(path).writeAsBytes(data.buffer.asUint8List());
      }
      final db = await openDatabase(path, readOnly: true);
      if (asset.contains('content')) _cachedContentDb = db;
      else _cachedCommentDb = db;
      return db;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadRandom() async {
    _ctrl.clear(); _submitted = false; _result = ''; _aiAnswer = ''; _reference = null;
    if (kIsWeb) {
      final content = await WebDataLoader().loadCommentaryContent();
      final refs = await WebDataLoader().loadCommentaryDb();
      if (content.isEmpty) return;
      final idx = Random().nextInt(content.length);
      _article = content[idx];
      final targetId = _article!['id'] as int?;
      final match = refs.where((r) => r['article_id'] == targetId).toList();
      if (match.isNotEmpty) _reference = match.first['commentary'] as String?;
    } else {
      final cdb = await _openDb('commentary_content.db');
      final mdb = await _openDb('commentary_db.db');
      if (cdb == null || mdb == null) return;
      final count = (await cdb.rawQuery('SELECT COUNT(*) FROM articles')).first.values.first as int;
      if (count == 0) return;
      final idx = Random().nextInt(count) + 1;
      final rows = await cdb.rawQuery('SELECT * FROM articles WHERE id = ?', [idx]);
      if (rows.isNotEmpty) _article = rows.first;
      final refs2 = await mdb.rawQuery('SELECT commentary FROM commentaries WHERE article_id = ?', [idx]);
      if (refs2.isNotEmpty) _reference = refs2.first['commentary'] as String?;
    }
    if (mounted) setState(() {});
  }

  Future<void> _genAI() async {
    setState(() => _genning = true);
    final key = await DatabaseHelper().getSetting('deepseek_api_key');
    if (key.isEmpty) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置API Key'))); setState(() => _genning = false); } return; }
    try {
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({'model':'deepseek-chat','messages':[{'role':'user','content':'请为以下新闻写一篇${_wordLimit}字以内的简评：\n${_article?['body'] ?? ''}'}],'temperature':0.5,'max_tokens':300}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final ans = jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String? ?? '';
        if (mounted) setState(() => _aiAnswer = ans);
      }
    } catch (_) {}
    if (mounted) setState(() => _genning = false);
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _scoring = true);
    final key = await DatabaseHelper().getSetting('deepseek_api_key');
    if (key.isEmpty) { setState(() { _result = '请先设置API Key'; _submitted = true; _scoring = false; }); return; }
    try {
      final r = await http.post(Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type':'application/json','Authorization':'Bearer $key'},
        body: jsonEncode({
          'model':'deepseek-chat','messages':[{'role':'user','content':'你是时政评论编辑。严格打分：\n- 不切题或太短：20-40分\n- 切题但平淡：40-60分\n- 有观点：60-80分\n- 观点深刻语言精炼：80-100分\n\n新闻：${_article?['body'] ?? ''}\n用户简评：$text\n严格用JSON：{"score":数字,"comment":"20字点评"}'}],
          'temperature':0.3,'max_tokens':200,
        }),
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final c = jsonDecode(r.body)['choices']?[0]?['message']?['content'] as String? ?? '';
        final m = RegExp(r'\{[^}]+\}').firstMatch(c);
        if (m != null) {
          final d = jsonDecode(m.group(0)!);
          _result = '得分${d['score']} · ${d['comment']}';
          _saveRecord(text, d['score'], d['comment'] ?? '');
        } else { _result = c; }
      }
    } catch (_) { _result = '评分失败'; }
    if (mounted) setState(() { _submitted = true; _scoring = false; });
  }

  void _saveRecord(String answer, score, String comment) {
    try {
      final now = DateTime.now();
      DatabaseHelper().savePracticeRecord({
        'id': 'commentary_${now.millisecondsSinceEpoch}',
        'question_id': _article?['id'] ?? 'commentary',
        'user_answer': answer,
        'score': score,
        'suggestions': comment,
        'practice_mode': 'commentary_exercise',
        'created_at': now.toIso8601String(),
      });
    } catch (_) {}
  }

  Widget _buildAnnoToggle() => GestureDetector(
    onTap: () => setState(() { _editMode = !_editMode; _tool = 'none'; }),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: _editMode ? const Color(0xFFE94560) : Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
      child: Text(_editMode ? '退出标注' : '标注', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _editMode ? Colors.white : const Color(0xFF333333))),
    ),
  );

  Widget _buildAnnotatableText(String text) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _toolBtn('🖊️', 'pen'), const SizedBox(width: 6), _toolBtn('🟡', 'yellow'), const SizedBox(width: 6), _toolBtn('🔴', 'red'),
      const SizedBox(width: 10),
      if (_strokes.isNotEmpty || _highlights.isNotEmpty) GestureDetector(onTap: () => setState(() { _strokes.clear(); _highlights.clear(); }), child: const Icon(Icons.delete_outline, size: 16, color: Colors.grey)),
    ]),
    const SizedBox(height: 6),
    Container(width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: GestureDetector(
        onPanStart: _tool == 'pen' ? (d) { _cur = _Stroke(const Color(0xCCE94560)); _cur!.points.add(d.localPosition); } : null,
        onPanUpdate: _tool == 'pen' ? (d) { _cur?.points.add(d.localPosition); setState(() {}); } : null,
        onPanEnd: _tool == 'pen' ? (d) { if (_cur != null && _cur!.points.length > 1) _strokes.add(_cur!); _cur = null; setState(() {}); } : null,
        onTapUp: (_tool == 'yellow' || _tool == 'red') ? (d) => setState(() { _highlights.add(_Highlight(d.localPosition.dx - 50, d.localPosition.dy - 10, 100, 22, _tool == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700))); }) : null,
        child: CustomPaint(painter: _AnnoPainter(strokes: _strokes, highlights: _highlights),
          child: Padding(padding: const EdgeInsets.all(8), child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.7))),
        ),
      ),
    ),
  ]);

  Widget _toolBtn(String emoji, String mode) {
    final active = _tool == mode;
    return GestureDetector(onTap: () => setState(() => _tool = active ? 'none' : mode),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: active ? const Color(0xFFE94560).withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? const Color(0xFFE94560) : Colors.grey.shade300)),
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('简评学习'), actions: [
        IconButton(icon: const Icon(Icons.history), tooltip: '练习历史', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SummaryHistoryScreen()))),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRandom),
      ]),
      body: _article == null ? Center(child: TextButton(onPressed: _loadRandom, child: const Text('加载题目')))
          : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title
        Text(_article!['title'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5)),
        Text('来源：陕西网 · 问政陕西', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        const SizedBox(height: 12),
        // Material
        Row(children: [const Text('材料', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const Spacer(), _buildAnnoToggle()]),
        const SizedBox(height: 6),
        if (_editMode) _buildAnnotatableText(_article!['body'] as String? ?? '') else SelectableText(_article!['body'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.7)),
        const SizedBox(height: 20),
        // Commentary input
        const Text('请写一篇简评', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('字数限制：$_wordLimit字', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        TextField(controller: _ctrl, maxLines: 5, maxLength: _wordLimit,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: InputDecoration(hintText: '在这里写下你的简评...', hintStyle: TextStyle(color: Colors.grey.shade400), filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300))),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(height: 44, child: ElevatedButton(
              onPressed: _scoring ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _scoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('提交评分', style: TextStyle(fontSize: 15)),
            )),
          ),
          const SizedBox(width: 8),
          SizedBox(height: 44, child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFA29BFE)),
            label: const Text('AI 答案', style: TextStyle(fontSize: 12, color: Color(0xFFA29BFE))),
            onPressed: _genning ? null : _genAI,
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
        ]),
        if (_genning) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
        if (_aiAnswer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFA29BFE).withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: SelectableText('🤖 $_aiAnswer', style: const TextStyle(fontSize: 13, height: 1.6)),
          ),
        ],
        if (_submitted && _result.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Text('📝 $_result', style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
        if (_submitted && _reference != null && _reference!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [const Icon(Icons.star, size: 16, color: Color(0xFFF9CA24)), const SizedBox(width: 6), const Text('参考简评', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFF9CA24)))]),
          Text('来源：陕西网问政陕西·编辑简评', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          const SizedBox(height: 8),
          SelectableText(_reference!, style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF333333))),
        ] else if (_submitted) ...[
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: const Text('（暂无参考简评，请换题重试）', style: TextStyle(color: Colors.grey))),
        ],
        const SizedBox(height: 40),
      ])),
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
  @override void paint(Canvas canvas, Size size) {
    for (final h in highlights) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(h.x, h.y, h.w, h.h), const Radius.circular(2)), Paint()..color = h.color);
    for (final s in strokes) { if (s.points.length < 2) continue;
      final path = Path(); path.moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) path.lineTo(s.points[i].dx, s.points[i].dy);
      canvas.drawPath(path, Paint()..color = s.color..strokeWidth = 2..style = PaintingStyle.stroke); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}
