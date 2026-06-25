import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../scorer/local_scorer.dart';
import '../scorer/ai_scorer.dart';
import '../services/export_service.dart';
import 'answer_editor.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ocr_service.dart';

class QuestionDetailScreen extends StatefulWidget {
  final String questionId;
  final String questionType;
  final TextEditingController? sharedAnswerCtrl; // 套卷模式共享答案
  final bool skipHistory; // 每日一练等不记录历史
  const QuestionDetailScreen({super.key, required this.questionId, required this.questionType, this.sharedAnswerCtrl, this.skipHistory = false});

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  final _db = DatabaseHelper();
  Map<String, dynamic>? _question;
  late final TextEditingController _answerController;

  @override
  void initState() {
    super.initState();
    _answerController = widget.sharedAnswerCtrl ?? TextEditingController();
    _answerController.addListener(_onTextChanged);
    _load();
  }
  final _editorKey = GlobalKey<AnswerEditorState>();
  bool _loading = true;
  bool _submitted = false;
  bool _isFavorited = false;
  bool _isSplitHorizontal = false;
  double _splitRatio = 0.45;
  ScoreResult? _scoreResult;
  bool _showAnswer = false;
  bool _scoring = false; // AI评分进行中
  bool _aiFilling = false; // AI补充答案进行中
  String _aiFilledAnswer = ''; // AI补充的答案
  bool _aiFullMode = false; // false=框架 true=全文
  String _aiTeacher = '袁东'; // AI生成时选的名师风格
  // 材料标注
  bool _editMode = false;
  String _materialTool = 'none';
  final List<_Stroke> _matStrokes = [];
  _Stroke? _matCur;
  final List<_Highlight> _matHighlights = [];
  final List<_Action2> _matUndo = [];

  // 题目标注（独立于材料标注）
  bool _qEditMode = false;
  String _qTool = 'none';
  final List<_Stroke> _qStrokes = [];
  _Stroke? _qCur;
  final List<_Highlight> _qHighlights = [];
  final List<_Action2> _qUndo = [];
  int _charCount = 0;
  String _selectedTeacher = '袁东';
  Map<String, String> _teacherAnswers = {};

  // ── OCR 识图 ──
  bool _ocrLoading = false;

  // ── 要点答题模式 ──
  bool _outlineMode = false;
  final _mainArgumentController = TextEditingController();
  final List<TextEditingController> _subArgumentControllers = [
    TextEditingController(), TextEditingController(), TextEditingController(),
  ];
  OutlineScoreResult? _outlineResult;

  void _onTextChanged() {
    final count = _answerController.text.length;
    if (count != _charCount) {
      final prevMilestone = _charCount ~/ 100;
      final newMilestone = count ~/ 100;
      if (newMilestone > prevMilestone && newMilestone > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📝 已达到 ${newMilestone * 100} 字'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            width: 180,
          ),
        );
      }
      setState(() => _charCount = count);
    }
  }

  @override
  @override
  void dispose() {
    _answerController.removeListener(_onTextChanged);
    // 套卷模式下共享 controller，不能 dispose
    if (widget.sharedAnswerCtrl == null) {
      _answerController.dispose();
    }
    _mainArgumentController.dispose();
    for (final c in _subArgumentControllers) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var q = await _db.getQuestionById(widget.questionId);
      q ??= await _db.getPaperQuestionById(widget.questionId);
      bool fav = false;
      try { fav = await _db.isFavorited(widget.questionId); } catch (_) {}
      // 读取分屏偏好
      bool splitH = false;
      try {
        final s = await _db.getSetting('split_horizontal');
        splitH = s == '1';
      } catch (_) {}
      if (mounted) setState(() { _question = q; _isFavorited = fav; _loading = false; _isSplitHorizontal = splitH; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSplit() {
    final newVal = !_isSplitHorizontal;
    setState(() => _isSplitHorizontal = newVal);
    _db.setSetting('split_horizontal', newVal ? '1' : '0');
  }

  void _saveToDownload(BuildContext ctx) {
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final title = '材料_$ts';
    final q = _question;
    final content = q?['content'] as String? ?? '';
    final questionTitle = q?['title'] as String? ?? '';
    final fullContent = questionTitle.isNotEmpty ? '【题目】$questionTitle\n\n$content' : content;
    ExportService.saveToDownloadList(title, fullContent);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('已保存到我的下载'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    await _db.toggleFavorite(widget.questionId);
    setState(() => _isFavorited = !_isFavorited);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFavorited ? '已加入收藏' : '已取消收藏'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          width: 150,
        ),
      );
    }
  }

  Future<void> _submitAnswer() async {
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入答案')),
      );
      return;
    }

    setState(() => _scoring = true);

    final q = _question!;
    final fullRef = (q['reference_answer'] as String?) ?? '';
    final content = (q['content'] as String?) ?? '';
    final wordLimit = (q['word_limit'] is int ? q['word_limit'] : int.tryParse('${q['word_limit'] ?? ''}')) as int?;
    final scoreHint = q['score_hint'] as String?;

    // 解析各名师答案
    _teacherAnswers = _parseTeacherAnswers(fullRef);

    // 打分用答案
    final hasTeacherMarkers = _teacherAnswers.isNotEmpty;
    final scoringAnswer = hasTeacherMarkers
        ? (_teacherAnswers['袁东'] ?? _teacherAnswers.values.first)
        : fullRef;

    final materialText = _extractMaterial(content);

    // 有 API key 默认走 AI（除非用户手动切换为本地）
    final scoringMode = await _db.getSetting('scoring_mode');
    final apiKey = await _db.getSetting('deepseek_api_key');
    final useAI = apiKey.isNotEmpty && scoringMode != 'local';

    ScoreResult? result;

    if (useAI) {
      result = await AIScorer.score(
        apiKey: apiKey,
        userAnswer: userAnswer,
        referenceAnswer: scoringAnswer,
        materialText: materialText,
        questionType: widget.questionType,
        scoreHint: scoreHint,
        wordLimit: wordLimit,
      );
    }

    // AI 未启用或失败 → 降级到本地评分
    result ??= LocalScorer.score(
      userAnswer: userAnswer,
      referenceAnswer: scoringAnswer,
      materialText: materialText,
      questionType: widget.questionType,
      scoreHint: scoreHint,
      wordLimit: wordLimit,
    );

    final effectiveMode = (useAI && result != null) ? 'ai' : 'local';

    if (mounted) {
      setState(() {
        _submitted = true;
        _scoreResult = result;
        _showAnswer = true;
        _scoring = false;
      });
    }

    _saveRecord(userAnswer, result!, effectiveMode);
  }

  void _saveRecord(String userAnswer, ScoreResult result, String mode) {
    if (widget.skipHistory) return; // 每日一练不记录历史
    _db.savePracticeRecord({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'question_id': widget.questionId,
      'user_answer': userAnswer,
      'score': result.score,
      'score_breakdown': result.details,
      'suggestions': result.feedback,
      'scoring_mode': mode,
      'practice_mode': widget.questionType,
      'ai_answer': _aiFilledAnswer.isNotEmpty ? _aiFilledAnswer : null,
      'ai_analysis': (result.feedback.isNotEmpty && result.feedback != '评分失败，请重试') ? result.feedback : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    _db.updateUserStats(addPractice: 1, lastDate: DateTime.now().toIso8601String().substring(0, 10));
  }

  /// 分离材料与题目：返回 (materialText, questionText)
  (String, String) _splitContent(String content, {bool isEssay = false}) {
    // 大作文：找最后一个"文章"或"议论文"出现位置，从该行开头分割
    if (isEssay) {
      final essayIdx = content.lastIndexOf(RegExp(r'文章|议论文'));
      if (essayIdx >= 0) {
        final lineStart = content.lastIndexOf('\n', essayIdx);
        final splitIdx = lineStart >= 0 ? lineStart : 0;
        return (content.substring(0, splitIdx).trim(), content.substring(splitIdx).trim());
      }
      // 回退：找边界
      final boundaryPatterns = [
        RegExp(r'\n作答要求'),
        RegExp(r'\n[\[【]?答题要求'),
        RegExp(r'\n[\[【]?题目要求'),
      ];
      int materialEnd = -1;
      for (final p in boundaryPatterns) {
        final matches = p.allMatches(content).toList();
        if (matches.isNotEmpty) {
          final last = matches.last.start;
          if (last > materialEnd) materialEnd = last;
        }
      }
      if (materialEnd > 0) {
        return (content.substring(0, materialEnd).trim(), content.substring(materialEnd).trim());
      }
      return (content, '');
    }

    // 非大作文：先找题目起始行
    // 题目行特征：根据/请根据/请用/请指出/谈谈 + 资料/材料 + 概括/分析/归纳等
    final questionLinePatterns = [
      // 作答要求边界
      RegExp(r'作答要求'),
      // 问题编号
      RegExp(r'\n?问题\d+[：:]'),
      RegExp(r'\n?第[一二三四五六七八九十\d]+题'),
      // 根据/请等题目关键词
      RegExp(r'\n根据给定材料[^\n]*'),
      RegExp(r'\n根据给定资料[^\n]*'),
      RegExp(r'\n根据["\u201c]给定资料[^\n]*'),
      RegExp(r'\n根据[\s\S]{0,20}材料[^\n]*'),
      RegExp(r'\n根据[\s\S]{0,20}资料[^\n]*'),
      RegExp(r'\n请根据[^\n]*'),
      RegExp(r'\n请用[^\n]*(?:归纳|概括|分析|表述)[^\n]*'),
      RegExp(r'\n请指出[^\n]*'),
      RegExp(r'\n请结合[^\n]*'),
      // "给定资料X" — 放宽前面间隔
      RegExp(r'\n[^\n]{0,80}给定资料\s*\d+[^\n]*'),
      // 数字编号开头的问题
      RegExp(r'\n\d+[.、]\s*(?:根据|请|要求|假如|如果|给定|阅读|结合|谈谈|概括|归纳|分析)[^\n]*'),
    ];
    int questionStart = -1;
    final contentLen = content.length;
    for (final p in questionLinePatterns) {
      final matches = p.allMatches(content).toList();
      if (matches.isNotEmpty) {
        for (int i = matches.length - 1; i >= 0; i--) {
          final pos = matches[i].start;
          // 必须以"给定资料"开头的行需要严格位置校验
          final matched = content.substring(pos, (pos + 30).clamp(0, contentLen));
          final isGivenZiliao = matched.trimLeft().startsWith('给定资料');
          final minPos = isGivenZiliao ? contentLen * 0.4 : 0;
          if (pos > minPos) {
            if (pos > questionStart) questionStart = pos;
            break;
          }
        }
      }
    }

    if (questionStart >= 0) {
      return (content.substring(0, questionStart).trim(), content.substring(questionStart).trim());
    }

    // 回退：用"要求"分割 — 在"要求："前最近的句号/分号处切开
    final reqPattern = RegExp(r'([。；）])\s*\n?\s*(?:[\[【]?(?:答题)?要求[：:\s（])');
    final reqMatch = reqPattern.firstMatch(content);
    if (reqMatch != null) {
      // Split right after the sentence end marker, before "要求："
      final cut = reqMatch.start + 1;
      return (content.substring(0, cut).trim(), content.substring(cut).trim());
    }

    // 最后兜底：取末尾最近的题目段落
    // 从末尾向前找第一个明显的题目起始行
    final lastQuestion = RegExp(r'\n[^\n]{2,120}(?:根据|请根据|请结合|给定资料|请你|假如你|要求[：:])');
    final lastMatch = lastQuestion.allMatches(content).toList();
    if (lastMatch.isNotEmpty) {
      final pos = lastMatch.last.start;
      return (content.substring(0, pos).trim(), content.substring(pos).trim());
    }
    return (content, '');
  }

  /// 从 content 中提取纯材料部分（去掉题目要求）
  String _extractMaterial(String content) {
    // content 格式：【给定资料N】\n材料正文...\n\n题目要求...
    // 找到最后一个 【给定资料 之前的题目要求行
    final reqMatch = RegExp(r'\n(?:要求[：:]|请根据|请结合|请以)').firstMatch(content);
    if (reqMatch != null) {
      return content.substring(0, reqMatch.start).trim();
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final inPaperMode = widget.sharedAnswerCtrl != null;
    return Scaffold(
      appBar: inPaperMode ? null : AppBar(
        title: Text(widget.questionType),
        actions: [
          IconButton(
            icon: Icon(_isFavorited ? Icons.bookmark : Icons.bookmark_border,
                color: _isFavorited ? const Color(0xFFE94560) : null),
            onPressed: _toggleFavorite,
            tooltip: _isFavorited ? '取消收藏' : '加入收藏',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _question == null
              ? Center(child: Text('题目加载失败', style: TextStyle(color: Colors.grey.shade500)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final q = _question!;
    final title = (q['title'] as String?) ?? '';
    final content = (q['content'] as String?) ?? '';
    final year = q['year'];
    final region = (q['region'] as String?) ?? '';
    final referenceAnswer = (q['reference_answer'] as String?) ?? '';
    final isEssay = widget.questionType.contains('文章论述') || widget.questionType.contains('大作文');
    final (materialText, questionText) = _splitContent(content, isEssay: isEssay);

    // 材料区（独立 widget，供分屏复用）
    // UNDO
    void matUndo() {
      if (_matUndo.isEmpty) return;
      final a = _matUndo.removeLast();
      if (a is _PenAction2) _matStrokes.remove(a.stroke);
      else if (a is _HlAction2) _matHighlights.remove(a.hl);
      setState(() {});
    }

    Widget materialSection = Column(children: [
      if (materialText.isNotEmpty) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const Text('📖   ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            // 编辑模式切换
            GestureDetector(
            onTap: () => setState(() { _editMode = !_editMode; _materialTool = 'none'; }),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _editMode ? const Color(0xFFE94560) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_editMode ? '退出标注' : '标注', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: _editMode ? Colors.white : const Color(0xFF333333))),
            ),
          ),
          if (_editMode) ...[
            // 工具切换
            _toolBtn('🖊️', 'pen', _materialTool, (s) => setState(() => _materialTool = s == _materialTool ? 'none' : s)),
            _toolBtn('🟡', 'yellow', _materialTool, (s) => setState(() => _materialTool = s == _materialTool ? 'none' : s)),
            _toolBtn('🔴', 'red', _materialTool, (s) => setState(() => _materialTool = s == _materialTool ? 'none' : s)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: (_matStrokes.isNotEmpty || _matHighlights.isNotEmpty) ? () { setState(() { _matStrokes.clear(); _matHighlights.clear(); _matUndo.clear(); _matCur = null; }); } : null,
              child: Icon(Icons.delete_outline, size: 16, color: (_matStrokes.isNotEmpty || _matHighlights.isNotEmpty) ? const Color(0xFF333333) : Colors.grey.shade300),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: _matUndo.isNotEmpty ? () => matUndo() : null,
              child: Icon(Icons.undo, size: 16, color: _matUndo.isNotEmpty ? const Color(0xFF333333) : Colors.grey.shade300),
            ),
          ],
          IconButton(
            icon: Icon(_isSplitHorizontal ? Icons.swap_vert : Icons.swap_horiz, size: 20),
            tooltip: _isSplitHorizontal ? '切换上下分屏' : '切换左右分屏',
            onPressed: _toggleSplit,
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FullScreenMaterial(content: materialText, questionTitle: _question?['title'] ?? ''))),
            icon: const Icon(Icons.fullscreen, size: 18),
            label: const Text('全屏', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            tooltip: '保存到我的下载',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, maxWidth: 32),
            onPressed: () => _saveToDownload(context),
          ),
        ])),
        const SizedBox(height: 6),
        Expanded(child: _editMode ? _buildAnnotatableCard(materialText, true) : _buildMaterialCard(materialText)),
      ],
    ]);

    // 题目+答题区
    Widget qaSection = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (year != null || region.isNotEmpty)
          Row(children: [
            if (year != null)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('$year', style: const TextStyle(fontSize: 11, color: Color(0xFF4ECDC4)))),
            if (region.isNotEmpty) ...[const SizedBox(width: 8), Text(region, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))],
          ]),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 16),
        ],
        if (questionText.isNotEmpty) ...[
          _buildQuestionCardWithToolbar(questionText),
          const SizedBox(height: 16),
        ],
        _buildAnswerSheet(),
        if (!_submitted) ...[
          const SizedBox(height: 8),
          // AI 生成参考答案（提交前可用）
          SizedBox(width: double.infinity, height: 38, child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFA29BFE)),
            label: const Text('AI 生成参考答案', style: TextStyle(fontSize: 13, color: Color(0xFFA29BFE))),
            onPressed: _aiFilling ? null : _aiFillAnswer,
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: _scoring ? null : (_outlineMode ? _submitOutline : _submitAnswer),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            child: _scoring ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('提交评分', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          )),
        ],
        if (_submitted && _outlineResult != null) ...[const SizedBox(height: 16), _buildOutlineScoreCard()],
        if (_submitted && _scoreResult != null && _outlineResult == null) ...[const SizedBox(height: 16), _buildScoreCard()],
        if (_submitted && _scoreResult != null) ...[const SizedBox(height: 16), _buildCompareTabs(referenceAnswer)],
        const SizedBox(height: 40),
      ],
    );

    // 没有材料时走原布局
    if (materialText.isEmpty) {
      return Column(children: [Expanded(child: qaSection)]);
    }

    if (_isSplitHorizontal) {
      // 左右分屏：材料左 | 题目+答题右
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(flex: 4, child: Padding(
            padding: const EdgeInsets.all(8),
            child: materialSection,
          )),
          Container(width: 3, color: Colors.grey.shade200),
          Expanded(flex: 5, child: Padding(
            padding: const EdgeInsets.all(8),
            child: qaSection,
          )),
        ]),
      );
    } else {
      // 上下分屏：材料上 | 题目+答题下
      return Column(children: [
        SizedBox(
          height: 280,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: materialSection,
          ),
        ),
        Container(height: 2, color: Colors.grey.shade200),
        Expanded(child: qaSection),
      ]);
    }
  }

  

  Widget _buildQuestionCardWithToolbar(String text) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('📋 题目', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCC3333))),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() { _qEditMode = !_qEditMode; _qTool = 'none'; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _qEditMode ? const Color(0xFFE94560) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_qEditMode ? '退出标注' : '标注', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: _qEditMode ? Colors.white : const Color(0xFF333333))),
          ),
        ),
        if (_qEditMode) ...[
          _qToolBtn2('🖊️', 'pen'), _qToolBtn2('🟡', 'yellow'), _qToolBtn2('🔴', 'red'),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: (_qStrokes.isNotEmpty || _qHighlights.isNotEmpty) ? () { setState(() { _qStrokes.clear(); _qHighlights.clear(); _qUndo.clear(); _qCur = null; }); } : null,
            child: Icon(Icons.delete_outline, size: 16, color: (_qStrokes.isNotEmpty || _qHighlights.isNotEmpty) ? const Color(0xFF333333) : Colors.grey.shade300),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: _qUndo.isNotEmpty ? () { setState(() { final a = _qUndo.removeLast(); if (a is _PenAction2) _qStrokes.remove(a.stroke); if (a is _HlAction2) _qHighlights.remove(a.hl); }); } : null,
            child: Icon(Icons.undo, size: 16, color: _qUndo.isNotEmpty ? const Color(0xFF333333) : Colors.grey.shade300),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      if (_qEditMode && _qTool == 'pen')
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCC3333).withOpacity(0.3))),
          child: Listener(
            onPointerDown: (e) { _qCur = _Stroke(const Color(0xCCE94560)); _qCur!.points.add(e.localPosition); setState(() {}); },
            onPointerMove: (e) {
              if (_qCur == null) return;
              final dx = (e.localPosition.dx - _qCur!.points.first.dx).abs();
              final dy = (e.localPosition.dy - _qCur!.points.first.dy).abs();
              if (dx >= dy || _qCur!.points.length > 1) { _qCur!.points.add(e.localPosition); setState(() {}); }
            },
            onPointerUp: (e) { if (_qCur != null && _qCur!.points.length > 1) { _qStrokes.add(_qCur!); _qUndo.add(_PenAction2(_qCur!)); } _qCur = null; setState(() {}); },
            child: CustomPaint(
              foregroundPainter: _MatAnnotationPainter(_qStrokes, _qCur, _qHighlights, const []),
              child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.6)),
            ),
          ),
        )
      else if (_qEditMode && (_qTool == 'yellow' || _qTool == 'red'))
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCC3333).withOpacity(0.3))),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) { final c = _qTool == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700); _qHighlights.add(_Highlight(d.localPosition.dx - 50, d.localPosition.dy - 12, 100, 24, c)); _qUndo.add(_HlAction2(_qHighlights.last)); setState(() {}); },
            child: CustomPaint(
              foregroundPainter: _MatAnnotationPainter(_qStrokes, _qCur, _qHighlights, const []),
              child: SelectableText(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.6)),
            ),
          ),
        )
      else
        Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCC3333).withOpacity(0.3))), child: SelectableText(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.6))),
    ]);
  }

  Widget _toolBtn(String icon, String mode, String current, void Function(String) onTap) {
    final active = current == mode;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: Container(width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: active ? const Color(0xFFFFF0F0) : Colors.transparent, borderRadius: BorderRadius.circular(6), border: active ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null), child: Center(child: Text(icon, style: TextStyle(fontSize: active ? 13 : 11))),
    ));
  }

  Widget _qToolBtn2(String icon, String mode) {
    final active = _qTool == mode;
    return GestureDetector(
      onTap: () => setState(() => _qTool = active ? 'none' : mode),
      child: Container(width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: active ? const Color(0xFFFFF0F0) : Colors.transparent, borderRadius: BorderRadius.circular(6), border: active ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null), child: Center(child: Text(icon, style: TextStyle(fontSize: active ? 13 : 11))),
    ));
  }

Widget _qToolBtn(String icon, String mode) {
    final active = _qTool == mode;
    return GestureDetector(
      onTap: () => setState(() => _qTool = active ? 'none' : mode),
      child: Container(
        width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF0F0) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null,
        ),
        child: Center(child: Text(icon, style: TextStyle(fontSize: active ? 13 : 11))),
      ),
    );
  }

  Widget _buildAnnotatableCard(String text, bool isMaterial) {
    if (_materialTool == 'none') return _buildMaterialCard(text);

    // 笔工具：Listener 放在 ScrollView 内部，让笔画跟随内容滚动；只记录水平移动
    if (_materialTool == 'pen') {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE94560).withOpacity(0.5)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Listener(
            onPointerDown: (e) {
              _matCur = _Stroke(const Color(0xCCE94560));
              _matCur!.points.add(e.localPosition);
              setState(() {});
            },
            onPointerMove: (e) {
              if (_matCur == null) return;
              final dx = (e.localPosition.dx - _matCur!.points.first.dx).abs();
              final dy = (e.localPosition.dy - _matCur!.points.first.dy).abs();
              // 只记录水平为主的移动，垂直的留给滚动
              if (dx >= dy || _matCur!.points.length > 1) {
                _matCur!.points.add(e.localPosition);
                setState(() {});
              }
            },
            onPointerUp: (e) {
              if (_matCur != null && _matCur!.points.length > 1) {
                _matStrokes.add(_matCur!);
                _matUndo.add(_PenAction2(_matCur!));
              }
              _matCur = null;
              setState(() {});
            },
            child: CustomPaint(
              foregroundPainter: _MatAnnotationPainter(_matStrokes, _matCur, _matHighlights, const []),
              child: Text(text, style: const TextStyle(fontSize: 14, height: 1.8)),
            ),
          ),
        ),
      );
    }
    // 高亮工具：只拦截 tap
    if (_materialTool == 'yellow' || _materialTool == 'red') {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              final c = _materialTool == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700);
              _matHighlights.add(_Highlight(d.localPosition.dx - 50, d.localPosition.dy - 12, 100, 24, c));
              _matUndo.add(_HlAction2(_matHighlights.last));
              setState(() {});
            },
            child: CustomPaint(
              foregroundPainter: _MatAnnotationPainter(_matStrokes, _matCur, _matHighlights, const []),
              child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.8)),
            ),
          ),
        ),
      );
    }
    return _buildMaterialCard(text);
  }

  Widget _buildMaterialCard(String text) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.8)),
      ),
    );
  }

  Widget _buildQuestionCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCC3333).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.quiz_outlined, size: 16, color: Color(0xFFCC3333)),
          SizedBox(width: 6),
          Text('📋 题目', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCC3333))),
        ]),
        const SizedBox(height: 8),
        SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.7)),
      ]),
    );
  }

  Widget _buildOutlineFields() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('总论点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFCC3333))),
        const SizedBox(height: 6),
        SizedBox(
          height: 60,
          child: TextField(
            controller: _mainArgumentController,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, height: 1.6),
            decoration: InputDecoration(
              hintText: '输入你的中心论点…',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('分论点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFCC3333))),
          const Spacer(),
          if (_subArgumentControllers.length < 4)
            GestureDetector(
              onTap: () => setState(() => _subArgumentControllers.add(TextEditingController())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('+ 添加', style: TextStyle(fontSize: 11, color: Color(0xFF4ECDC4))),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        ...List.generate(_subArgumentControllers.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text('${i+1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE94560)))),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _subArgumentControllers[i],
                  maxLines: 2,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  decoration: InputDecoration(
                    hintText: '分论点 ${i+1}…',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                ),
              ),
            ),
            if (_subArgumentControllers.length > 1)
              GestureDetector(
                onTap: () => setState(() { _subArgumentControllers[i].dispose(); _subArgumentControllers.removeAt(i); }),
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
          ]),
        )),
      ]),
    );
  }

  Widget _buildAnswerSheet() {
    final wordLimit = _question?['word_limit'] is int ? _question!['word_limit'] as int : int.tryParse('${_question?['word_limit'] ?? ''}');
    final isEssay = widget.questionType.contains('文章论述') || widget.questionType.contains('大作文');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCC3333), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 表头
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFCC3333), width: 1))),
          child: Row(children: [
            const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFFCC3333)),
            const SizedBox(width: 6),
            const Text('作答区域', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFCC3333))),
            const Spacer(),
            // 大作文：框架模式切换
            if (isEssay)
              GestureDetector(
                onTap: () => setState(() => _outlineMode = !_outlineMode),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _outlineMode ? const Color(0xFF4ECDC4) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_outlineMode ? '框架' : '全文', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: _outlineMode ? Colors.white : Colors.grey.shade700)),
                ),
              ),
            _buildCharCounter(wordLimit),
            // OCR 识图按钮
            if (!_submitted)
              GestureDetector(
                onTap: _ocrLoading ? null : _pickAndOcr,
                child: Container(
                  width: 32, height: 32,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: _ocrLoading ? Colors.grey.shade200 : const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _ocrLoading ? Colors.grey.shade300 : const Color(0xFFCC3333).withOpacity(0.4)),
                  ),
                  child: _ocrLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt_outlined, size: 16, color: Color(0xFFCC3333)),
                ),
              ),
          ]),
        ),
        // 答题区
        if (_outlineMode) _buildOutlineFields() else AnswerEditor(key: _editorKey, controller: _answerController, readOnly: _submitted),
        // 底部字数进度
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFCC3333), width: 0.5))),
          child: _buildWordProgressBar(wordLimit),
        ),
      ]),
    );
  }

  Widget _buildCharCounter(int? wordLimit) {
    final count = _charCount;
    final Color counterColor;
    if (wordLimit == null) {
      counterColor = const Color(0xFF333333);
    } else if (count > wordLimit) {
      counterColor = const Color(0xFFE94560);
    } else if (count >= wordLimit * 0.8) {
      counterColor = const Color(0xFFF9CA24);
    } else {
      counterColor = const Color(0xFF4ECDC4);
    }
    
    return RichText(
      text: TextSpan(children: [
        TextSpan(text: '$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: counterColor)),
        if (wordLimit != null)
          TextSpan(text: ' / $wordLimit 字', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _buildWordProgressBar(int? wordLimit) {
    if (wordLimit == null || wordLimit == 0) {
      return const Text('无字数限制', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    
    final ratio = (_charCount / wordLimit).clamp(0.0, 1.2);
    final Color barColor;
    final String tip;
    if (ratio > 1.0) {
      barColor = const Color(0xFFE94560);
      tip = '已超出 ${_charCount - wordLimit} 字';
    } else if (ratio >= 0.8) {
      barColor = const Color(0xFFF9CA24);
      tip = '即将达到字数上限';
    } else if (ratio >= 0.5) {
      barColor = const Color(0xFF4ECDC4);
      tip = '字数适中';
    } else {
      barColor = Colors.grey.shade300;
      tip = '还需 ${wordLimit - _charCount} 字';
    }
    
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 18,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: barColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(tip, style: TextStyle(fontSize: 11, color: barColor)),
            const SizedBox(width: 12),
            // 100字刻度标记
            ...List.generate(wordLimit ~/ 100 + 1, (i) {
              final m = (i + 1) * 100;
              if (m > wordLimit) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text('|$m', style: TextStyle(fontSize: 8, color: _charCount >= m ? barColor : Colors.grey.shade300)),
              );
            }),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════
  // 要点答题 UI
  // ═══════════════════════════════════════════

  Widget _buildOutlineInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 总论点
        const Text('总论点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCC3333))),
        const SizedBox(height: 6),
        TextField(
          controller: _mainArgumentController,
          readOnly: _submitted,
          maxLines: 3,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: InputDecoration(
            hintText: '请输入您的总论点...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCC3333))),
          ),
        ),
        const SizedBox(height: 16),
        // 分论点
        Row(children: [
          const Text('分论点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCC3333))),
          const Spacer(),
          if (!_submitted)
            GestureDetector(
              onTap: () => setState(() => _subArgumentControllers.add(TextEditingController())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 14, color: Color(0xFF4ECDC4)),
                  Text('添加', style: TextStyle(fontSize: 11, color: Color(0xFF4ECDC4), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        ...List.generate(_subArgumentControllers.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24, height: 24,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(color: const Color(0xFFCC3333).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFCC3333)))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _subArgumentControllers[i],
                  readOnly: _submitted,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  decoration: InputDecoration(
                    hintText: '分论点 ${i + 1}...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCC3333))),
                  ),
                ),
              ),
              if (_subArgumentControllers.length > 3 && !_submitted)
                GestureDetector(
                  onTap: () {
                    _subArgumentControllers[i].dispose();
                    setState(() => _subArgumentControllers.removeAt(i));
                  },
                  child: Container(
                    width: 28, height: 28,
                    margin: const EdgeInsets.only(top: 10, left: 4),
                    decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.remove, size: 16, color: Color(0xFFE94560)),
                  ),
                ),
            ]),
          );
        }),
      ]),
    );
  }

  Future<void> _submitOutline() async {
    final mainArg = _mainArgumentController.text.trim();
    if (mainArg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入总论点')));
      return;
    }
    final subArgs = _subArgumentControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (subArgs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少填写一个分论点')));
      return;
    }

    setState(() => _scoring = true);

    final q = _question!;
    final content = (q['content'] as String?) ?? '';
    final scoreHint = q['score_hint'] as String?;
    final (_, questionText) = _splitContent(content, isEssay: true);
    final materialText = _extractMaterial(content);

    final apiKey = await _db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在「我的」页面设置 DeepSeek API Key')));
        setState(() => _scoring = false);
      }
      return;
    }

    final result = await AIScorer.scoreOutline(
      apiKey: apiKey,
      mainArgument: mainArg,
      subArguments: subArgs,
      questionText: questionText,
      materialText: materialText,
      scoreHint: scoreHint,
    );

    if (mounted) {
      if (result != null) {
        setState(() {
          _submitted = true;
          _outlineResult = result;
          _scoring = false;
        });
        // 保存记录
        final argsText = '总论点：$mainArg\n${subArgs.asMap().entries.map((e) => '分论点${e.key + 1}：${e.value}').join('\n')}';
        _db.savePracticeRecord({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'question_id': widget.questionId,
          'user_answer': argsText,
          'score': result.score,
          'score_breakdown': '要点答题模式',
          'suggestions': result.suggestion,
          'scoring_mode': 'ai',
          'practice_mode': widget.questionType,
          'created_at': DateTime.now().toIso8601String(),
        });
        _db.updateUserStats(addPractice: 1, lastDate: DateTime.now().toIso8601String().substring(0, 10));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 评分失败，请检查网络和 API Key')));
        setState(() => _scoring = false);
      }
    }
  }

  Widget _buildOutlineScoreCard() {
    final r = _outlineResult!;
    final ratio = r.score / r.totalScore;
    final Color color;
    final String emoji;
    if (ratio >= 0.8) { color = const Color(0xFF4ECDC4); emoji = '🎉'; }
    else if (ratio >= 0.6) { color = const Color(0xFFA29BFE); emoji = '👍'; }
    else if (ratio >= 0.4) { color = const Color(0xFFF9CA24); emoji = '📝'; }
    else { color = const Color(0xFFE94560); emoji = '💪'; }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 袁东总分
        Center(child: Text(emoji, style: const TextStyle(fontSize: 36))),
        const SizedBox(height: 6),
        Center(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${r.score}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: color)),
            Text(' / ${r.totalScore} 分', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          ]),
        ),
        const SizedBox(height: 4),
        Center(child: Text('袁东标准评分', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
        // 分项分
        if (r.breakdown.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...r.breakdown.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 40, child: Text(e.key, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.value / r.totalScore,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 28, child: Text('${e.value}', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
            ]),
          )),
        ],
        const Divider(height: 24),
        // 四位名师评析
        const Text('名师评析', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ..._teacherLabels.map((teacher) {
          final analysis = r.analyses[teacher] ?? '';
          if (analysis.isEmpty) return const SizedBox.shrink();
          final tColor = _teacherColor(teacher);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: tColor, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: tColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(teacher, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tColor)),
                ),
                const SizedBox(width: 8),
                Text(_teacherStyle(teacher), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 8),
              Text(analysis, style: const TextStyle(fontSize: 13, height: 1.6)),
            ]),
          );
        }),
        // 综合建议
        if (r.suggestion.isNotEmpty) ...[
          const Divider(height: 24),
          const Row(children: [
            Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFF9CA24)),
            SizedBox(width: 6),
            Text('综合建议', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.3)),
            ),
            child: Text(r.suggestion, style: const TextStyle(fontSize: 13, height: 1.7)),
          ),
        ],
      ]),
    );
  }

  Widget _buildScoreCard() {
    final r = _scoreResult!;
    final ratio = r.score / r.totalScore;
    final Color color;
    final String emoji;
    if (ratio >= 0.8) { color = const Color(0xFF4ECDC4); emoji = '🎉'; }
    else if (ratio >= 0.6) { color = const Color(0xFFA29BFE); emoji = '👍'; }
    else if (ratio >= 0.4) { color = const Color(0xFFF9CA24); emoji = '📝'; }
    else { color = const Color(0xFFE94560); emoji = '💪'; }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${r.score}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: color)),
          Text(' / ${r.totalScore} 分', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        Text(r.feedback, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        // Dimension breakdown
        if (r.breakdown.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...r.breakdown.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 40, child: Text(e.key, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.value / r.totalScore,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      e.key == '扣分' ? const Color(0xFFE94560) : color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: Text('${e.value}', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: e.key == '扣分' ? const Color(0xFFE94560) : color)),
              ),
            ]),
          )),
        ],
        if (r.details.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(r.details, style: const TextStyle(fontSize: 13, height: 1.6)),
          ),
        ],
        if (r.weaknesses.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE94560).withOpacity(0.15)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE94560)),
                SizedBox(width: 6),
                Text('不足之处', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFE94560))),
              ]),
              const SizedBox(height: 8),
              ...r.weaknesses.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('• ', style: TextStyle(fontSize: 13, color: Color(0xFFCC3333))),
                  Expanded(child: Text(w, style: const TextStyle(fontSize: 13, height: 1.5))),
                ]),
              )),
            ]),
          ),
        ],
        // ── 五位名师评析（AI评分时展示）──
        if (r.analyses.isNotEmpty && r.analyses.values.any((a) => a.isNotEmpty)) ...[
          const SizedBox(height: 14),
          const Divider(),
          const Text('名师评析', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ..._teacherLabels.map((teacher) {
            final analysis = r.analyses[teacher] ?? '';
            if (analysis.isEmpty) return const SizedBox.shrink();
            final tColor = _teacherColor(teacher);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: tColor, width: 3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: tColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(teacher, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tColor)),
                  ),
                  const SizedBox(width: 8),
                  Text(_teacherStyle(teacher), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ]),
                const SizedBox(height: 8),
                Text(analysis, style: const TextStyle(fontSize: 13, height: 1.6)),
              ]),
            );
          }),
        ],
        // ── 五位名师参考答案（AI评分时生成）──
        if (r.modelAnswers.isNotEmpty && r.modelAnswers.values.any((a) => a.isNotEmpty)) ...[
          const SizedBox(height: 14),
          const Divider(),
          const Text('📝 名师参考答案', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ..._teacherLabels.where((t) => (r.modelAnswers[t] ?? '').isNotEmpty).map((teacher) {
            final answer = r.modelAnswers[teacher] ?? '';
            final tColor = _teacherColor(teacher);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tColor.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tColor.withOpacity(0.15)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: tColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(teacher, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tColor)),
                  ),
                  const SizedBox(width: 8),
                  Text(_teacherStyle(teacher), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14, color: Colors.grey),
                    tooltip: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: answer));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制$teacher参考答案'), duration: const Duration(seconds: 1)));
                    },
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ]),
                const SizedBox(height: 8),
                SelectableText(answer, style: const TextStyle(fontSize: 13, height: 1.7)),
              ]),
            );
          }),
        ],
        // ── 综合建议 ──
        if (r.suggestion.isNotEmpty) ...[
          const Divider(height: 24),
          const Row(children: [
            Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFF9CA24)),
            SizedBox(width: 6),
            Text('综合建议', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.3)),
            ),
            child: Text(r.suggestion, style: const TextStyle(fontSize: 13, height: 1.7)),
          ),
        ],
      ]),
    );
  }

  /// ── 名师答案解析与展示 ──
  static const _teacherLabels = ['白鹭', '飞扬', '小马哥', '袁东', '忠政'];

  Map<String, String> _parseTeacherAnswers(String fullAnswer) {
    final result = <String, String>{};
    for (final label in _teacherLabels) {
      final pattern = RegExp('【' + label + '参考答案】\\s*\\n?');
      final match = pattern.firstMatch(fullAnswer);
      if (match != null) {
        final start = match.end;
        final nextPattern = RegExp(r'【(?:白鹭|飞扬|小马哥|袁东)参考答案】');
        final nextMatch = nextPattern.firstMatch(fullAnswer.substring(start));
        final end = nextMatch != null ? start + nextMatch.start : fullAnswer.length;
        result[label] = fullAnswer.substring(start, end).trim();
      }
    }
    return result;
  }

  bool _isTemplateAnswer(String answer) {
    return answer.contains('此为AI生成的参考答案模板') ||
           answer.contains('此为AI生成的参考答案框架') ||
           answer.startsWith('【综合参考答案】');
  }

  bool _hasRealAnswers() {
    return _teacherAnswers.values.any((a) => a.isNotEmpty && !_isTemplateAnswer(a));
  }

  Color _teacherColor(String name) {
    switch (name) {
      case '白鹭': return const Color(0xFF4ECDC4);
      case '飞扬': return const Color(0xFFA29BFE);
      case '小马哥': return const Color(0xFFE94560);
      case '袁东': return const Color(0xFF1A1A2E);
      default: return Colors.grey;
    }
  }

  String _teacherStyle(String name) {
    switch (name) {
      case '白鹭': return '紧贴材料·原文提取';
      case '飞扬': return '五大原则·系统框架';
      case '小马哥': return '材料是爹·找大哥';
      case '袁东': return '化大为小·规范表达';
      default: return '';
    }
  }

  Widget _buildCompareTabs(String referenceAnswer) {
    final userAnswer = _answerController.text;
    final r = _scoreResult!;
    final isAI = r.analyses.isNotEmpty || r.suggestion.isNotEmpty;

    return DefaultTabController(
      length: isAI ? 3 : 2,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          TabBar(
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFE94560),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: '我的答案'),
              const Tab(text: '参考答案'),
              if (isAI) const Tab(text: 'AI 建议'),
            ],
          ),
          SizedBox(
            height: 300,
            child: TabBarView(children: [
              // Tab 1: 我的答案
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  userAnswer.isEmpty ? '（未作答）' : userAnswer,
                  style: const TextStyle(fontSize: 14, height: 1.8),
                ),
              ),
              // Tab 2: 参考答案
              referenceAnswer.isNotEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(referenceAnswer, style: const TextStyle(fontSize: 14, height: 1.8)),
                    )
                  : const Center(child: Text('暂无参考答案', style: TextStyle(color: Colors.grey))),
              // Tab 3: AI 建议
              if (isAI)
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (r.suggestion.isNotEmpty) ...[
                      const Text('📝 综合建议', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(r.suggestion, style: const TextStyle(fontSize: 13, height: 1.7)),
                    ],
                    if (r.analyses.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('👨‍🏫 名师评析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...r.analyses.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE94560))),
                          const SizedBox(height: 2),
                          Text(e.value, style: const TextStyle(fontSize: 13, height: 1.6)),
                        ]),
                      )),
                    ],
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildAIFillCard(String hint) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.4)),
      ),
      child: Column(children: [
        const Icon(Icons.auto_awesome, color: Color(0xFFF9CA24), size: 28),
        const SizedBox(height: 10),
        Text(hint, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFB8860B))),
        const SizedBox(height: 6),
        const Text(
          '选择名师风格，AI 将模仿其答题思路生成答案。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF888888), height: 1.6),
        ),
        const SizedBox(height: 10),
        // ── 名师风格选择 ──
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: _teacherLabels.map((name) {
            final selected = _aiTeacher == name;
            return GestureDetector(
              onTap: () => setState(() => _aiTeacher = name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? _teacherColor(name).withOpacity(0.15) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? _teacherColor(name) : Colors.grey.shade300,
                    width: selected ? 1.5 : 0.5,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(name, style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? _teacherColor(name) : Colors.grey.shade600,
                  )),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Text(_teacherStyle(name), style: TextStyle(fontSize: 9, color: _teacherColor(name).withOpacity(0.7))),
                  ],
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // 框架/全文切换
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('框架', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
          Switch(
            value: _aiFullMode,
            activeColor: const Color(0xFF4ECDC4),
            onChanged: (_) => setState(() => _aiFullMode = !_aiFullMode),
          ),
          const Text('全文', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
        ]),
        if (_aiFilledAnswer.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(_aiFilledAnswer, style: const TextStyle(fontSize: 14, height: 1.8)),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _aiFilling
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_aiFilling ? 'AI 生成中...' : (_aiFullMode ? 'AI 生成全文' : 'AI 生成框架')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF9CA24),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _aiFilling ? null : _aiFillAnswer,
          ),
        ),
      ]),
    );
  }

  /// 获取名师风格的系统提示词
  String _teacherSystemPrompt(String name) {
    switch (name) {
      case '白鹭':
        return '你是申论名师白鹭。你的风格是"紧贴材料·原文提取"：作答时最大限度引用材料原词原句，从材料中直接提取关键信息进行归纳，减少自我发挥，答案几乎每个要点都能在材料中找到原文出处。';
      case '飞扬':
        return '你是申论名师飞扬。你的风格是"五大原则·系统框架"：作答时运用五大原则（针对性——紧扣题目、可行性——措施可落地、系统性——逻辑闭环、时效性——关注最新政策、规范性——语言标准），构建系统化答题框架，层次分明。';
      case '小马哥':
        return '你是申论名师小马哥。你的风格是"材料是爹·找大哥"：一切从材料出发，作答前先找材料的核心观点（大哥），围绕核心观点展开，不凭空发挥。答案简洁有力，直击要点，口语化表达中带着精准。';
      case '袁东':
        return '你是申论名师袁东。你的风格是"化大为小·规范表达"：将复杂的大问题拆解为具体的小要点，逐条规范表达。使用标准的政府工作报告式语言，善用"一是…二是…"、小标题+阐述的结构，严谨工整。';
      case '忠政':
        return '你是申论名师忠政。你的风格是"综合全面·辩证分析"：全面覆盖材料要点，辩证分析问题，既看到成绩也看到不足。答案结构完整，有总有分，语言平实稳健，不偏激不遗漏。';
      default:
        return '你是申论辅导专家，擅长各类申论题型的作答。';
    }
  }

  Future<void> _aiFillAnswer() async {
    final apiKey = await _db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在「我的」页面设置 DeepSeek API Key')),
        );
      }
      return;
    }
    final teacher = _aiTeacher;
    setState(() => _aiFilling = true);

    try {
      final q = _question!;
      final content = (q['content'] as String?) ?? '';
      final isEssay = widget.questionType.contains('大作文') || widget.questionType.contains('文章论述');
      final (_, questionText) = _splitContent(content, isEssay: isEssay);
      final materialText = _extractMaterial(content);
      final styleHint = _teacherStyle(teacher);

      var prompt = '';
      if (isEssay) {
        prompt = _aiFullMode
            ? '请根据以下大作文题目和材料，写一篇完整的参考范文（1000-1200字）。要求：观点鲜明、论证充分、结构完整、语言规范。\n\n题目：$questionText'
            : '请为以下大作文题提供简要的写作思路框架（200-400字），包括：核心论点、3-4个分论点方向、可用的论据素材提示。不要写完整文章。\n\n题目：$questionText';
      } else {
        prompt = '请根据以下题目和材料，写一份参考答案（不超过题目字数要求）。答案要：紧扣材料、条理清晰、语言规范。\n\n题目：$questionText';
      }
      prompt += '\n\n材料：${materialText.length > 2000 ? materialText.substring(0, 2000) : materialText}';

      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': _teacherSystemPrompt(teacher)},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': isEssay ? 600 : 1200,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        final msg = response.statusCode == 401 ? 'API Key 无效，请检查设置'
            : response.statusCode == 429 ? '请求太频繁，请稍后重试'
            : response.statusCode == 503 ? 'DeepSeek 服务繁忙，请稍后重试'
            : 'API 请求失败 (${response.statusCode})';
        throw Exception(msg);
      }

      final data = jsonDecode(response.body);
      final generatedContent = data['choices']?[0]?['message']?['content'] as String?;
      if (generatedContent != null && mounted) {
        setState(() {
          _aiFilledAnswer = generatedContent.trim();
          _teacherAnswers[teacher] = generatedContent.trim();
          _selectedTeacher = teacher;
          _aiFilling = false;
        });
        _db.updatePracticeRecordAiAnswer(widget.questionId, generatedContent.trim());
      } else {
        throw Exception('AI 未返回有效内容，请重试');
      }
    } on http.ClientException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络连接失败，请检查网络后重试'), duration: Duration(seconds: 3)),
        );
        setState(() => _aiFilling = false);
      }
    } catch (e) {
      if (mounted) {
        final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$msg'), duration: const Duration(seconds: 3)),
        );
        setState(() => _aiFilling = false);
      }
    }
  }

  Widget _buildAnswerSection(String answer) {
    // 先解析（如果 _teacherAnswers 为空，说明没有名师标记）
    if (_teacherAnswers.isEmpty) {
      _teacherAnswers = _parseTeacherAnswers(answer);
    }

    // 没有名师标记 → 纯文本展示
    if (_teacherAnswers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4ECDC4)),
            SizedBox(width: 6),
            Text('参考答案', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          SelectableText(answer, style: const TextStyle(fontSize: 14, height: 1.8)),
        ]),
      );
    }

    // 全是模板或空答案 → AI补充按钮
    if (!_hasRealAnswers() || answer.isEmpty || answer.length < 80) {
      return _buildAIFillCard(answer.isEmpty ? '暂缺参考答案' : '答案不完整');
    }

    // 有真实答案 → Tab 切换
    final allLabels = [..._teacherLabels, if (_teacherAnswers.containsKey('AI补充')) 'AI补充'];
    final availableTeachers = allLabels
        .where((t) => _teacherAnswers[t] != null && _teacherAnswers[t]!.isNotEmpty && !_isTemplateAnswer(_teacherAnswers[t]!))
        .toList();
    if (!availableTeachers.contains(_selectedTeacher)) {
      _selectedTeacher = availableTeachers.first;
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4ECDC4)),
            const SizedBox(width: 6),
            const Text('参考答案', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _teacherColor(_selectedTeacher).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _teacherStyle(_selectedTeacher),
                style: TextStyle(fontSize: 10, color: _teacherColor(_selectedTeacher)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: availableTeachers.map((t) {
              final selected = _selectedTeacher == t;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTeacher = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? _teacherColor(t) : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: selected ? null : Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SelectableText(
            _teacherAnswers[_selectedTeacher] ?? '',
            style: const TextStyle(fontSize: 14, height: 1.8),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════
  // OCR 识图
  // ═══════════════════════════════════════════

  Future<void> _pickAndOcr() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFFCC3333)),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Color(0xFFCC3333)),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;

    final xfile = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048);
    if (xfile == null) return;

    setState(() => _ocrLoading = true);

    final apiKey = await _db.getSetting('deepseek_api_key');
    if (apiKey == null || apiKey.isEmpty) {
      setState(() => _ocrLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置 DeepSeek API Key')),
        );
      }
      return;
    }

    final text = await OcrService.extractText(imagePath: xfile.path, apiKey: apiKey);

    setState(() => _ocrLoading = false);

    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能识别到文字，请确保图片清晰且包含文字内容')),
        );
      }
      return;
    }

    if (mounted) _showOcrEditor(text);
  }

  void _showOcrEditor(String initialText) {
    final editCtrl = TextEditingController(text: initialText);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.text_snippet, size: 20, color: Color(0xFFCC3333)),
                const SizedBox(width: 8),
                const Text('识别结果（可编辑）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close, size: 20, color: Colors.grey),
                ),
              ]),
              const SizedBox(height: 4),
              Text('AI 从图片中提取的文字，你可以编辑修改后再填入', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: editCtrl,
                    maxLines: null,
                    autofocus: true,
                    style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF333333)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCC3333)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCC3333),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final edited = editCtrl.text.trim();
                    if (edited.isNotEmpty) {
                      _answerController.text = edited;
                      _answerController.selection = TextSelection.collapsed(offset: edited.length);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('确认填入作答区', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 全屏材料阅读页
class _FullScreenMaterial extends StatefulWidget {
  final String content;
  final String questionTitle;
  const _FullScreenMaterial({required this.content, this.questionTitle = ''});
  @override
  State<_FullScreenMaterial> createState() => _FullScreenMaterialState();
}

class _FullScreenMaterialState extends State<_FullScreenMaterial> {
  bool _editMode = false;
  String _tool = 'none'; // 'none' | 'pen' | 'yellow' | 'red'
  final List<_Stroke> _strokes = [];
  _Stroke? _cur;
  final List<_Highlight> _hls = [];
  final List<_Action2> _undo = [];

  void _undoAct() {
    if (_undo.isEmpty) return;
    final a = _undo.removeLast();
    if (a is _PenAction2) _strokes.remove(a.stroke);
    else if (a is _HlAction2) _hls.remove(a.hl);
    setState(() {});
  }

  void _clear() {
    _strokes.clear(); _hls.clear(); _undo.clear();
    setState(() {});
  }

  void _saveToDownload(BuildContext ctx) async {
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final title = '材料_$ts';
    final fullContent = '【题目】${widget.questionTitle}\n\n${widget.content}';
    await ExportService.saveToDownloadList(title, fullContent);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('已保存到我的下载，前往「我的」→「下载管理」导出'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSavedSnack(BuildContext ctx, String path) {
    final name = path.split('/').last;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('已保存：$name', style: const TextStyle(fontSize: 13)),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
            // 无法直接打开文件夹，给用户路径提示
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(path, style: const TextStyle(fontSize: 11)), duration: const Duration(seconds: 5)),
            );
          },
        ),
      ),
    );
  }

  void _removed() {}

  Future<void> _addNote(Offset pos) async {
    // 批注功能已移除
  }

  @override
  Widget build(BuildContext context) {
    final hasAnnotations = _strokes.isNotEmpty || _hls.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读材料'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: [
        GestureDetector(
          onTap: () => setState(() => _editMode = !_editMode),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _editMode ? const Color(0xFFE94560) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _editMode ? '退出编辑' : '编辑',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: _editMode ? Colors.white : const Color(0xFF333333)),
            ),
          ),
        ),
        if (_editMode) ...[
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _smallBtn('🖊️', 'pen'), _smallBtn('🟡', 'yellow'), _smallBtn('🔴', 'red'),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.undo, size: 18),
                      onPressed: _undo.isNotEmpty ? _undoAct : null),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: hasAnnotations ? _clear : null),
                ],
              ),
            ),
          ),
        ],
      ]),
      body: _editMode ? _buildEditView() : _buildReadView(),
    );
  }

  Widget _buildReadView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(widget.content, style: const TextStyle(fontSize: 16, height: 2.0)),
    );
  }

  Widget _buildEditView() {
    final anyTool = _tool != 'none';
    return SingleChildScrollView(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _tool == 'pen' ? (d) { _cur = _Stroke(const Color(0xCCE94560)); _cur!.points.add(d.localPosition); setState(() {}); } : null,
        onHorizontalDragUpdate: _tool == 'pen' ? (d) { _cur?.points.add(d.localPosition); setState(() {}); } : null,
        onHorizontalDragEnd: _tool == 'pen' ? (d) { if (_cur != null && _cur!.points.length > 1) { _strokes.add(_cur!); _undo.add(_PenAction2(_cur!)); } _cur = null; setState(() {}); } : null,
        onTapUp: (_tool == 'yellow' || _tool == 'red') ? (d) {
          final c = _tool == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700);
          final h = _Highlight(d.localPosition.dx - 50, d.localPosition.dy - 12, 100, 24, c);
          _hls.add(h); _undo.add(_HlAction2(h)); setState(() {});
        } : null,
        child: CustomPaint(
          painter: _MatAnnotationPainter(_strokes, _cur, _hls, const []),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: anyTool
                ? Text(widget.content, style: const TextStyle(fontSize: 16, height: 2.0))
                : SelectableText(widget.content, style: const TextStyle(fontSize: 16, height: 2.0)),
          ),
        ),
      ),
    );
  }

  Widget _smallBtn(String icon, String mode) {
    final active = _tool == mode;
    return GestureDetector(
      onTap: () => setState(() => _tool = active ? 'none' : mode),
      child: Container(
        width: 36, height: 36, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF0F0) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null,
        ),
        child: Center(child: Text(icon, style: TextStyle(fontSize: active ? 18 : 15))),
      ),
    );
  }
}

/// 可标注的材料阅读区（内嵌）
class AnnotatableMaterial extends StatefulWidget {
  final String content;
  const AnnotatableMaterial({super.key, required this.content});
  @override
  State<AnnotatableMaterial> createState() => _AnnotatableMaterialState();
}

class _AnnotatableMaterialState extends State<AnnotatableMaterial> {
  bool _editMode = false;
  String _toolMode = 'none'; // 'none' | 'pen' | 'yellow' | 'red' | 'note'
  final List<_Stroke> _strokes = [];
  _Stroke? _cur;
  final List<_Highlight> _hls = [];
  final List<_Note> _notes = [];
  final List<_Action2> _undo = [];

  void _undoAct() {
    if (_undo.isEmpty) return;
    final a = _undo.removeLast();
    if (a is _PenAction2) _strokes.remove(a.stroke);
    else if (a is _HlAction2) _hls.remove(a.hl);
    else if (a is _NoteAction2) _notes.remove(a.note);
    setState(() {});
  }

  void _clear() {
    _strokes.clear(); _hls.clear(); _notes.clear(); _undo.clear();
    setState(() {});
  }

  Future<void> _addNote(Offset pos) async {
    if (!mounted) return;
    try {
      final near = _notes.where((n) => (n.x - pos.dx).abs() < 24 && (n.y - pos.dy).abs() < 24).toList();
      if (near.isNotEmpty) {
        final n = near.first;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('📝 批注'),
            content: SelectableText(n.text, style: const TextStyle(fontSize: 15, height: 1.6)),
            actions: [
              TextButton(
                onPressed: () { _notes.remove(n); Navigator.pop(ctx); if (mounted) setState(() {}); },
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          ),
        );
        return;
      }
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('添加批注'),
          content: TextField(controller: ctrl, autofocus: true, maxLines: 4,
            decoration: const InputDecoration(hintText: '输入批注内容...', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
          ],
        ),
      );
      ctrl.dispose();
      if (result != null && result.trim().isNotEmpty && mounted) {
        _notes.add(_Note(pos.dx, pos.dy, result.trim()));
        _undo.add(_NoteAction2(_notes.last));
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: const Row(children: [
            Text('📖 材料', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE94560))),
          ]),
        ),
        SizedBox(
          height: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(widget.content, style: const TextStyle(fontSize: 14, height: 1.8)),
          ),
        ),
      ]),
    );
  }

  Widget _buildReadView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(widget.content, style: const TextStyle(fontSize: 14, height: 1.8)),
    );
  }

  Widget _buildEditView() {
    final anyTool = _toolMode != 'none';
    return SingleChildScrollView(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _toolMode == 'pen' ? (d) { _cur = _Stroke(const Color(0xCCE94560)); _cur!.points.add(d.localPosition); setState(() {}); } : null,
        onHorizontalDragUpdate: _toolMode == 'pen' ? (d) { _cur?.points.add(d.localPosition); setState(() {}); } : null,
        onHorizontalDragEnd: _toolMode == 'pen' ? (d) { if (_cur != null && _cur!.points.length > 1) { _strokes.add(_cur!); _undo.add(_PenAction2(_cur!)); } _cur = null; setState(() {}); } : null,
        onTapUp: (_toolMode == 'yellow' || _toolMode == 'red') ? (d) {
          final c2 = _toolMode == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700);
          final h = _Highlight(d.localPosition.dx - 40, d.localPosition.dy - 10, 80, 22, c2);
          _hls.add(h); _undo.add(_HlAction2(h)); setState(() {});
        } : _toolMode == 'note' ? (d) { _addNote(d.localPosition); } : null,
        child: CustomPaint(
          painter: _MatAnnotationPainter(_strokes, _cur, _hls, _notes),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: anyTool
                ? Text(widget.content, style: const TextStyle(fontSize: 14, height: 1.8))
                : SelectableText(widget.content, style: const TextStyle(fontSize: 14, height: 1.8)),
          ),
        ),
      ),
    );
  }

  Widget _tb(String i, String m) {
    final a = _toolMode == m;
    return GestureDetector(
      onTap: () => setState(() => _toolMode = a ? 'none' : m),
      child: Container(
        width: 32, height: 32, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: a ? const Color(0xFFFFF0F0) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: a ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null,
        ),
        child: Center(child: Text(i, style: TextStyle(fontSize: a ? 16 : 14))),
      ),
    );
  }

  Widget _icon(IconData i, VoidCallback? cb) {
    return GestureDetector(
      onTap: cb,
      child: Container(
        width: 32, height: 32, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: cb != null ? Colors.grey.shade100 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(i, size: 16, color: cb != null ? const Color(0xFF333333) : Colors.grey.shade300),
      ),
    );
  }
}

// ── Annotation models ──
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

class _Note {
  final double x, y;
  final String text;
  _Note(this.x, this.y, this.text);
}

abstract class _Action2 {}
class _PenAction2 extends _Action2 { final _Stroke stroke; _PenAction2(this.stroke); }
class _HlAction2 extends _Action2 { final _Highlight hl; _HlAction2(this.hl); }
class _NoteAction2 extends _Action2 { final _Note note; _NoteAction2(this.note); }

class _MatAnnotationPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  final List<_Highlight> highlights;
  final List<_Note> notes;
  _MatAnnotationPainter(this.strokes, this.current, this.highlights, this.notes);

  @override
  void paint(Canvas canvas, Size size) {
    try {
      for (final h in highlights) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(h.x, h.y, h.w, h.h), const Radius.circular(3)),
            Paint()..color = h.color..style = PaintingStyle.fill);
      }
      for (final s in strokes) _drawStroke(canvas, s);
      if (current != null) _drawStroke(canvas, current!);
      for (final n in notes) {
        _drawNoteBadge(canvas, n, notes.indexOf(n) + 1);
      }
    } catch (_) {
      // 绘制异常时静默降级，防止渲染崩溃
    }
  }

  void _drawNoteBadge(Canvas canvas, _Note n, int idx) {
    const r = 12.0;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(n.x - r, n.y - r, r * 2, r * 2),
      const Radius.circular(r),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF4ECDC4));
    canvas.drawRRect(badgeRect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final tp = TextPainter(
      text: TextSpan(
        text: '$idx',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(n.x - tp.width / 2, n.y - tp.height / 2));
  }

  void _drawStroke(Canvas canvas, _Stroke s) {
    if (s.points.length < 2) return;
    final p = Paint()..color = s.color..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length; i++) path.lineTo(s.points[i].dx, s.points[i].dy);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// 申论方格答题纸绘制
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFE8D5D5)
      ..strokeWidth = 0.5;

    const cellSize = 24.0;

    // Draw horizontal lines
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      y += cellSize;
    }

    // Draw vertical lines every cell
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      x += cellSize;
    }

    // Red margin line on the left
    final redLine = Paint()
      ..color = const Color(0xFFCC3333)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(16, 0), Offset(16, size.height), redLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 水平拖拽手势识别器 — 只认水平滑动用于标注画线，垂直滑动穿透给滚动视图
class _HorizontalDrawRecognizer extends OneSequenceGestureRecognizer {
  Offset? _startPos;
  bool _isHorizontal = false;

  void Function(Offset pos)? onStart;
  void Function(Offset pos)? onUpdate;
  void Function()? onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _startPos = event.localPosition;
    _isHorizontal = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _startPos != null) {
      final dx = (event.localPosition.dx - _startPos!.dx).abs();
      final dy = (event.localPosition.dy - _startPos!.dy).abs();

      if (!_isHorizontal && (dx > 3 || dy > 3)) {
        // 水平位移 >= 垂直位移 → 画线；否则 → 滚动
        if (dx >= dy) {
          _isHorizontal = true;
          resolve(GestureDisposition.accepted);
          onStart?.call(_startPos!);
        } else {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
        }
      }

      if (_isHorizontal) {
        onUpdate?.call(event.localPosition);
      }
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_isHorizontal) onEnd?.call();
      _startPos = null;
      _isHorizontal = false;
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => '_HorizontalDrawRecognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {
    _startPos = null;
    _isHorizontal = false;
  }
}
