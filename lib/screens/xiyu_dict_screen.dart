import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/xiyu_dict.dart';
import '../services/journal_service.dart';

class XiyuDictScreen extends StatefulWidget {
  const XiyuDictScreen({super.key});
  @override
  State<XiyuDictScreen> createState() => _XiyuDictScreenState();
}

class _XiyuDictScreenState extends State<XiyuDictScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _tabs = [
    {'key': 'guyu', 'label': '古语篇', 'color': Color(0xFF8B4513)},
    {'key': 'yanyu', 'label': '谚语篇', 'color': Color(0xFFDAA520)},
    {'key': 'yuanchuang', 'label': '原创篇', 'color': Color(0xFFE94560)},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<XiyuTerm> _filter(String cat) {
    var all = <XiyuTerm>[];
    if (cat == 'guyu') all = xiyuTerms.where((t) => t.source.contains('《')).toList();
    else if (cat == 'yanyu') all = xiyuTerms.where((t) => t.source == '民间谚语' || t.source.contains('谚')).toList();
    else all = xiyuTerms.where((t) => !t.source.contains('《') && t.source != '民间谚语' && !t.source.contains('谚')).toList();
    
    if (_search.isEmpty) return all;
    return all.where((t) => t.title.contains(_search) || t.quote.contains(_search) || t.meaning.contains(_search)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('习语金句'),
        backgroundColor: const Color(0xFF1A1A2E),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索习语...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                      : null,
                  filled: true, fillColor: Colors.white.withOpacity(0.15),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: _tabs.map((t) => Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: t['color'] as Color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(t['label'] as String),
                ]),
              )).toList(),
            ),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) {
          final items = _filter(t['key'] as String);
          return items.isEmpty
              ? Center(child: Text('暂无词条', style: TextStyle(color: Colors.grey.shade400)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildCard(items[i]),
                );
        }).toList(),
      ),
    );
  }

  Widget _buildCard(XiyuTerm term) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: const Color(0xFFB8860B), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Text(term.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFA000).withOpacity(0.2)),
            ),
            child: Text('"${term.quote}"', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.6, fontStyle: FontStyle.italic, color: Color(0xFF5D4037))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.menu_book, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(child: Text(term.source, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
          ]),
          const SizedBox(height: 8),
          Text(term.meaning, style: const TextStyle(fontSize: 13, height: 1.8, color: Colors.black87)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${term.title}\n"${term.quote}"\n——${term.source}\n${term.meaning}'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add, size: 14),
              label: const Text('加入积累本', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, foregroundColor: const Color(0xFF4ECDC4)),
              onPressed: () => _addToJournal(term),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addToJournal(XiyuTerm term) async {
    final now = DateTime.now();
    final entry = JournalEntry(
      id: now.millisecondsSinceEpoch.toString(),
      date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      content: '【${term.title}】\n"${term.quote}"\n——${term.source}\n\n${term.meaning}',
      imagePath: '',
      createdAt: now.toIso8601String(),
    );
    await JournalService.add(entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
    }
  }
}
