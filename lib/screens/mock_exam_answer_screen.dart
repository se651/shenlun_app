import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';
import '../services/mock_exam_service.dart';
import 'answer_editor.dart';

/// 模拟题答题页面 — 查看材料+题目，作答，AI批改
class MockExamAnswerScreen extends StatefulWidget {
  final MockExam exam;
  const MockExamAnswerScreen({super.key, required this.exam});

  @override
  State<MockExamAnswerScreen> createState() => _MockExamAnswerScreenState();
}

class _MockExamAnswerScreenState extends State<MockExamAnswerScreen> {
  late TextEditingController _answerCtrl;
  bool _readOnly = false;
  bool _grading = false;
  String? _errorMsg;
  Map<String, dynamic>? _aiResult;
  bool _showMaterial = true;

  @override
  void initState() {
    super.initState();
    _answerCtrl = TextEditingController(text: widget.exam.userAnswer);
    _readOnly = widget.exam.userAnswer.isNotEmpty && widget.exam.aiAnalysis.isNotEmpty;
    if (_readOnly && widget.exam.aiAnalysis.isNotEmpty) {
      try {
        _aiResult = jsonDecode(widget.exam.aiAnalysis) as Map<String, dynamic>;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先作答')),
      );
      return;
    }
    if (answer.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('答案太短，请至少写20字')),
      );
      return;
    }

    // Save answer first
    await MockExamService.updateAnswer(widget.exam.id, answer);
    widget.exam.userAnswer = answer;

    setState(() => _grading = true);

    final db = DatabaseHelper();
    final apiKey = await db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      setState(() { _grading = false; _errorMsg = '请先设置 DeepSeek API Key'; });
      return;
    }

    try {
      final material = '${widget.exam.material}\n\n${widget.exam.questions}';
      final prompt = '''请批改以下申论模拟题答案：

题目主题：${widget.exam.title}
题型：${widget.exam.questionType}

材料与题目：
$material

考生答案：$answer''';

      final r = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': _gradingSystemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 2000,
        }),
      ).timeout(const Duration(seconds: 45));

      if (!mounted) return;

      if (r.statusCode == 200) {
        final ans = jsonDecode(r.body)['choices'][0]['message']['content'] as String;
        // Parse response
        Map<String, dynamic> parsed;
        try {
          parsed = jsonDecode(ans) as Map<String, dynamic>;
        } catch (_) {
          parsed = {'raw': ans};
        }

        await MockExamService.updateAnalysis(widget.exam.id, jsonEncode(parsed));
        setState(() { _aiResult = parsed; _grading = false; _readOnly = true; });
      } else {
        setState(() { _grading = false; _errorMsg = 'AI 批改请求失败'; });
      }
    } catch (_) {
      if (mounted) {
        setState(() { _grading = false; _errorMsg = '网络错误，请重试'; });
      }
    }
  }

  Future<void> _reAnswer() async {
    setState(() {
      _readOnly = false;
      _aiResult = null;
      _errorMsg = null;
    });
    _answerCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;

    return Scaffold(
      appBar: AppBar(
        title: Text(exam.title),
        actions: [
          if (_readOnly)
            IconButton(icon: const Icon(Icons.refresh), tooltip: '重新作答', onPressed: _reAnswer),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制题目',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '【${exam.questionType}】${exam.title}\n\n${exam.material}\n\n${exam.questions}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制题目'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4ECDC4), Color(0xFF2ECC71)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('AI 模拟题 · ${exam.questionType}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 12),
          Text(exam.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('生成时间：${exam.createdAt}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 20),
          const Divider(),

          // Material section
          const SizedBox(height: 8),
          Row(children: [
            const Text('📄 给定材料', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _showMaterial = !_showMaterial),
              child: Icon(_showMaterial ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
            ),
          ]),
          if (_showMaterial) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SelectableText(
                exam.material,
                style: const TextStyle(fontSize: 14, height: 1.8),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Question section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.assignment, color: Color(0xFF4ECDC4), size: 18),
                SizedBox(width: 6),
                Text('📋 作答要求', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF4ECDC4))),
              ]),
              const SizedBox(height: 8),
              SelectableText(
                exam.questions,
                style: const TextStyle(fontSize: 14, height: 1.8),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // Answer section
          Row(children: [
            const Text('✍️ 我的作答', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (exam.userAnswer.isNotEmpty)
              Text('${exam.userAnswer.length}字', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnswerEditor(controller: _answerCtrl, readOnly: _readOnly),
          ),

          const SizedBox(height: 16),

          // Error message
          if (_errorMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13))),
              ]),
            ),

          // Action buttons
          if (!_readOnly) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _grading ? null : _submit,
                icon: _grading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 20),
                label: Text(_grading ? 'AI 批改中…' : '提交并 AI 批改', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],

          // AI Result
          if (_aiResult != null) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _buildAiResult(_aiResult!),
          ],

          if (_readOnly && _grading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('AI 正在批改…', style: TextStyle(fontSize: 13, color: Colors.grey))),
          ],
        ]),
      ),
    );
  }

  Widget _buildAiResult(Map<String, dynamic> result) {
    if (result.containsKey('raw')) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFFA29BFE).withOpacity(0.08), const Color(0xFFE94560).withOpacity(0.08)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFA29BFE).withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFA29BFE), size: 18),
            const SizedBox(width: 6),
            const Text('AI 综合评分', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFA29BFE))),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result['raw'] ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
              },
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 12),
          SelectableText(result['raw'] ?? '', style: const TextStyle(fontSize: 14, height: 1.9)),
        ]),
      );
    }

    final score = result['score'];
    final feedback = result['feedback'] as String? ?? '';
    final details = result['details'] as String? ?? '';
    final analyses = result['analyses'] as Map<String, dynamic>?;
    final suggestion = result['suggestion'] as String? ?? '';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Score card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          if (score != null)
            Text('$score分', style: const TextStyle(color: Color(0xFFE94560), fontSize: 42, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(feedback, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
        ]),
      ),

      const SizedBox(height: 20),

      // Detailed analysis
      if (details.isNotEmpty) ...[
        _section('📊 详细分析', details),
        const SizedBox(height: 16),
      ],

      // Four-teacher analysis
      if (analyses != null && analyses.isNotEmpty) ...[
        const Text('🎓 名师评析', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...analyses.entries.where((e) => (e.value as String).isNotEmpty).map((e) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _teacherColor(e.key).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _teacherColor(e.key).withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _teacherColor(e.key),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
            const SizedBox(height: 6),
            SelectableText(e.value as String, style: const TextStyle(fontSize: 13, height: 1.7)),
          ]),
        )),
        const SizedBox(height: 16),
      ],

      // Suggestion
      if (suggestion.isNotEmpty) ...[
        _section('💡 改进建议', suggestion),
      ],

      const SizedBox(height: 8),
      Row(children: [
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: jsonEncode(result)));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制完整评析'), duration: Duration(seconds: 1)));
          },
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('复制完整评析', style: TextStyle(fontSize: 12)),
        ),
      ]),
    ]);
  }

  Widget _section(String title, String content) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SelectableText(content, style: const TextStyle(fontSize: 14, height: 1.85)),
    ]);
  }

  Color _teacherColor(String name) {
    switch (name) {
      case '袁东': return const Color(0xFFE94560);
      case '白鹭': return const Color(0xFF4ECDC4);
      case '飞扬': return const Color(0xFFA29BFE);
      case '小马哥': return const Color(0xFFFFB347);
      case '忠政': return const Color(0xFF1A5276);
      default: return const Color(0xFF6C5CE7);
    }
  }
}

const _gradingSystemPrompt = '''你是五位国家公务员考试申论名师组成的评审团。请按照以下分工批改考生的申论模拟题答案：

【袁东老师主评 — 化大为小·规范表达】
采用赋分制（从0分起，逐项加分，不扣分）：
1. 内容质量（40%）：要点覆盖、观点准确、紧扣材料
2. 结构逻辑（30%）：层次分明、有序号标记和层次词
3. 语言表达（20%）：用词精准规范、有政策术语
4. 卷面规范（10%）：字数合理、无明显格式问题
5. 特殊情况：作答少于20字或无实质内容 → 直接给0分

【名师评析 — 五位老师各写一段】
- 袁东：从宏观立意和规范表达角度点评
- 白鹭（紧贴材料·原文提取）：检查是否紧扣材料，指出遗漏要点
- 飞扬（五大原则·系统框架）：从逻辑框架和结构层次角度点评
- 小马哥（材料是爹·找大哥）：从实战得分角度，指出最关键提分点
- 忠政（忠政方法论·三步走）：审题干→读材料→整答案，从五维评分体系点评（材料扣合度、逻辑结构、政策素养、语言规范、完整性），标注材料来源段落位置，给出参考答案框架

请用以下 JSON 格式回复（不要输出其他内容）：
{
  "score": 数字,
  "feedback": "一句话总体评价",
  "details": "从内容、结构、语言、规范四维度逐条分析",
  "analyses": {"袁东": "...", "白鹭": "...", "飞扬": "...", "小马哥": "...", "忠政": "..."},
  "suggestion": "综合改进建议..."
}''';
