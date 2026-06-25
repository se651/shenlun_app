import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/xinnian_heci.dart';
import '../services/journal_service.dart';

class XinnianHeciScreen extends StatelessWidget {
  const XinnianHeciScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新年贺词'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: xinnianHeci.length,
        itemBuilder: (_, i) => _buildCard(context, xinnianHeci[i]),
      ),
    );
  }

  Widget _buildCard(BuildContext context, XinnianHeci heci) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE94560), Color(0xFFE8C560)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(heci.year.substring(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(heci.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        children: [
          // 全文
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF5F0EB), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.article, size: 16, color: Color(0xFF1A1A2E)),
                SizedBox(width: 6),
                Text('全文', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
              ]),
              const SizedBox(height: 8),
              Text(heci.fullText, style: const TextStyle(fontSize: 13, height: 1.9)),
            ]),
          ),
          const SizedBox(height: 10),
          // 总结
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.summarize, size: 16, color: Color(0xFFE8C560)),
                SizedBox(width: 6),
                Text('内容总结', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE8C560))),
              ]),
              const SizedBox(height: 8),
              Text(heci.summary, style: const TextStyle(fontSize: 13, height: 1.8)),
            ]),
          ),
          const SizedBox(height: 10),
          // 核心金句
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.format_quote, size: 16, color: Color(0xFFE94560)),
                SizedBox(width: 6),
                Text('核心金句', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE94560))),
              ]),
              const SizedBox(height: 8),
              Text(heci.highlights, style: const TextStyle(fontSize: 13, height: 1.8, fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${heci.title}\n\n${heci.fullText}\n\n【内容总结】\n${heci.summary}\n\n【核心金句】\n${heci.highlights}'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制全文'), duration: Duration(seconds: 1)));
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_add, size: 14),
              label: const Text('加入积累本', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, foregroundColor: const Color(0xFF4ECDC4)),
              onPressed: () => _addToJournal(context, heci),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addToJournal(BuildContext context, XinnianHeci heci) async {
    final now = DateTime.now();
    final entry = JournalEntry(
      id: now.millisecondsSinceEpoch.toString(),
      date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      content: '【${heci.title}】\n\n${heci.fullText}\n\n【总结】${heci.summary}\n\n【金句】${heci.highlights}',
      imagePath: '',
      createdAt: now.toIso8601String(),
    );
    await JournalService.add(entry);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
    }
  }
}
