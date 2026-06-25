import 'package:flutter/material.dart';
import '../services/mock_exam_service.dart';
import 'mock_exam_answer_screen.dart';

/// 模拟题 — 生成记录列表 + 历史习题
class MockExamListScreen extends StatefulWidget {
  const MockExamListScreen({super.key});
  @override
  State<MockExamListScreen> createState() => _MockExamListScreenState();
}

class _MockExamListScreenState extends State<MockExamListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<MockExam> _allExams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final exams = await MockExamService.getAll();
    if (mounted) setState(() { _allExams = exams; _loading = false; });
  }

  List<MockExam> get _pending => _allExams.where((e) => e.userAnswer.isEmpty).toList();
  List<MockExam> get _completed => _allExams.where((e) => e.userAnswer.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模拟题'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: const Color(0xFF1A1A2E),
            child: TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: const Color(0xFF4ECDC4),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: '待练习 (${_pending.length})'),
                Tab(text: '已完成 (${_completed.length})'),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildList(_pending, emptyMsg: '暂无待练习的模拟题\n从「重要会议→聚焦重点」生成吧'),
                _buildList(_completed, emptyMsg: '暂无已完成的历史习题'),
              ],
            ),
    );
  }

  Widget _buildList(List<MockExam> exams, {required String emptyMsg}) {
    if (exams.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(emptyMsg, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400, height: 1.5)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: exams.length,
        itemBuilder: (_, i) => _buildCard(exams[i]),
      ),
    );
  }

  Widget _buildCard(MockExam exam) {
    final isCompleted = exam.userAnswer.isNotEmpty;
    final typeColor = _typeColorMap[exam.questionType] ?? const Color(0xFF1A5276);

    return Dismissible(
      key: Key(exam.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除确认'),
            content: const Text('确定删除这份模拟题吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (ok == true) {
          await MockExamService.delete(exam.id);
          _load();
        }
        return false;
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => MockExamAnswerScreen(exam: exam),
            ));
            _load();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // Type indicator
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(isCompleted ? Icons.check_circle : Icons.edit_note, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(exam.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(exam.questionType, style: TextStyle(fontSize: 10, color: typeColor)),
                    ),
                    const SizedBox(width: 8),
                    Text(exam.createdAt, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                  if (isCompleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('已作答${exam.aiAnalysis.isNotEmpty ? ' · 已批改' : ''}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                    ),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ]),
          ),
        ),
      ),
    );
  }
}

const _typeColorMap = {
  '概括归纳题': Color(0xFF4ECDC4),
  '综合分析题': Color(0xFFA29BFE),
  '对策题': Color(0xFFE94560),
  '应用文写作': Color(0xFFFFB347),
  '大作文': Color(0xFF1A1A2E),
  '整套题目': Color(0xFF6C5CE7),
};
