import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/db_helper.dart';
import '../services/web_db.dart';
import 'question_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (kIsWeb) {
        final webDb = WebDatabase();
        await webDb.init();
        final allQuestions = await webDb.getQuestions(limit: 9999, offset: 0);
        final favsList = <Map<String, dynamic>>[];
        for (final q in allQuestions) {
          final qid = q['id'] as String;
          if (await webDb.isFavorited(qid)) {
            favsList.add(q);
          }
        }
        if (mounted) setState(() { _questions = favsList; _loading = false; });
      } else {
        final db = await _db.database;
        if (db == null) { if (mounted) setState(() => _loading = false); return; }
        final favs = await db.rawQuery('''
          SELECT q.* FROM questions q INNER JOIN favorites f ON q.id = f.question_id
          WHERE q.is_deleted = 0 ORDER BY f.created_at DESC
        ''');
        if (mounted) setState(() { _questions = favs; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bookmark_border, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('暂无收藏', style: TextStyle(color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  itemBuilder: (_, i) {
                    final q = _questions[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(q['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${q['question_type'] ?? ''} · ${q['region'] ?? ''} ${q['year'] ?? ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => QuestionDetailScreen(
                            questionId: q['id'] as String,
                            questionType: q['question_type'] as String? ?? '',
                          ),
                        )),
                      ),
                    );
                  },
                ),
    );
  }
}
