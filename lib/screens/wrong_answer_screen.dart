import 'package:flutter/material.dart';
import '../database/db_helper.dart';

int _parseTotal(String hint) {
  final m = RegExp(r'(\d+)').firstMatch(hint);
  if (m != null) return int.parse(m.group(1)!);
  return 20; // 默认20分
}

class WrongAnswerScreen extends StatefulWidget {
  const WrongAnswerScreen({super.key});
  @override
  State<WrongAnswerScreen> createState() => _WrongAnswerScreenState();
}

class _WrongAnswerScreenState extends State<WrongAnswerScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await _db.database;
      if (db == null) { if (mounted) setState(() => _loading = false); return; }
      // Get records with low scores
      final records = await db.rawQuery('''
        SELECT pr.*, q.title, q.question_type, q.region, q.year, q.score_hint
        FROM practice_records pr
        LEFT JOIN questions q ON pr.question_id = q.id
        WHERE pr.score IS NOT NULL
        ORDER BY pr.created_at DESC LIMIT 200
      ''');
      // 得分低于满分50%的进入错题本
      final wrong = records.where((r) {
        final score = (r['score'] as int?) ?? 0;
        final hint = (r['score_hint'] as String?) ?? '';
        final total = _parseTotal(hint);
        return total > 0 && score < total / 2;
      }).toList();
      if (mounted) setState(() { _records = wrong; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('错题本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('暂无错题记录', style: TextStyle(color: Colors.grey.shade400)),
                  const SizedBox(height: 4),
                  Text('多做练习后这里会显示需要复习的题目', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (_, i) {
                    final r = _records[i];
                    final score = r['score'] as int? ?? 0;
                    return Dismissible(
                      key: Key(r['id']?.toString() ?? '$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除错题记录'),
                            content: const Text('确定删除此错题记录？题目仍保留在题库中。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (result == true) {
                          await _db.deletePracticeRecord(r['id']?.toString() ?? '');
                          _records.removeAt(i);
                          setState(() {});
                          return true;
                        }
                        return false;
                      },
                      child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                            child: Text('$score 分', style: const TextStyle(fontSize: 11, color: Color(0xFFE94560), fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text(r['question_type'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                        const SizedBox(height: 6),
                        Text(r['title'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (r['user_answer'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('你的答案：${r['user_answer']}',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ),
                      ]),
                    ),
                    );
                  },
                ),
    );
  }
}
