import 'package:flutter/material.dart';
import '../data/party_history.dart';
import 'political_dict_screen.dart';
import 'xiyu_dict_screen.dart';
import 'person_library_screen.dart';
import 'xinnian_heci_screen.dart';
import 'article_list_screen.dart';
import 'party_history_screen.dart';
import 'people_commentary_screen.dart';
import 'xjp_speech_list_screen.dart';
import 'qiushi_magazine_screen.dart';
import 'hqwg_magazine_screen.dart';
import 'gov_docs_screen.dart';
import 'zuzhirenshi_screen.dart';
import 'important_meetings_screen.dart';

class MaterialLibraryScreen extends StatelessWidget {
  const MaterialLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('素材库')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('申论必备', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildCard(
            context,
            icon: Icons.description_outlined,
            color: const Color(0xFF0984E3),
            title: '公文示例',
            subtitle: '通知·通告·意见·办法·方案·规划等18类',
            count: '363篇',
            screen: const GovDocsScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.flag,
            color: const Color(0xFF8B0000),
            title: '党史谱系',
            subtitle: '重要会议·党的精神谱系·申论考点',
            count: '${partyHistoryData.length}条',
            screen: const PartyHistoryScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.account_balance,
            color: const Color(0xFFE94560),
            title: '政治理论词典',
            subtitle: '党的创新理论、党史知识、二十大报告',
            count: '151条',
            screen: const PoliticalDictScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.format_quote,
            color: const Color(0xFFB8860B),
            title: '习语金句',
            subtitle: '习近平用典、原创金句、出处释义',
            count: '66条',
            screen: const XiyuDictScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.people,
            color: const Color(0xFF9C27B0),
            title: '人物素材',
            subtitle: '时代楷模、共和国勋章、大国工匠等',
            count: '55位',
            screen: const PersonLibraryScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(context, icon: Icons.celebration, color: const Color(0xFFE94560), title: '新年贺词', subtitle: '2018-2026年新年贺词全文摘要与金句', count: '9篇', screen: const XinnianHeciScreen()),
          const SizedBox(height: 24),
          const Text('实时素材', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildCard(
            context,
            icon: Icons.event,
            color: const Color(0xFF1A1A2E),
            title: '重要会议',
            subtitle: '2024-2026年中央重要工作会议·提要+重点',
            count: '申论核心',
            screen: const ImportantMeetingsScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.article,
            color: const Color(0xFFE94560),
            title: '先锋文汇',
            subtitle: '共产党员网·基层干部政论文章精选',
            count: '实时更新',
            screen: const ArticleListScreen(title: '先锋文汇', sourceKey: 'xianfeng_wenhui', accentColor: Color(0xFFE94560)),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.menu_book,
            color: const Color(0xFF4A90D9),
            title: '求是网评',
            subtitle: '求是网·评论员政论文章精选',
            count: '实时更新',
            screen: const ArticleListScreen(title: '求是网评', sourceKey: 'qiushi_wp', accentColor: Color(0xFF4A90D9)),
          ),
          const SizedBox(height: 10),
          _buildCard(context, icon: Icons.rate_review, color: const Color(0xFFCC0000), title: '人民网评', subtitle: '壹时评·人民时评·党建评', count: '实时更新', screen: const PeopleCommentaryScreen()),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.menu_book,
            color: const Color(0xFFCC0000),
            title: '红旗文稿',
            subtitle: '2020-2026年《红旗文稿》全文',
            count: '实时更新',
            screen: const HqwgMagazineScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.menu_book,
            color: const Color(0xFF8B0000),
            title: '求是杂志',
            subtitle: '2019-2026年《求是》期刊全文',
            count: '实时更新',
            screen: const QiushiMagazineScreen(),
          ),
          const SizedBox(height: 10),
          _buildCard(
            context,
            icon: Icons.newspaper,
            color: const Color(0xFF1A5276),
            title: '中国组织人事报',
            subtitle: '2010-2026年 党建·干部·人才·人社',
            count: '实时更新',
            screen: const ZuzhirenshiScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String count,
    required Widget screen,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text(count, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}
