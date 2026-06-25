import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'paper_practice_screen.dart';

/// 套卷库 — 全部/历史/收藏 三栏
class PaperLibraryScreen extends StatefulWidget {
  final String initialTab; // 'all' | 'history' | 'favorites'
  final String filter; // '全部' | '国考' | '省考' | '选调生'
  const PaperLibraryScreen({super.key, this.initialTab = 'all', this.filter = '全部'});

  @override State<PaperLibraryScreen> createState() => _PaperLibraryScreenState();
}

class _PaperLibraryScreenState extends State<PaperLibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _allPapers = [];
  List<Map<String, dynamic>> _historyPapers = [];
  List<Map<String, dynamic>> _favPapers = [];
  bool _loadingAll = true;
  bool _loadingHistory = true;
  bool _loadingFav = true;

  @override void initState() {
    super.initState();
    final idx = {'all': 0, 'history': 1, 'favorites': 2}[widget.initialTab] ?? 0;
    _tab = TabController(length: 3, vsync: this, initialIndex: idx);
    _loadAll();
    _loadHistory();
    _loadFavorites();
  }

  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadAll() async {
    setState(() => _loadingAll = true);
    final f = widget.filter;
    if (f == '选调生') {
      _allPapers = await _db.getPaperList(examCategory: '选调生');
    } else {
      _allPapers = await _db.getPaperList(
        region: f == '国考' ? '国家' : (f == '省考' ? '省考' : null),
      );
    }
    if (mounted) setState(() => _loadingAll = false);
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final ids = await _db.getPaperHistory();
    if (ids.isNotEmpty) {
      _historyPapers = await _db.getPaperListByIds(ids);
      // Sort by history order
      final idOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      _historyPapers.sort((a, b) {
        final ai = idOrder[a['paper_id']] ?? 999;
        final bi = idOrder[b['paper_id']] ?? 999;
        return ai.compareTo(bi);
      });
    } else {
      _historyPapers = [];
    }
    if (mounted) setState(() => _loadingHistory = false);
  }

  Future<void> _loadFavorites() async {
    setState(() => _loadingFav = true);
    final ids = await _db.getPaperFavorites();
    if (ids.isNotEmpty) {
      _favPapers = await _db.getPaperListByIds(ids);
      final idOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      _favPapers.sort((a, b) => (idOrder[a['paper_id']] ?? 999).compareTo(idOrder[b['paper_id']] ?? 999));
    } else {
      _favPapers = [];
    }
    if (mounted) setState(() => _loadingFav = false);
  }

  void _startPaper(Map<String, dynamic> p) async {
    final questions = await _db.getPaperQuestions(p['paper_id'] as String);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PaperPracticeScreen(
        questions: questions,
        paperName: p['paper_title'] as String? ?? '${p['year']} ${p['region']}',
        paperId: p['paper_id'] as String,
      ),
    )).then((_) => _loadHistory());
  }

  void _deleteFromHistory(Map<String, dynamic> p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除历史'),
        content: Text('将 "${_paperLabel(p)}" 从历史记录中移除？\n\n移除后可在全部套卷中重新找到。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
            onPressed: () async {
              await _db.removePaperFromHistory(p['paper_id'] as String);
              Navigator.pop(ctx);
              _loadHistory();
              _loadAll();
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite(Map<String, dynamic> p) async {
    await _db.togglePaperFavorite(p['paper_id'] as String);
    _loadFavorites();
    _loadAll();
  }

  String _paperLabel(Map<String, dynamic> p) {
    final year = p['year'] ?? '';
    final region = p['region'] ?? '';
    final subtype = (p['exam_subtype'] as String?) ?? '';
    return '$year $region${subtype.isNotEmpty ? ' $subtype' : ''}';
  }

  String _typeAbbr(String t) {
    const abbr = {'概括归纳': '概括', '综合分析': '分析', '提出对策': '对策', '应用文写作': '应用文', '文章论述（大作文）': '大作文'};
    return abbr[t] ?? t;
  }

  @override
  void didUpdateWidget(PaperLibraryScreen old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) {
      _loadAll();
      _loadHistory();
      _loadFavorites();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(
        controller: _tab,
        labelColor: const Color(0xFFE94560),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color(0xFFE94560),
        tabs: const [
          Tab(text: '全部'),
          Tab(text: '历史'),
          Tab(text: '收藏'),
        ],
      ),
      Expanded(child: TabBarView(
        controller: _tab,
        children: [
          _buildTab(_allPapers, _loadingAll, isHistory: false, isFav: false),
          _buildTab(_historyPapers, _loadingHistory, isHistory: true, isFav: false),
          _buildTab(_favPapers, _loadingFav, isHistory: false, isFav: true),
        ],
      )),
    ]);
  }

  Widget _buildTab(List<Map<String, dynamic>> papers, bool loading, {required bool isHistory, required bool isFav}) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (papers.isEmpty) return Center(child: Text(isHistory ? '暂无历史记录' : isFav ? '暂无收藏' : '暂无试卷', style: TextStyle(color: Colors.grey.shade400)));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: papers.length,
      itemBuilder: (_, i) {
        final p = papers[i];
        final label = _paperLabel(p);
        final count = p['question_count'];
        final rawTypes = (p['types'] as String?) ?? '';
        final typeLabels = <String>{};
        for (var t in rawTypes.split(',')) { t = t.trim(); if (t.isNotEmpty) typeLabels.add(_typeAbbr(t)); }
        final subtitle = '$count 题  |  ${typeLabels.join('·')}';
        final paperId = p['paper_id'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _startPaper(p),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                if (isHistory)
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _deleteFromHistory(p),
                      tooltip: '移除历史')
                else if (!isFav)
                  IconButton(
                    icon: const Icon(Icons.bookmark_border, size: 20),
                    onPressed: () => _toggleFavorite(p),
                    tooltip: '收藏',
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.bookmark, color: Color(0xFFE94560), size: 20),
                    onPressed: () => _toggleFavorite(p),
                    tooltip: '取消收藏',
                  ),
                IconButton(icon: const Icon(Icons.play_arrow, color: Color(0xFF4ECDC4), size: 22), onPressed: () => _startPaper(p), tooltip: '开始练习'),
              ]),
            ),
          ),
        );
      },
    );
  }
}
