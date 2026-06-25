import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'question_detail_screen.dart';

/// 薄弱点加练 — 根据AI分析的薄弱题型推荐题目
class WeaknessPracticeScreen extends StatefulWidget {
  final List<String> weakTypes;
  const WeaknessPracticeScreen({super.key, required this.weakTypes});

  @override State<WeaknessPracticeScreen> createState() => _WeaknessPracticeScreenState();
}

class _WeaknessPracticeScreenState extends State<WeaknessPracticeScreen> {
  final _db = DatabaseHelper();
  Map<String, List<Map<String, dynamic>>> _questionsByType = {};
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    _questionsByType = {};
    for (final type in widget.weakTypes) {
      // Map to actual query type
      var queryType = type;
      if (type.contains('应用文')) queryType = '应用文写作';
      if (type.contains('大作文') || type.contains('文章')) queryType = '文章论述（大作文）';
      
      final qs = await _db.getQuestions(
        questionTypes: [queryType],
        limit: 8,
      );
      if (qs.isNotEmpty) {
        _questionsByType[queryType] = qs;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openQuestion(Map<String, dynamic> q) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuestionDetailScreen(
        questionId: q['id'] as String,
        questionType: q['question_type'] as String? ?? '',
        skipHistory: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('薄弱点加练'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 弱点分析卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF4A4A6E)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🎯 AI 诊断结果', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    ...widget.weakTypes.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.warning_amber, size: 14, color: Color(0xFFF9CA24)),
                        const SizedBox(width: 8),
                        Text(w, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    )),
                    const SizedBox(height: 8),
                    const Text('以下题目根据你的薄弱点智能推荐，逐一攻破', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 20),
                // 分组题目
                ..._questionsByType.entries.map((entry) {
                  final typeName = entry.key;
                  final qs = entry.value;
                  final color = _typeColor(typeName);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 8),
                        Text(typeName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                        const Spacer(),
                        Text('${qs.length} 题', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                      const SizedBox(height: 10),
                      ...qs.map((q) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openQuestion(q),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Icon(Icons.quiz_outlined, size: 18, color: color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${q['year'] ?? ''} · ${q['region'] ?? ''}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Text('${q['year'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                            ]),
                          ),
                        ),
                      )),
                    ]),
                  );
                }),
                if (_questionsByType.isEmpty)
                  const Center(child: Text('暂无匹配题目', style: TextStyle(color: Colors.grey))),
              ]),
            ),
    );
  }

  Color _typeColor(String type) {
    if (type.contains('概括')) return const Color(0xFF4ECDC4);
    if (type.contains('分析')) return const Color(0xFFA29BFE);
    if (type.contains('对策')) return const Color(0xFFF9CA24);
    if (type.contains('应用文')) return const Color(0xFF6C5CE7);
    if (type.contains('大作文') || type.contains('文章')) return const Color(0xFFE94560);
    return const Color(0xFF1A1A2E);
  }
}
