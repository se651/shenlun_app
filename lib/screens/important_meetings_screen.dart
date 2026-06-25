import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/important_meetings.dart';
import '../database/db_helper.dart';
import '../services/meeting_refresh_service.dart';

/// 重要会议 — 会议提要 + 聚焦重点 两栏（含联网刷新+AI分析）
class ImportantMeetingsScreen extends StatefulWidget {
  const ImportantMeetingsScreen({super.key});

  @override
  State<ImportantMeetingsScreen> createState() => _ImportantMeetingsScreenState();
}

class _ImportantMeetingsScreenState extends State<ImportantMeetingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, String>> _latestArticles = [];
  bool _loadingArticles = true;
  String _aiAnalysis = '';
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCached();
    _refresh();
  }

  Future<void> _loadCached() async {
    final cached = await MeetingRefreshService.loadCache();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _latestArticles.clear();
        for (final item in cached.take(20)) {
          _latestArticles.add({
            'title': item['title']?.toString() ?? '',
            'url': item['url']?.toString() ?? '',
            'date': item['date']?.toString() ?? '',
          });
        }
        _loadingArticles = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _loadingArticles = true);
    final items = await MeetingRefreshService.fetchLatest();
    if (items.isNotEmpty) {
      await MeetingRefreshService.saveCache(items);
      if (mounted) {
        setState(() {
          _latestArticles.clear();
          _latestArticles.addAll(items);
          _loadingArticles = false;
        });
        _tryAiAnalyze(items.map((e) => e['title'] ?? '').toList());
      }
    } else {
      if (mounted) setState(() => _loadingArticles = false);
    }
  }

  Future<void> _tryAiAnalyze(List<String> titles) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty || titles.length < 3) return;
    setState(() => _aiLoading = true);
    final result = await MeetingRefreshService.aiAnalyze(apiKey, titles);
    if (mounted) setState(() { _aiAnalysis = result; _aiLoading = false; });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('重要会议'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A1A2E),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE94560),
          tabs: const [
            Tab(text: '会议提要'),
            Tab(text: '聚焦重点'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDigestTab(),
          _buildFocusTab(),
        ],
      ),
    );
  }

  /// Tab1: 会议提要 — 数据驱动的会议卡片列表
  Widget _buildDigestTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final meeting in importantMeetingsData)
          _buildMeetingCard(meeting),
      ],
    );
  }

  Widget _buildMeetingCard(ImportantMeeting meeting) {
    final categoryLabel = meetingCategoryLabels[meeting.category] ?? meeting.category;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.event, color: Color(0xFF1A1A2E), size: 20),
        ),
        title: Text(meeting.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(categoryLabel, style: const TextStyle(fontSize: 10, color: Color(0xFFE94560))),
          ),
          const SizedBox(width: 8),
          Text(meeting.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              Text(meeting.summary, style: const TextStyle(fontSize: 13, height: 1.6)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.star, size: 14, color: Color(0xFFF9CA24)),
                    SizedBox(width: 4),
                    Text('申论要点', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB8860B))),
                  ]),
                  const SizedBox(height: 6),
                  Text(meeting.keyPoints, style: const TextStyle(fontSize: 13, height: 1.7)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Tab2: 聚焦重点 — 联网获取最新会议动态 + AI 分析
  Widget _buildFocusTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI 分析卡片
          if (_aiAnalysis.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Text('🤖', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text('AI 会议分析', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                Text(_aiAnalysis, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (_aiLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),

          // 标题 + 刷新
          Row(children: [
            const Text('📰 最新会议动态', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),

          if (_loadingArticles)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),

          if (!_loadingArticles && _latestArticles.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('暂无最新会议动态\n下拉刷新或检查网络连接', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ),
            ),

          ..._latestArticles.map((article) => _buildArticleCard(article)),
        ],
      ),
    );
  }

  Widget _buildArticleCard(Map<String, String> article) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: const Icon(Icons.article_outlined, color: Color(0xFF1A1A2E)),
        title: Text(article['title'] ?? '', style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(article['date'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
      ),
    );
  }
}
