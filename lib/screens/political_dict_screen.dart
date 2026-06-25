import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/political_dict.dart';
import '../database/db_helper.dart';
import '../services/journal_service.dart';

class PoliticalDictScreen extends StatefulWidget {
  const PoliticalDictScreen({super.key});
  @override
  State<PoliticalDictScreen> createState() => _PoliticalDictScreenState();
}

class _PoliticalDictScreenState extends State<PoliticalDictScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _tabs = [
    {'key': 'cxll', 'label': '创新理论', 'color': Color(0xFFE94560)},
    {'key': 'dszs', 'label': '党史知识', 'color': Color(0xFF4A90D9)},
    {'key': '20d', 'label': '二十大报告', 'color': Color(0xFFF5A623)},
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

  List<PoliticalTerm> _filter(String cat) {
    final all = politicalTerms.where((t) => t.category == cat).toList();
    if (_search.isEmpty) return all;
    return all.where((t) => t.title.contains(_search) || t.definition.contains(_search)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? null : const Color(0xFF1A1A2E);
    return Scaffold(
      appBar: AppBar(
        title: const Text('政治理论词典'),
        backgroundColor: appBarBg,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索词条...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); }, padding: EdgeInsets.zero)
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
          final accent = t['color'] as Color;
          return items.isEmpty
              ? Center(child: Text('暂无匹配词条', style: TextStyle(color: Colors.grey.shade400)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildCard(items[i], accent),
                );
        }).toList(),
      ),
    );
  }

  Widget _buildCard(PoliticalTerm term, Color accent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Text(term.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        children: [
          Text(term.definition, style: const TextStyle(fontSize: 13, height: 1.8, color: Colors.black87)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${term.title}\n${term.definition}'));
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

  Future<void> _addToJournal(PoliticalTerm term) async {
    final now = DateTime.now();
    final entry = JournalEntry(
      id: now.millisecondsSinceEpoch.toString(),
      date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      content: '【${term.title}】\n${term.definition}',
      imagePath: '',
      createdAt: now.toIso8601String(),
    );
    await JournalService.add(entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
    }
  }
}
