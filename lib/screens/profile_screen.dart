import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/achievement_overlay.dart';
import '../widgets/shiny_medal.dart';
import '../services/achievement_service.dart';
import '../screens/my_achievements_screen.dart';
import '../screens/grand_finale_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../database/db_helper.dart';
import '../main.dart';
import 'study_plan_screen.dart';
import 'favorites_screen.dart';
import 'wrong_answer_screen.dart';
import 'history_screen.dart';
import 'radar_screen.dart';
import 'download_screen.dart';
import 'journal_screen.dart';
import '../services/daily_push.dart';
import 'daily_push_card.dart';
import 'mock_exam_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = DatabaseHelper();
  String _apiKey = '';
  String _scoringMode = 'auto';
  bool _dailyPushEnabled = true;
  String _avatarPath = '';
  String _userName = '公考考生';
  int _totalPractice = 0;
  int _streakDays = 0;
  int _favoriteCount = 0;
  bool _hideThankYou = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final pushEnabled = await _db.getSetting('daily_push_enabled');
      _dailyPushEnabled = pushEnabled != 'false';
      final key = await _db.getSetting('deepseek_api_key');
      final mode = await _db.getSetting('scoring_mode');
      final theme = await _db.getSetting('theme_mode');
      final history = await _db.getPracticeHistory(limit: 100);
      
      int streak = 0;
      if (history.isNotEmpty) {
        final dates = <DateTime>{};
        for (final r in history) {
          final t = r['created_at'] as String?;
          if (t != null && t.length >= 10) {
            dates.add(DateTime.parse(t.substring(0, 10)));
          }
        }
        final sorted = dates.toList()..sort((a, b) => b.compareTo(a));
        final today = DateTime.now();
        var check = DateTime(today.year, today.month, today.day);
        for (final d in sorted) {
          if (d == check) { streak++; check = check.subtract(const Duration(days: 1)); }
          else if (d.isBefore(check)) break;
        }
      }
      
      // Count favorites
      int favCount = 0;
      try {
        final db = await _db.database;
        if (db != null) {
          final r = await db.rawQuery('SELECT COUNT(*) as c FROM favorites');
          favCount = r.first['c'] as int? ?? 0;
        }
      } catch (_) {}

      final avatar = await _db.getSetting('avatar_path');
      final name = await _db.getSetting('user_name');
      final fontScaleStr = await _db.getSetting('font_scale');
      final hideThankYou = await _db.getSetting('hide_thankyou');
      if (mounted) setState(() {
        _hideThankYou = hideThankYou == '1';
        _apiKey = key;
        _scoringMode = mode.isNotEmpty && mode != 'auto' ? mode : (key.isNotEmpty ? 'ai' : 'local');
        _currentTheme = theme.isNotEmpty ? theme : 'light';
        _avatarPath = avatar;
        _userName = name.isNotEmpty ? name : '公考考生';
        if (fontScaleStr.isNotEmpty) {
          try { ShenlunAppState.of(context).setFontScale(double.parse(fontScaleStr)); } catch (_) {}
        }
        _totalPractice = history.length;
        _streakDays = streak;
        _favoriteCount = favCount;
      });
      // 启动时应用已保存的主题
      if (theme.isNotEmpty && theme != 'light') {
        try { ShenlunAppState.of(context).applyThemeMode(theme); } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (picked != null) {
      await _db.setSetting('avatar_path', picked.path);
      setState(() => _avatarPath = picked.path);
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _userName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '输入你的昵称'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _db.setSetting('user_name', result);
      setState(() => _userName = result);
    }
  }

  void _openApiKeyDialog() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ApiKeyTutorialPage(
        currentKey: _apiKey,
        onSaved: (key) async {
          await _db.setSetting('deepseek_api_key', key);
          // 首次设置或清空 Key → 自动切 AI
          await _db.setSetting('scoring_mode', key.isNotEmpty ? 'ai' : 'local');
          if (mounted) setState(() { _apiKey = key; _scoringMode = key.isNotEmpty ? 'ai' : 'local'; });
        },
      ),
    ));
  }

  void _toggleScoringMode() async {
    final newMode = _scoringMode == 'local' ? 'ai' : 'local';
    await _db.setSetting('scoring_mode', newMode);
    setState(() => _scoringMode = newMode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newMode == 'ai' ? '已切换为 AI 批改' : '已切换为本地评分'), duration: const Duration(seconds: 1)),
      );
    }
  }

  String _currentTheme = 'light'; // 'light' | 'dark' | 'eye'

  Future<void> _openThemeDialog() async {
    final labels = {'light': '☀️ 日间模式', 'dark': '🌙 夜间模式', 'eye': '👁️ 护眼模式'};
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择背景模式'),
        children: ['light', 'dark', 'eye'].map((mode) {
          final isSelected = mode == _currentTheme;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, mode),
            child: Row(children: [
              Text(labels[mode]!, style: TextStyle(fontSize: 15, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
              const Spacer(),
              if (isSelected) const Icon(Icons.check, color: Color(0xFFE94560), size: 20),
            ]),
          );
        }).toList(),
      ),
    );
    if (result != null && result != _currentTheme) {
      await _db.setSetting('theme_mode', result);
      setState(() => _currentTheme = result);
      // 实际切换 App 主题
      try {
        ShenlunAppState.of(context).applyThemeMode(result);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已切换为${labels[result]}'), duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  String get _fontLabel {
    final s = ShenlunAppState.of(context).fontScale;
    if (s <= 0.85) return '小';
    if (s <= 1.05) return '标准';
    if (s <= 1.25) return '大';
    return '特大';
  }

  void _openFontDialog() {
    final app = ShenlunAppState.of(context);
    final current = app.fontScale;
    final options = [0.8, 0.9, 1.0, 1.15, 1.3];
    final labels = ['小', '较小', '标准', '较大', '大'];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('字体大小'),
        children: List.generate(options.length, (i) {
          final sel = (current - options[i]).abs() < 0.05;
          return SimpleDialogOption(
            onPressed: () {
              app.setFontScale(options[i]);
              _db.setSetting('font_scale', options[i].toStringAsFixed(2));
              Navigator.pop(ctx);
              setState(() {});
            },
            child: Row(children: [
              Text(labels[i], style: TextStyle(fontSize: 14 + options[i] * 2, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
              const Spacer(),
              if (sel) const Icon(Icons.check, color: Color(0xFFE94560), size: 18),
            ]),
          );
        }),
      ),
    );
  }

  void _showReward() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocalState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.favorite, color: Color(0xFFE94560), size: 22),
            SizedBox(width: 8),
            Text('赞赏支持', style: TextStyle(fontSize: 17)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/reward_qr.png', width: 220, height: 220),
            const SizedBox(height: 12),
            Column(mainAxisSize: MainAxisSize.min, children: [
                Text('感谢乙基苯丙烃的支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢大头不头大的全力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢lilico的大力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢等我删个评论的全力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢该用户拥有无限好运(^_-)的鼎力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢牛油果里没有牛油的大力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢protea的全力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢一舟的全力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                SizedBox(height: 1),
                Text('感谢Ada_的大力支持！', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
              ]),
          ]),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('不再显示感谢弹窗', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Switch(
                      value: _hideThankYou,
                      activeColor: const Color(0xFFE94560),
                      onChanged: (v) {
                        _db.setSetting('hide_thankyou', v ? '1' : '0');
                        setState(() => _hideThankYou = v);
                        setLocalState(() {});
                      },
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭', style: TextStyle(color: Color(0xFFE94560))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static AudioPlayer? _staticAudioPlayer;

  AudioPlayer get _audioPlayer {
    _staticAudioPlayer ??= AudioPlayer();
    return _staticAudioPlayer!;
  }

  void _playAboutAudio() async {
    _audioPlayer.play(AssetSource('zjs.mp3'));
    final prefs = await SharedPreferences.getInstance();
    final unlocked = prefs.getBool('achievement_qs') ?? false;
    if (unlocked) {
      _showAbout();
    } else {
      await prefs.setBool('achievement_qs', true);
      if (mounted) _showAchievement();
    }
  }

  void _showAchievement() {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) => AchievementOverlay(onDismiss: () { entry.remove(); }));
    overlay.insert(entry);
  }

  @override void dispose() { super.dispose(); }

  Future<Map<String, dynamic>> _getAchStatus() async {
    final hidden = await AchievementService.hiddenShown();
    final count = await AchievementService.unlockedCount();
    return {'hidden': hidden, 'count': count};
  }

  void _openAchievements() async {
    // Check for hidden achievement before opening
    final showHidden = await AchievementService.tryUnlockHidden();
    if (showHidden && mounted) {
      _showHiddenAchievement();
      return;
    }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAchievementsScreen()));
  }

  void _showHiddenAchievement() {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) => AchievementOverlay(
      imageAsset: 'assets/achievement_shangan.jpg',
      title: '一鸣惊人',
      content: '大鹏一日同风起，扶摇直上九万里',
      tagline: '数风流人物，还看今朝！你已获得全部成就',
      onDismiss: () { entry.remove(); _showGrandFinale(); },
    ));
    overlay.insert(entry);
  }

  void _showGrandFinale() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GrandFinaleScreen()));
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: '练申论',
      applicationVersion: 'v1.0.0-alpha.58',
      applicationIcon: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE94560), Color(0xFF16213E)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
      ),
      children: [
        const Text('公务员考试申论刷题 App\n\n640 道真题 · 全覆盖五大题型\n智能评分 · AI 批改 · 时政积累'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiKeyLabel = _apiKey.isNotEmpty ? '已设置 (${_apiKey.substring(0, _apiKey.length.clamp(0, 10))}...)' : '未设置';
    final scoringLabel = _scoringMode == 'local' ? '本地规则引擎' : 'AI 批改 (DeepSeek)';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // User card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      image: _avatarPath.isNotEmpty ? DecorationImage(image: FileImage(File(_avatarPath)), fit: BoxFit.cover) : null,
                    ),
                    child: _avatarPath.isEmpty ? const Icon(Icons.camera_alt_rounded, color: Colors.white54, size: 28) : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(
                      onTap: _editName,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                          child: Text(_userName, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit, color: Colors.white38, size: 15),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text('坚持打卡 $_streakDays 天 · 练习 $_totalPractice 题',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                  ]),
                ),
                // Medal icon when all achievements unlocked
                FutureBuilder<int>(future: AchievementService.unlockedCount(), builder: (ctx, snap) {
                  final count = snap.data ?? 0;
                  if (count >= 3) {
                    return const ShinyMedal();
                  }
                  return const SizedBox.shrink();
                }),
              ]),
            ),
            const SizedBox(height: 24),

            // Stats
            Row(children: [
              _buildMiniStat('练习天数', '$_streakDays', Icons.calendar_today_rounded),
              const SizedBox(width: 10),
              _buildMiniStat('总答题', '$_totalPractice', Icons.edit_note_rounded),
              const SizedBox(width: 10),
              _buildMiniStat('收藏', '$_favoriteCount', Icons.bookmark_rounded),
            ]),
            const SizedBox(height: 24),

            // AI
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Material(
                color: Colors.transparent, borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyPlanScreen())),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(children: [
                      Text('🤖', style: TextStyle(fontSize: 32)),
                      SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('AI 学习计划', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('智能分析弱项 · 生成个性化方案', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ])),
                      Icon(Icons.chevron_right, color: Colors.white70),
                    ]),
                  ),
                ),
              ),
            ),

            // 每日推送
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_rounded, color: Color(0xFF4ECDC4)),
                  title: const Text('每日推送', style: TextStyle(fontSize: 15)),
                  subtitle: const Text('打开App时弹出今日新闻汇总'),
                  value: _dailyPushEnabled,
                  activeColor: const Color(0xFF4ECDC4),
                  onChanged: (v) { setState(() => _dailyPushEnabled = v); _db.setSetting('daily_push_enabled', v ? 'true' : 'false'); },
                ),
              ),
            ),
            // Settings
            Text('功能', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _buildMenuItem(Icons.bookmark_rounded, '我的收藏', '$_favoriteCount 题', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
            _buildMenuItem(Icons.history_rounded, '历史习题', '$_totalPractice 题', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
            _buildMenuItem(Icons.error_outline_rounded, '错题本', '', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WrongAnswerScreen()))),
            _buildMenuItem(Icons.radar_rounded, '自我分析', '', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RadarScreen()))),
            _buildMenuItem(Icons.download_rounded, '下载管理', '', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadScreen()))),

            _buildMenuItem(Icons.open_in_full_rounded, '查看今日推送', '', onTap: () async {
              final push = await DailyPushService.getDailyPush(_apiKey.isNotEmpty ? _apiKey : null);
              if (!context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => DailyPushScreen(push: push)));
            }),
            _buildMenuItem(Icons.menu_book_rounded, '素材积累本', '', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalScreen()))),
            _buildMenuItem(Icons.quiz_rounded, 'AI 模拟题', '', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MockExamListScreen()))),
            const SizedBox(height: 24),

            Text('设置', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _buildMenuItem(Icons.brightness_6_rounded, '背景模式', {'light': '日间模式', 'dark': '夜间模式', 'eye': '护眼模式'}[_currentTheme] ?? '日间模式', onTap: _openThemeDialog),
            _buildMenuItem(Icons.key_rounded, 'DeepSeek API Key', apiKeyLabel, onTap: _openApiKeyDialog),
            _buildMenuItem(Icons.speed_rounded, '评分模式', scoringLabel, onTap: _toggleScoringMode),
            _buildMenuItem(Icons.text_fields_rounded, '字体大小', _fontLabel, onTap: _openFontDialog),
            _buildMenuItem(Icons.favorite_rounded, '赞赏支持', '支持开发者', onTap: _showReward),
            FutureBuilder<Map<String, dynamic>>(
              future: _getAchStatus(),
              builder: (ctx, snap) {
                final d = snap.data;
                if (d == null) return const SizedBox.shrink();
                if ((d['hidden'] as bool) ?? false) return const SizedBox.shrink();
                final count = (d['count'] as int?) ?? 0;
                if (count > 0) {
                  return _buildMenuItem(Icons.emoji_events_rounded, '我的成就', '$count/3 已解锁', onTap: _openAchievements);
                }
                return const SizedBox.shrink();
              },
            ),
            _buildMenuItem(Icons.info_outline_rounded, '关于练申论', 'v0.46.3', onTap: _playAboutAudio),
          ]),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, color: const Color(0xFF1A1A2E), size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFF1A1A2E)),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}


// ── API 设置教程页 ──
class _ApiKeyTutorialPage extends StatefulWidget {
  final String currentKey;
  final Future<void> Function(String key) onSaved;
  const _ApiKeyTutorialPage({required this.currentKey, required this.onSaved});

  @override
  State<_ApiKeyTutorialPage> createState() => _ApiKeyTutorialPageState();
}

class _ApiKeyTutorialPageState extends State<_ApiKeyTutorialPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentKey);
  }

  @override
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onSaved(_controller.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 已保存'), duration: Duration(seconds: 1)),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepSeek API 设置教程')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 标题 ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(children: [
              Text('🤖', style: TextStyle(fontSize: 48)),
              SizedBox(height: 8),
              Text('AI 智能批改', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('接入 DeepSeek 大模型，为你的申论答案提供智能评分与详细反馈', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
            ]),
          ),

          const SizedBox(height: 24),

          // ── AI 能做什么 ──
          _sectionTitle('✨ AI 批改能做什么'),
          const SizedBox(height: 10),
          _featureCard('📝', '智能评分', '从内容质量、结构逻辑、语言表达等多维度打分'),
          _featureCard('💡', '详细批注', '指出具体问题并给出修改建议，标注材料对应关系'),
          _featureCard('📊', '弱项分析', '统计各题型得分率，帮你精准定位薄弱环节'),
          _featureCard('📋', '个性化学习计划', '根据错题数据生成专属复习方案'),

          const SizedBox(height: 24),

          // ── 获取步骤 ──
          _sectionTitle('📖 如何获取 API Key'),
          const SizedBox(height: 10),
          _stepCard('1', '打开 DeepSeek 开发者平台',
            '在浏览器中访问 platform.deepseek.com，点击右上角「注册」按钮，使用手机号或邮箱注册账号。'),
          _stepCard('2', '完成实名认证',
            '登录后进入「个人中心」→「实名认证」，按提示填写信息完成认证（通常几分钟审核通过）。'),
          _stepCard('3', '创建 API Key',
            '进入左侧菜单「API Keys」页面，点击「创建 API Key」，输入名称（如"申论App"），复制生成的 key。'),
          _stepCard('4', '粘贴到下方输入框',
            '将复制的 key（格式为 sk-xxxxxxxx）粘贴到本页底部的输入框中，点击「保存」即可。'),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.2)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFF4ECDC4), size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                '提示：Key 创建后仅显示一次，请立即复制保存。如遗失需重新创建新 Key。',
                style: TextStyle(fontSize: 13, color: Color(0xFF4ECDC4), height: 1.5),
              )),
            ]),
          ),

          const SizedBox(height: 24),

          // ── 费用说明 ──
          _sectionTitle('💰 费用说明'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FeeItem('注册赠送', '新用户注册即送 500 万 tokens 免费额度'),
              _FeeItem('收费标准', 'deepseek-chat 模型：￥1 / 百万 tokens（约 60 万汉字）'),
              _FeeItem('一篇申论', '评分一次约消耗 2000-4000 tokens，约 ￥0.002-0.004'),
              _FeeItem('月均花费', '按每天练习 5 题计算，月均约 ￥0.3-0.6'),
              _FeeItem('充值门槛', '最低充值 ￥10，余额长期有效'),
            ]),
          ),

          const SizedBox(height: 24),

          // ── 隐私安全 ──
          _sectionTitle('🔒 隐私安全'),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_rounded, color: Colors.green, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                '你的 API Key 和答题内容仅通过 HTTPS 加密传输到 DeepSeek 官方服务器进行批改，不经由任何第三方中转。Key 仅保存在你的手机本地，不上传我们的服务器。',
                style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.6),
              )),
            ]),
          ),

          const SizedBox(height: 32),

          // ── Key 输入区 ──
          Text('🔑 输入你的 API Key', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: widget.currentKey.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _controller.clear(),
                    ) : null,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('保存 API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
  }

  Widget _featureCard(String emoji, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _stepCard(String num, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF4ECDC4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
        ])),
      ]),
    );
  }
}

class _FeeItem extends StatelessWidget {
  final String label;
  final String value;
  const _FeeItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4))),
      ]),
    );
  }
}
