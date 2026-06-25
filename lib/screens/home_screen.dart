import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../widgets/achievement_overlay.dart';
import 'summary_practice_screen.dart';
import 'question_list_screen.dart';
import 'weakness_practice_screen.dart';
import 'question_detail_screen.dart';
import 'summary_exercise_screen.dart';
import 'commentary_exercise_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _globalDialogsShown = false;
  final _db = DatabaseHelper();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  int _questionCount = 0;
  int _wordCount = 1006;
  Map<String, int> _typeStats = {};
  bool _loading = true;
  int _easterTapCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkDialogs();
  }

  Future<void> _checkDialogs() async {
    if (_globalDialogsShown) return;
    _globalDialogsShown = true;
    await _showAnnouncement();
    await _showThankYou();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String keyword) {
    if (keyword.trim().isEmpty) return;
    _focusNode.unfocus();
    // 搜全部类型 → questionType 传一个不存在的值让 searchQuestions 不限制类型
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionListScreen(
          questionType: '全部题型',
          keyword: keyword.trim(),
        ),
      ),
    );
  }

  Future<void> _showAnnouncement() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // 只显示一次
    final db = DatabaseHelper();
    final shown = await db.getSetting('announcement_shown');
    if (shown == 'true') return;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.campaign_rounded, color: Color(0xFFE94560), size: 22),
          SizedBox(width: 8),
          Text('📢 公告栏', style: TextStyle(fontSize: 17)),
        ]),
        content: SingleChildScrollView(
          child: Text(
            '''后续更新计划：

第一阶段：行测模拟题
• 政治理论、言语理解、数字推理、资料分析模拟题
• 成语查询 + 高频成语库
• 整理行测真题后统一更新

第二阶段：云端服务
• 账号密码登录，数据云端同步
• 每日下发模拟题 + 排行榜
• 活跃度统计，重点优化高频功能

第三阶段：AI 增强
• 统一模考功能
• 申论大模型批改打分（更准确）
• 行测大模型无限生成模拟题

更多建议欢迎反馈！

────────────────────
该软件只用于免费学习交流，切勿牟利''',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: Color(0xFFE94560))),
          ),
        ],
      ),
    );

    // 标记已显示
    db.setSetting('announcement_shown', 'true');
  }

  Future<void> _showThankYou() async {
    if (!mounted) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.favorite, color: Color(0xFFE94560), size: 22),
          SizedBox(width: 8),
          Text('感谢', style: TextStyle(fontSize: 17)),
        ]),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('感谢乙基苯丙烃的大力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢大头不头大的全力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢lilico的大力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢等我删个评论的全力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢该用户拥有无限好运(^_-)的鼎力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢牛油果里没有牛油的大力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢protea的全力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢一舟的全力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
          SizedBox(height: 4),
          Text('感谢Ada_的大力支持！', style: TextStyle(fontSize: 15, height: 1.6)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭', style: TextStyle(color: Color(0xFFE94560))),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      final count = await _db.getQuestionCount();
      final stats = await _db.getQuestionTypeStats();
      final wordCount = await _db.getWordCount();
      if (mounted) setState(() { _questionCount = count; _wordCount = wordCount; _typeStats = stats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        _questionCount = 644;
        _wordCount = 1006;
        _typeStats = {
          '综合分析': 179, '概括归纳': 178, '文章论述（大作文）': 119,
          '应用文': 143, '提出对策': 21,
        };
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 顶端每日一言 ──
                    GestureDetector(
                      onTap: () => _tapEasterEgg(),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 6),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '一万年太久，　', style: TextStyle(fontSize: 21, fontFamily: 'STXingkai', color: Colors.black87, letterSpacing: 1)),
                                TextSpan(text: '只争朝夕', style: TextStyle(fontSize: 21, fontFamily: 'STXingkai', color: Colors.black, letterSpacing: 1)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Header
                    _buildHeader(theme),
                    const SizedBox(height: 16),

                    // Stats cards
                    _buildStatsRow(theme),
                    const SizedBox(height: 24),

                    // 每日一练
                    _buildDailyPractice(theme),
                    const SizedBox(height: 16),
                    // 薄弱点加练
                    _buildWeaknessCard(theme),
                    const SizedBox(height: 16),
                    // 简评学习
                    _buildCommentaryExercise(theme),
                    const SizedBox(height: 12),
                    // 概括与分析
                    _buildSummaryExercise(theme),
                    const SizedBox(height: 12),


                    // 概括练习入口
                    _buildSummaryPractice(theme),
                    const SizedBox(height: 24),

                    // Quick actions
                    Text('快捷刷题', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildQuickActions(theme),
                    const SizedBox(height: 24),

                    // Type distribution
                    Text('题型分布', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildTypeList(theme),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('练申论',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                )),
            const SizedBox(height: 2),
            Text('公务员考试 · 申论刷题',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
        GestureDetector(
          onTap: () => _tapEarthEasterEgg(),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE94560), Color(0xFF16213E)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      decoration: InputDecoration(
        hintText: '搜索题目材料…',
        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
        ),
      ),
      style: const TextStyle(fontSize: 14),
      textInputAction: TextInputAction.search,
      onSubmitted: _onSearch,
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    return Row(
      children: [
        _buildStatCard('总题库', '$_questionCount', '道题目', Icons.library_books_outlined, const Color(0xFF4ECDC4)),
        const SizedBox(width: 12),
        _buildStatCard('规范词', '$_wordCount', '个词汇', Icons.menu_book_outlined, const Color(0xFFA29BFE)),
        const SizedBox(width: 12),
        _buildStatCard('地区', '28', '个省份', Icons.public_outlined, const Color(0xFFF9CA24)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(unit, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildWeaknessCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withOpacity(0.2),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('AI 诊断', style: TextStyle(color: Color(0xFFE94560), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              const Text('🎯', style: TextStyle(fontSize: 28)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('薄弱点加练',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<List<String>>(
            future: _analyzeWeakness(),
            builder: (ctx, snap) {
              if (!snap.hasData || snap.data!.isEmpty) {
                return Text('完成更多练习后，AI 将为你分析薄弱项',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...snap.data!.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.priority_high, size: 14, color: Color(0xFFF9CA24)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  ]),
                )),
              ]);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => _startWeaknessPractice(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('开始练习', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPractice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SummaryPracticeScreen())),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF4ECDC4), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('概括练习', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('短句→段落→全文→提纲，渐进式归纳训练',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('权威官媒素材',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4ECDC4))),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    final items = [
      {'icon': Icons.summarize_rounded, 'label': '概括归纳', 'color': const Color(0xFF4ECDC4), 'count': _typeStats['概括归纳'] ?? 0},
      {'icon': Icons.psychology_rounded, 'label': '综合分析', 'color': const Color(0xFFA29BFE), 'count': _typeStats['综合分析'] ?? 0},
      {'icon': Icons.lightbulb_rounded, 'label': '提出对策', 'color': const Color(0xFFF9CA24), 'count': _typeStats['提出对策'] ?? 0},
      {'icon': Icons.description_rounded, 'label': '应用文', 'color': const Color(0xFF6C5CE7), 'count': 143},
      {'icon': Icons.article_rounded, 'label': '大作文', 'color': const Color(0xFFE94560), 'count': _typeStats['文章论述（大作文）'] ?? 0},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 10),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionListScreen(questionType: item['label'] as String))),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                  child: Column(
                    children: [
                      Icon(item['icon'] as IconData, color: item['color'] as Color, size: 26),
                      const SizedBox(height: 8),
                      Text(item['label'] as String,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 2),
                      Text('${item['count']}题',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTypeList(ThemeData theme) {
    final colors = {
      '综合分析': const Color(0xFFA29BFE),
      '概括归纳': const Color(0xFF4ECDC4),
      '文章论述（大作文）': const Color(0xFFE94560),
      '提出对策': const Color(0xFFF9CA24),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _typeStats.entries.where((e) => colors.containsKey(e.key)).map((e) {
          final pct = _questionCount > 0 ? e.value / _questionCount : 0.0;
          final color = colors[e.key] ?? Colors.grey;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                SizedBox(width: 72, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct, minHeight: 6,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 36,
                  child: Text('${e.value}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// AI 分析薄弱点
  Future<List<String>> _analyzeWeakness() async {
    final db = DatabaseHelper();
    final history = await db.getPracticeHistory(limit: 200);
    if (history.length < 5) return [];
    final typeStats = <String, List<int>>{};
    for (final r in history) {
      final t = (r['question_type'] as String?) ?? '';
      if (t.isEmpty) continue;
      final score = r['score'] is int ? r['score'] as int : int.tryParse('${r['score'] ?? '0'}') ?? 0;
      typeStats.putIfAbsent(t, () => []).add(score);
    }
    final weakness = <String, double>{};
    for (final e in typeStats.entries) {
      if (e.value.length < 2) continue;
      final avg = e.value.reduce((a,b)=>a+b) / e.value.length;
      weakness[e.key] = avg;
    }
    final sorted = weakness.entries.toList()..sort((a,b) => a.value.compareTo(b.value));
    final result = <String>[];
    for (int i = 0; i < sorted.length && i < 3; i++) {
      result.add('${sorted[i].key} 得分率 ${sorted[i].value.round()}%');
    }
    return result;
  }

  Widget _buildCommentaryExercise(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFF9CA24).withOpacity(0.08), const Color(0xFFE94560).withOpacity(0.08)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0xFFF9CA24).withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.rate_review_rounded, color: Color(0xFFE94560), size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('简评学习', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('用问政陕西素材练评论写作', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        SizedBox(height: 38, child: ElevatedButton.icon(
          onPressed: () => _checkAPIAndNav(const CommentaryExerciseScreen(), '简评学习'),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('开始', style: TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF9CA24), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        )),
      ]),
    );
  }

  Widget _buildSummaryExercise(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF6C5CE7).withOpacity(0.08), const Color(0xFF4ECDC4).withOpacity(0.08)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.summarize_rounded, color: Color(0xFF6C5CE7), size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('概括与分析', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('用留言板素材练习概括+对策', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            onPressed: () => _checkAPIAndNav(const SummaryExerciseScreen(), '概括与分析'),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('开始', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildDailyPractice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFE94560).withOpacity(0.08), const Color(0xFFF9CA24).withOpacity(0.08)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE94560).withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.today_rounded, color: Color(0xFFE94560), size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('每日一练', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('AI 智能推荐今日薄弱专项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            onPressed: _startDailyPractice,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('开始', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _startDailyPractice() async {
    final db = DatabaseHelper();
    // 获取题型列表
    final allTypes = await db.getQuestionTypes();
    // 分析薄弱题型
    final history = await db.getPracticeHistory(limit: 200);
    var weakestType = allTypes.isNotEmpty ? allTypes.first : '概括归纳';
    if (history.length >= 5) {
      final typeStats = <String, List<int>>{};
      for (final r in history) {
        final t = (r['question_type'] as String?) ?? '';
        if (t.isEmpty) continue;
        final s = r['score'] is int ? r['score'] as int : int.tryParse('${r['score'] ?? '0'}') ?? 0;
        typeStats.putIfAbsent(t, () => []).add(s);
      }
      if (typeStats.isNotEmpty) {
        double lowest = double.infinity;
        for (final e in typeStats.entries) {
          final avg = e.value.reduce((a,b)=>a+b) / e.value.length;
          if (avg < lowest) { lowest = avg; weakestType = e.key; }
        }
      }
    }
    // 随机抽一题
    final qs = await db.getQuestions(questionType: weakestType, limit: 1);
    if (qs.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('题库暂无匹配题目')));
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuestionDetailScreen(
        questionId: qs.first['id'] as String,
        questionType: qs.first['question_type'] as String? ?? weakestType,
        skipHistory: true,
      ),
    ));
  }

  void _tapEarthEasterEgg() async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = prefs.getBool('achievement_earth') ?? false;
    if (!unlocked) {
      await prefs.setBool('achievement_earth', true);
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(builder: (ctx) => AchievementOverlay(
        imageAsset: 'assets/achievement_earth.jpg',
        title: '把申论写在大地上',
        content: '把申论写在祖国大地上，把答案写在群众心里',
        tagline: '为党分忧，为民解难！你已达成成就',
        onDismiss: () { entry.remove(); },
      ));
      overlay.insert(entry);
    }
  }

  void _tapEasterEgg() async {
    _easterTapCount++;
    if (_easterTapCount >= 5) {
      final prefs = await SharedPreferences.getInstance();
      final unlocked = prefs.getBool('achievement_zheng') ?? false;
      if (!unlocked) {
        await prefs.setBool('achievement_zheng', true);
        _easterTapCount = 0;
        final overlay = Overlay.of(context);
        late OverlayEntry entry;
        entry = OverlayEntry(builder: (ctx) => AchievementOverlay(
          imageAsset: 'assets/achievement_zheng.png',
          title: '只争朝夕',
          content: '四海翻腾云水怒，五洲震荡风雷激！',
          tagline: '今日长缨在手，何时缚住苍龙？你已达成成就',
          onDismiss: () { entry.remove(); },
        ));
        overlay.insert(entry);
      }
    }
  }

  Future<void> _checkAPIAndNav(Widget screen, String label) async {
    final key = await DatabaseHelper().getSetting('deepseek_api_key');
    if (key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$label」需要 DeepSeek API Key，请在「我的」页面设置'), duration: const Duration(seconds: 2)),
      );
      return;
    }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _startWeaknessPractice() async {
    final weaknesses = await _analyzeWeakness();
    if (weaknesses.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('练习数据不足，请先完成至少5道题')));
      return;
    }
    final weakTypes = weaknesses.map((w) {
      final m = RegExp(r'^(.+?) 得分率').firstMatch(w);
      return m?.group(1) ?? '';
    }).where((t) => t.isNotEmpty).toList();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => WeaknessPracticeScreen(weakTypes: weakTypes)));
  }
}
