import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  final _db = DatabaseHelper();
  final _hoursController = TextEditingController(text: '2');
  final _goalController = TextEditingController();
  String? _planResult;
  bool _loading = false;
  Map<String, double> _weaknessData = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _db.getQuestionTypeStats();
      final history = await _db.getPracticeHistory(limit: 200);
      
      // Count practice by type
      final typeCounts = <String, int>{};
      for (final r in history) {
        // Try to get question type from practice record
        final qid = r['question_id'] as String?;
        if (qid != null) {
          final q = await _db.getQuestionById(qid);
          if (q != null) {
            final qt = _simplifyType(q['question_type'] as String? ?? '');
            typeCounts[qt] = (typeCounts[qt] ?? 0) + 1;
          }
        }
      }
      
      // Calculate weakness: lower = weaker (less practiced)
      final types = ['概括归纳', '综合分析', '提出对策', '应用文', '文章论述'];
      final data = <String, double>{};
      final maxCount = typeCounts.values.fold<int>(1, (a, b) => a > b ? a : b);
      for (final t in types) {
        final count = typeCounts[t] ?? 0;
        data[t] = maxCount > 0 ? (count / maxCount).clamp(0.1, 1.0) : 0.5;
      }
      
      if (mounted) setState(() => _weaknessData = data);
    } catch (_) {}
  }

  String _simplifyType(String type) {
    if (type.contains('应用文')) return '应用文';
    if (type.contains('大作文') || type.contains('文章论述')) return '文章论述';
    return type;
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (_goalController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写学习目标')),
      );
      return;
    }

    setState(() => _loading = true);

    // 模拟 AI 生成（Phase 2 接 DeepSeek API）
    await Future.delayed(const Duration(seconds: 2));

    final hours = _hoursController.text;
    final goal = _goalController.text;

    setState(() {
      _loading = false;
      _planResult = _buildMockPlan(hours, goal);
    });
  }

  String _buildMockPlan(String hours, String goal) {
    return '''
📋 申论学习计划

🎯 目标：$goal
⏰ 每日学习时长：$hours 小时

━━━━━━━━━━━━━━━━━━

📅 第一周：基础巩固
  · 概括归纳专项训练（每天 2 题）
  · 规范词背诵（每天 20 个）
  · 时政新闻阅读（每天 1 篇）

📅 第二周：能力提升
  · 综合分析 + 提出对策（每天 2 题）
  · 应用文格式专项（每天 1 篇）
  · 错题回顾（每周 1 次）

📅 第三周：大作文突破
  · 议论文结构训练（每天 1 篇提纲）
  · 优秀范文精读（每天 1 篇）
  · 名言素材积累（每天 5 条）

📅 第四周：模拟冲刺
  · 全真模考（每周 2 次）
  · 弱项针对性补练
  · 时间管理训练

━━━━━━━━━━━━━━━━━━

💡 AI 提示：
根据你的学习目标，建议优先攻克综合分析题型
（该题型在近年考试中占比提升至 28%）。

⚠️ 当前为模拟计划。接入 DeepSeek API 后可获得
基于真实答题数据的个性化弱项分析。
''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 学习计划'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Text('🤖', style: TextStyle(fontSize: 36)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI 智能规划',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('分析弱项，生成个性化学习方案',
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_planResult == null) ...[
                // Input form
                Text('学习设置', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                // Hours input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFF6C5CE7), size: 20),
                      const SizedBox(width: 10),
                      const Text('每日学习', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        child: TextField(
                          controller: _hoursController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const Text('小时', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Goal input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _goalController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '学习目标，如：提升申论大作文写作能力',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Generate button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generatePlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('生成学习计划', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else ...[
                // Show plan result
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF4ECDC4), size: 20),
                          const SizedBox(width: 8),
                          const Text('计划已生成', style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _planResult = null),
                            child: const Text('重新生成'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_planResult!,
                          style: const TextStyle(fontSize: 14, height: 1.7)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Weakness analysis card
              Text('弱项分析', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _buildWeaknessRow('综合分析', 0.45, const Color(0xFFA29BFE)),
                    _buildWeaknessRow('概括归纳', 0.62, const Color(0xFF4ECDC4)),
                    _buildWeaknessRow('提出对策', 0.38, const Color(0xFFF9CA24)),
                    _buildWeaknessRow('应用文', 0.55, const Color(0xFF6C5CE7)),
                    _buildWeaknessRow('大作文', 0.28, const Color(0xFFE94560)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('* 基于练习记录自动计算，数据越多越准确',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeaknessRow(String label, double rate, Color color) {
    final emoji = rate < 0.35 ? '⚠️' : rate < 0.55 ? '📝' : '✅';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: rate, minHeight: 8,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(rate * 100).toInt()}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
