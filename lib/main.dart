import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/question_screen.dart';
import 'screens/words_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/news_screen.dart';
import 'screens/material_library_screen.dart';
import 'screens/daily_push_card.dart';
import 'services/app_navigator.dart';
import 'services/daily_push.dart';
import 'services/news_scraper.dart';
import 'database/db_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('Flutter Error: ${details.exception}');
  };
  runApp(const ShenlunApp());
}

class ShenlunApp extends StatefulWidget {
  const ShenlunApp({super.key});
  @override
  State<ShenlunApp> createState() => ShenlunAppState();
}

class ShenlunAppState extends State<ShenlunApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _isEyeProtection = false;
  double _fontScale = 1.0;
  bool _pushEnabled = true;
  bool _pushShown = false;

  @override
  void initState() {
    super.initState();
    _loadPushSettings();
  }

  Future<void> _loadPushSettings() async {
    try {
      final db = DatabaseHelper();
      final v = await db.getSetting('daily_push_enabled');
      if (v.isNotEmpty) _pushEnabled = v == 'true';
      if (v.isEmpty) _pushEnabled = true;
    } catch (_) {}
  }

  void togglePush(bool v) {
    _pushEnabled = v;
    DatabaseHelper().setSetting('daily_push_enabled', v ? 'true' : 'false');
    setState(() {});
  }

  void _setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);
  void _setEyeProtection(bool v) => setState(() => _isEyeProtection = v);
  void setFontScale(double s) => setState(() => _fontScale = s);
  ThemeMode get themeMode => _themeMode;
  bool get isEyeProtection => _isEyeProtection;
  double get fontScale => _fontScale;

  /// 统一入口：三模式切换（唯一公开的修改方法）
  void applyThemeMode(String mode) {
    switch (mode) {
      case 'dark':
        _setThemeMode(ThemeMode.dark);
        _setEyeProtection(false);
        break;
      case 'eye':
        _setThemeMode(ThemeMode.light);
        _setEyeProtection(true);
        break;
      default: // 'light'
        _setThemeMode(ThemeMode.light);
        _setEyeProtection(false);
    }
  }

  static ShenlunAppState of(BuildContext context) {
    return context.findAncestorStateOfType<ShenlunAppState>()!;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_fontScale)),
      child: MaterialApp(
      navigatorKey: AppNavigator.key,
      title: '练申论',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _isEyeProtection
          ? ThemeData(
              brightness: Brightness.light,
              primaryColor: const Color(0xFF8B7355),
              scaffoldBackgroundColor: const Color(0xFFF4ECD8),
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF8B7355),
                secondary: Color(0xFFD4756B),
                surface: Color(0xFFFFF8EC),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
              ),
              cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: const Color(0xFFFFF8EC)),
              appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
                titleTextStyle: TextStyle(color: Color(0xFF5D4037), fontSize: 18, fontWeight: FontWeight.w700)),
              textTheme: const TextTheme(bodyMedium: TextStyle(color: Color(0xFF4E342E)), bodySmall: TextStyle(color: Color(0xFF6D4C41))),
              pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()}),
              useMaterial3: true,
            )
          : ThemeData(
              brightness: Brightness.light,
              primaryColor: const Color(0xFF1A1A2E),
              scaffoldBackgroundColor: const Color(0xFFF8F9FC),
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF1A1A2E),
                secondary: Color(0xFFE94560),
                surface: Colors.white,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
              ),
              cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: Colors.white),
              appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
                titleTextStyle: TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700)),
              pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()}),
              useMaterial3: true,
            ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF4ECDC4),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF4ECDC4), secondary: Color(0xFFE94560), surface: Color(0xFF16213E)),
        cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: const Color(0xFF16213E)),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()}),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final padding = MediaQuery.of(context).padding;
        return Column(
          children: [
            SizedBox(height: padding.top),
            Container(height: 1.5, color: const Color(0xFFD0D0D0)),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: child!,
              ),
            ),
            Container(height: 2, color: const Color(0xFFD0D0D0)),
            SizedBox(height: padding.bottom),
          ],
        );
      },
      home: const SplashScreen(),
    ),
    );
  }
}

/// ── 启动页：「恰同学少年」──
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(pageBuilder: (_, __, ___) => const MainShell(), transitionDuration: const Duration(milliseconds: 500), reverseTransitionDuration: Duration.zero, transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)),
        );
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [Color(0xFF2A2A4E), Color(0xFF1A1A2E), Color(0xFF0D0D22)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(flex: 3),
              // 金字 — 四行
              Text('恰同学少年', style: TextStyle(fontSize: 34, fontFamily: 'STXingkai', color: Color(0xFFE8C560), letterSpacing: 2, height: 1.8)),
              Text('风华正茂', style: TextStyle(fontSize: 34, fontFamily: 'STXingkai', color: Color(0xFFE8C560), letterSpacing: 2, height: 1.8)),
              Text('书生意气', style: TextStyle(fontSize: 34, fontFamily: 'STXingkai', color: Color(0xFFE8C560), letterSpacing: 2, height: 1.8)),
              Text('挥斥方遒', style: TextStyle(fontSize: 34, fontFamily: 'STXingkai', color: Color(0xFFE8C560), letterSpacing: 2, height: 1.8)),
              Spacer(flex: 2),
              // 红金装饰线
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 80, height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE94560), Color(0xFFE8C560)]))),
                SizedBox(width: 12),
                Container(width: 80, height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE8C560), Color(0xFFE94560)]))),
              ]),
              SizedBox(height: 16),
              Text('公考题库 · 时政积累', style: TextStyle(fontSize: 13, color: Color(0x99E8C560), letterSpacing: 2)),
              const Spacer(flex: 1),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('该软件只用于免费学习交流，切勿牟利',
                    style: TextStyle(fontSize: 10, color: Color(0x33FFFFFF), letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _pushShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showPush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 截屏会触发 resume 两次导致推送弹出两次，去掉这里改为只在冷启动弹出
  }

  void _switchTab(int index) => setState(() => _currentIndex = index);

  Future<void> _showPush() async {
    if (_pushShown) return;
    _pushShown = true;
    final db = DatabaseHelper();
    final enabled = await db.getSetting('daily_push_enabled');
    if (enabled == 'false') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showPushDialog();
    });
  }

  Future<void> _showPushDialog() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    DailyPush push;
    try {
      final db = DatabaseHelper();
      final apiKey = await db.getSetting('deepseek_api_key');
      push = await DailyPushService.getDailyPush(apiKey.isNotEmpty ? apiKey : null);
    } catch (_) {
      final now = DateTime.now();
      push = DailyPush(
        date: '${now.month}月${now.day}日',
        theme: '今日时政',
        summary: '学如逆水行舟，不进则退。打开时政页面查看最新资讯。',
        bgColor: const Color(0xFF1A1A2E),
        quote: '日拱一卒，功不唐捐。',
      );
    }

    if (!mounted || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 120),
        child: DailyPushCard(push: push, onClose: () => Navigator.of(context).pop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onNavigateToTab: _switchTab),
      const NewsScreen(),
      QuestionScreen(onNavigateToTab: _switchTab),
      const WordsScreen(),
      const MaterialLibraryScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: const Color(0xFFD0D0D0), width: 1.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedItemColor: const Color(0xFFE94560),
            unselectedItemColor: Colors.grey.shade400,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '首页'),
              BottomNavigationBarItem(icon: Icon(Icons.newspaper_rounded), label: '时政'),
              BottomNavigationBarItem(icon: Icon(Icons.edit_note_rounded), label: '题库'),
              BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: '规范词'),
              BottomNavigationBarItem(icon: Icon(Icons.library_books_rounded), label: '素材库'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: '我的'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockScreenDialog extends StatefulWidget {
  final VoidCallback onUnlock;
  const _LockScreenDialog({required this.onUnlock});
  @override
  State<_LockScreenDialog> createState() => _LockScreenDialogState();
}

class _LockScreenDialogState extends State<_LockScreenDialog> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _c1.dispose(); _c2.dispose();
    super.dispose();
  }

  void _check() {
    if (_c1.text.trim() == '100' && _c2.text.trim() == '4') {
      Navigator.pop(context);
      widget.onUnlock();
    } else {
      setState(() => _error = '答案不正确，请重新输入');
      _c1.clear(); _c2.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 40, color: Color(0xFF1A1A2E)),
            const SizedBox(height: 12),
            const Text('请输入正确答案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('1    1    ___    ___    兀    3    5',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 4, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 6),
            const Text('请按照规律填写后两个数字', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 60, child: TextField(controller: _c1, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '?'))),
              const SizedBox(width: 12),
              SizedBox(width: 60, child: TextField(controller: _c2, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '?'))),
            ]),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _check,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('确定提交', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
