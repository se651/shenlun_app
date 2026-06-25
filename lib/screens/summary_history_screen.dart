import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class SummaryHistoryScreen extends StatefulWidget {
  const SummaryHistoryScreen({super.key});
  @override
  State<SummaryHistoryScreen> createState() => _SummaryHistoryScreenState();
}

class _SummaryHistoryScreenState extends State<SummaryHistoryScreen> {
  final _db = DatabaseHelper();
  List<_HistoryGroup> _groups = [];
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
      final records = await db.rawQuery('''
        SELECT * FROM practice_records
        WHERE practice_mode LIKE 'summary_exercise_%'
           OR practice_mode = 'commentary_exercise'
        ORDER BY created_at DESC LIMIT 300
      ''');
      // 按 practice_mode 分组
      final map = <String, List<Map<String, dynamic>>>{};
      for (final r in records) {
        final mode = (r['practice_mode'] as String?) ?? '其他';
        final label = _modeLabel(mode);
        map.putIfAbsent(label, () => []).add(r);
      }
      if (mounted) setState(() {
        _groups = map.entries.map((e) => _HistoryGroup(type: e.key, records: e.value)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'summary_exercise_概括': return '概括';
      case 'summary_exercise_对策': return '对策';
      case 'summary_exercise_概括回复': return '概括回复';
      case 'commentary_exercise': return '简评';
      default: return mode;
    }
  }

  Color _modeColor(String label) {
    switch (label) {
      case '概括': return const Color(0xFF4ECDC4);
      case '对策': return const Color(0xFFE94560);
      case '概括回复': return const Color(0xFFA29BFE);
      case '简评': return const Color(0xFFF9CA24);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('概括·简评 练习历史')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('暂无练习记录', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Text('完成概括分析与简评练习后，记录会出现在这里', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) {
                    final g = _groups[i];
                    final color = _modeColor(g.type);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(g.type, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                          ),
                          const SizedBox(width: 8),
                          Text('${g.records.length} 次练习', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ]),
                        const SizedBox(height: 8),
                        ...g.records.asMap().entries.map((e) {
                          final idx = e.key;
                          final r = e.value;
                          final answer = (r['user_answer'] as String?) ?? '';
                          final score = r['score'];
                          final suggestions = (r['suggestions'] as String?) ?? '';
                          final date = (r['created_at'] as String?) ?? '';
                          final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                              title: Row(children: [
                                if (score != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (score is int && score >= 70) ? const Color(0xFF4ECDC4).withOpacity(0.15) : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('$score 分', style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700,
                                      color: (score is int && score >= 70) ? const Color(0xFF4ECDC4) : Colors.orange,
                                    )),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    '$dateStr · 第${g.records.length - idx}次',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                ),
                                if (suggestions.isNotEmpty)
                                  Text(suggestions, style: TextStyle(fontSize: 11, color: Colors.grey.shade400), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                              children: [
                                if (answer.isNotEmpty) ...[
                                  const Divider(),
                                  const Text('作答内容', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: SelectableText(answer, style: const TextStyle(fontSize: 14, height: 1.6)),
                                  ),
                                ],
                                if (suggestions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFA29BFE).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('评分', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFA29BFE))),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(suggestions, style: const TextStyle(fontSize: 13, height: 1.5))),
                                  ]),
                                ],
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    onTap: () => _deleteOne(e.key),
                                    child: Text('删除', style: TextStyle(fontSize: 11, color: Colors.red.shade300)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ]),
                    );
                  },
                ),
    );
  }

  Future<void> _deleteOne(int groupIndex) async {
    // Find the record to delete
    if (groupIndex >= _groups.length) return;
    final g = _groups[groupIndex];
    if (g.records.isEmpty) return;
    final record = g.records.first;
    final id = record['id'] as String?;
    if (id == null) return;
    await _db.deletePracticeRecord(id);
    _load();
  }
}

class _HistoryGroup {
  final String type;
  final List<Map<String, dynamic>> records;
  _HistoryGroup({required this.type, required this.records});
}
