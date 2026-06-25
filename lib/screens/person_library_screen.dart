import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/person_data.dart';
import '../services/journal_service.dart';

class PersonLibraryScreen extends StatefulWidget {
  const PersonLibraryScreen({super.key});
  @override
  State<PersonLibraryScreen> createState() => _PersonLibraryScreenState();
}

class _PersonLibraryScreenState extends State<PersonLibraryScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PersonProfile> get _filtered => _search.isEmpty
      ? personProfiles
      : personProfiles.where((p) =>
          p.name.contains(_search) || p.tag.contains(_search) || p.keywords.contains(_search)).toList();

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物素材'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索人物、标签或关键词...',
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
        ),
      ),
      body: items.isEmpty
          ? Center(child: Text('暂无匹配人物', style: TextStyle(color: Colors.grey.shade400)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, i) => _buildCard(items[i]),
            ),
    );
  }

  Widget _buildCard(PersonProfile person) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: const Color(0xFF9C27B0), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(person.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(person.tag, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ])),
        ]),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.15)),
            ),
            child: Text(person.brief, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.5)),
          ),
          const SizedBox(height: 8),
          Text(person.details, style: const TextStyle(fontSize: 13, height: 1.8, color: Colors.black87)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: person.keywords.split('·').map((k) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF9C27B0).withOpacity(0.06), borderRadius: BorderRadius.circular(4)),
            child: Text(k.trim(), style: const TextStyle(fontSize: 10, color: Color(0xFF9C27B0))),
          )).toList()),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${person.name}\n${person.tag}\n${person.brief}\n${person.details}'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add, size: 14),
              label: const Text('加入积累本', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, foregroundColor: const Color(0xFF4ECDC4)),
              onPressed: () => _addToJournal(person),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addToJournal(PersonProfile person) async {
    final now = DateTime.now();
    final entry = JournalEntry(
      id: now.millisecondsSinceEpoch.toString(),
      date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      content: '【${person.name}】${person.tag}\n${person.brief}\n\n${person.details}',
      imagePath: '',
      createdAt: now.toIso8601String(),
    );
    await JournalService.add(entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
    }
  }
}
