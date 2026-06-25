import 'package:shared_preferences/shared_preferences.dart';

class AchievementService {
  static const _keys = ['achievement_qs', 'achievement_zheng', 'achievement_earth'];

  static Future<int> unlockedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _keys.where((k) => prefs.getBool(k) ?? false).length;
  }

  static Future<bool> isAllUnlocked() async => await unlockedCount() == _keys.length;

  static Future<List<Map<String, String>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final all = [
      {'key': _keys[0], 'title': '情书不朽', 'content': '与你的下一次邂逅，是十二万亿九千六百年后', 'tag': '情书再不朽 也磨成沙漏', 'img': 'assets/achievement_qs.jpg'},
      {'key': _keys[1], 'title': '只争朝夕', 'content': '四海翻腾云水怒，五洲震荡风雷激！', 'tag': '今日长缨在手，何时缚住苍龙？', 'img': 'assets/achievement_zheng.png'},
      {'key': _keys[2], 'title': '把申论写在大地上', 'content': '把申论写在祖国大地上，把答案写在群众心里', 'tag': '为党分忧，为民解难！', 'img': 'assets/achievement_earth.jpg'},
    ];
    return all.map((a) => {
      ...a,
      'unlocked': (prefs.getBool(a['key']!) ?? false) ? 'true' : 'false',
    }).toList();
  }

  static Future<bool> tryUnlockHidden() async {
    if (!await isAllUnlocked()) return false;
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('achievement_hidden_shown') ?? false;
    if (shown) return false;
    await prefs.setBool('achievement_hidden_shown', true);
    return true;
  }

  static Future<bool> hiddenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('achievement_hidden_shown') ?? false;
  }
}
