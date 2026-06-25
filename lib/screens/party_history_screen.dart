import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/party_history.dart';
import '../services/journal_service.dart';

class PartyHistoryScreen extends StatefulWidget {
  const PartyHistoryScreen({super.key});

  @override
  State<PartyHistoryScreen> createState() => _PartyHistoryScreenState();
}

class _PartyHistoryScreenState extends State<PartyHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    {'key': 'meeting', 'label': '重要会议', 'color': Color(0xFFE94560)},
    {'key': 'spirit', 'label': '精神谱系', 'color': Color(0xFF4A90D9)},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<PartyHistoryItem> _data(String cat) {
    final list = partyHistoryData.where((e) => e.category == cat).toList();
    // 时间倒序
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('党史谱系'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF8B0000),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              tabs: _tabs.map((t) => Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: t['color'] as Color, shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(t['label'] as String),
                ]),
              )).toList(),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) {
          final items = _data(tab['key'] as String);
          final color = tab['color'] as Color;
          return tab['key'] == 'meeting'
              ? _buildMeetingList(items, color)
              : _buildSpiritList(items, color);
        }).toList(),
      ),
    );
  }

  // ─── 会议列表（时间线） ───
  Widget _buildMeetingList(List<PartyHistoryItem> items, Color color) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _MeetingCard(item: items[i], color: color),
    );
  }

  // ─── 精神谱系列表 ───
  Widget _buildSpiritList(List<PartyHistoryItem> items, Color color) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _SpiritCard(item: items[i], color: color),
    );
  }
}

// ─── 会议卡片 ───
class _MeetingCard extends StatelessWidget {
  final PartyHistoryItem item;
  final Color color;
  const _MeetingCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDetail(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Text(item.time.split('年')[0], style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                Text('年${item.time.contains('月') ? item.time.split('年')[1] : ''}', style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(item.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
                if (item.significance.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8F0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.lightbulb_outline, size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(child: Text('考点：${item.significance}', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)))),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── 精神卡片 ───
class _SpiritCard extends StatelessWidget {
  final PartyHistoryItem item;
  final Color color;
  const _SpiritCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDetail(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.flag, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                  if (item.time.isNotEmpty)
                    Text(item.time, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ]),
                const SizedBox(height: 4),
                Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── 详情弹窗 ───
void _showDetail(BuildContext context, PartyHistoryItem item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.category == 'meeting' ? const Color(0xFFE94560).withOpacity(0.1) : const Color(0xFF4A90D9).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item.category == 'meeting' ? '重要会议' : '精神谱系',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: item.category == 'meeting' ? const Color(0xFFE94560) : const Color(0xFF4A90D9))),
                ),
                if (item.time.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(item.time, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
                const Spacer(),
                // 复制按钮
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制全文',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '【${item.title}】${item.time.isNotEmpty ? '（$item.time）' : ''}\n\n${item.content}${item.significance.isNotEmpty ? '\n\n考点：${item.significance}' : ''}'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
                  },
                ),
                // 导入积累本
                IconButton(
                  icon: const Icon(Icons.bookmark_add, size: 18),
                  tooltip: '导入积累本',
                  onPressed: () async {
                    final now = DateTime.now();
                    await JournalService.add(JournalEntry(
                      id: now.millisecondsSinceEpoch.toString(),
                      date: '${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}',
                      content: '【${item.title}】${item.time.isNotEmpty ? '（$item.time）' : ''}\n\n${item.content}${item.significance.isNotEmpty ? '\n\n考点：${item.significance}' : ''}',
                      createdAt: now.toIso8601String(),
                    ));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
                  },
                ),
              ]),
              const SizedBox(height: 16),
              SelectableText(item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              SelectableText(item.content, style: const TextStyle(fontSize: 15, height: 1.9)),
              if (item.significance.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE94560).withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFE94560)),
                      SizedBox(width: 6),
                      Text('申论考点', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE94560))),
                    ]),
                    const SizedBox(height: 8),
                    SelectableText(item.significance, style: TextStyle(fontSize: 14, height: 1.8, color: Colors.brown.shade800)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    ),
  );
}
