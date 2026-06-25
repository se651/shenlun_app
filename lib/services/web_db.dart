/// Web 端内存数据库 — sqflite 不可用时的降级方案
/// 从 assets/empty_questions.json 加载题目到内存，用 Dart 过滤替代 SQL
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'local_storage.dart';

class WebDatabase {
  static final WebDatabase _instance = WebDatabase._();
  factory WebDatabase() => _instance;
  WebDatabase._();

  List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _paperQuestions = [];
  List<Map<String, dynamic>> _words = [];
  final List<Map<String, dynamic>> _practiceRecords = [];
  final Set<String> _favoriteIds = {};
  int _totalPracticeCount = 0;
  String _lastPracticeDate = '';
  final Map<String, String> _settings = {};

  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final jsonStr = await rootBundle.loadString('full_questions.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final list = data['questions'] as List<dynamic>? ?? [];
      _questions = list.map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'] ?? '',
          'question_type': m['type'] ?? '',
          'title': m['title'] ?? '',
          'score': m['score'] ?? '',
          'content': m['content'] ?? '',
          'word_limit': m['word_limit'] ?? 0,
          'year': m['year'] ?? _extractYear(m['content'] as String? ?? ''),
          'region': m['region'] ?? '国考',
          'exam_type': m['exam_type'] ?? '',
          'exam_subtype': m['exam_subtype'] ?? '',
          'exam_category': m['exam_category'] ?? '',
          'is_deleted': 0,
        };
      }).toList();
      // 加载套卷题目（paper_questions）
      final paperList = data['paper_questions'] as List<dynamic>? ?? [];
      _paperQuestions = paperList.map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'] ?? '',
          'question_type': m['question_type'] ?? '',
          'title': m['title'] ?? '',
          'content': m['content'] ?? '',
          'year': m['year'] ?? 2024,
          'region': m['region'] ?? '',
          'exam_type': m['exam_type'] ?? '',
          'exam_subtype': m['exam_subtype'] ?? '',
          'exam_category': m['exam_category'] ?? '',
          'word_limit': m['word_limit'] ?? 0,
          'reference_answer': m['reference_answer'] ?? '',
          'is_deleted': 0,
          'paper_id': m['paper_id'] ?? '',
          'paper_title': m['paper_title'] ?? '',
        };
      }).toList();
      // 加载规范词
      final wordList = data['words'] as List<dynamic>? ?? [];
      _words = wordList.map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'category': m['category'] ?? '',
          'word': m['word'] ?? '',
          'explanation': m['explanation'] ?? m['context'] ?? '',
          'usage': m['usage'] ?? '',
        };
      }).toList();
    } catch (e) {
      _questions = [];
      _words = [];
    }
    // Load reference answers from DB backup
    try {
      final ansJson = await rootBundle.loadString('assets/reference_answers.json');
      final ansMap = json.decode(ansJson) as Map<String, dynamic>;
      for (int i = 0; i < _questions.length; i++) {
        final qid = _questions[i]['id'] as String;
        if (ansMap.containsKey(qid)) {
          _questions[i]['reference_answer'] = ansMap[qid] as String;
        }
      }
    } catch (_) {}
    _loadPersisted();
    _loaded = true;
  }

  /// 从材料内容提取年份
  int _extractYear(String content) {
    // 尝试匹配 20XX 年或 19XX 年
    final m = RegExp(r'(20\d{2})\s*年').firstMatch(content);
    if (m != null) return int.tryParse(m.group(1)!) ?? 2024;
    // 从给定资料编号推测
    final m2 = RegExp(r'给定资料.*?(\d{4})').firstMatch(content);
    if (m2 != null) return int.tryParse(m2.group(1)!) ?? 2024;
    return 2024;
  }

  // ========== 题目查询 ==========

  Future<List<Map<String, dynamic>>> getQuestions({
    String? questionType,
    int? year,
    String? region,
    int limit = 20,
    int offset = 0,
  }) async {
    await _ensureLoaded();
    var filtered = _questions.where((q) => q['is_deleted'] == 0).toList();

    if (questionType != null && questionType != '全部题型') {
      final qt = questionType;
      if (qt == '应用文' || qt == '应用文写作') {
        filtered = filtered.where((q) {
          final t = q['question_type'] as String;
          return t.contains('应用文');
        }).toList();
      } else if (qt == '文章论述（大作文）') {
        filtered = filtered.where((q) {
          final t = q['question_type'] as String;
          return t.contains('大作文') || t.contains('文章论述');
        }).toList();
      } else {
        filtered = filtered.where((q) => q['question_type'] == qt).toList();
      }
    }

    if (year != null) {
      filtered = filtered.where((q) => q['year'] == year).toList();
    }
    if (region != null) {
      filtered = filtered.where((q) => q['region'] == region).toList();
    }

    filtered.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));

    final start = offset.clamp(0, filtered.length);
    final end = (start + limit).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  Future<List<Map<String, dynamic>>> searchQuestions(
    String keyword, {
    String? questionType,
    String? region,
  }) async {
    await _ensureLoaded();
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    bool matches(Map<String, dynamic> q) {
      final content = q['content'] as String? ?? '';
      if (!content.contains(kw) || (q['is_deleted'] ?? 0) != 0) return false;
      if (region != null && region.isNotEmpty && region != '全部') {
        final r = q['region'] as String? ?? '';
        final match = region == '国考' ? r == '国家' : (r.isNotEmpty && r != '国家');
        if (!match) return false;
      }
      if (questionType != null && questionType != '全部题型') {
        final t = q['question_type'] as String? ?? '';
        final qt = questionType;
        if (qt == '应用文' || qt == '应用文写作') {
          if (!t.contains('应用文')) return false;
        } else if (qt == '文章论述（大作文）') {
          if (!t.contains('大作文') && !t.contains('文章论述')) return false;
        } else {
          if (t != qt) return false;
        }
      }
      return true;
    }

    final combined = <Map<String, dynamic>>[];
    for (final q in _questions) {
      if (matches(q)) combined.add(q);
    }
    for (final q in _paperQuestions) {
      if (matches(q)) combined.add(q);
    }

    combined.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
    return combined;
  }

  Future<Map<String, dynamic>?> getQuestionById(String id) async {
    await _ensureLoaded();
    try {
      return _questions.firstWhere((q) => q['id'] == id);
    } catch (_) {
      try {
        return _paperQuestions.firstWhere((q) => q['id'] == id);
      } catch (_) {
        return null;
      }
    }
  }

  Future<int> getQuestionCount() async {
    await _ensureLoaded();
    return _questions.where((q) => q['is_deleted'] == 0).length;
  }

  // ========== 规范词 ==========

  Future<List<Map<String, dynamic>>> getWords({String? category}) async {
    await _ensureLoaded();
    if (_words.isEmpty) return [];
    if (category != null) {
      return _words.where((w) => w['category'] == category).toList();
    }
    return _words;
  }

  Future<int> getWordCount() async {
    await _ensureLoaded();
    return _words.length;
  }

  Future<List<String>> getWordCategories() async {
    await _ensureLoaded();
    final cats = _words.map((w) => w['category'] as String).toSet();
    return cats.toList()..sort();
  }

  // ========== 题型统计 ==========

  Future<Map<String, int>> getQuestionTypeStats() async {
    await _ensureLoaded();
    final stats = <String, int>{};
    for (final q in _questions) {
      if (q['is_deleted'] != 0) continue;
      final t = q['question_type'] as String? ?? '其他';
      stats[t] = (stats[t] ?? 0) + 1;
    }
    return stats;
  }

  Future<Map<String, int>> getQuestionTypeStatsByRegion(String region) async {
    await _ensureLoaded();
    final stats = <String, int>{};
    for (final q in _questions) {
      if (q['is_deleted'] != 0) continue;
      final r = q['region'] as String? ?? '';
      final match = region == '国考' ? r == '国家' : r.isNotEmpty && r != '国家';
      if (!match) continue;
      final t = q['question_type'] as String? ?? '其他';
      stats[t] = (stats[t] ?? 0) + 1;
    }
    return stats;
  }

  // ========== 练习记录 ==========

  Future<void> savePracticeRecord(Map<String, dynamic> record) async {
    await _ensureLoaded();
    _practiceRecords.add(record);
    if (_practiceRecords.length > 200) {
      _practiceRecords.removeAt(0);
    }
    _savePracticeRecords();
  }

  Future<List<Map<String, dynamic>>> getPracticeHistory({int limit = 50}) async {
    final sorted = List<Map<String, dynamic>>.from(_practiceRecords);
    sorted.sort((a, b) {
      final at = a['created_at'] as String? ?? '';
      final bt = b['created_at'] as String? ?? '';
      return bt.compareTo(at);
    });
    return sorted.take(limit).toList();
  }

  Future<void> deletePracticeRecord(String id) async {
    _practiceRecords.removeWhere((r) => r['id'] == id);
    _savePracticeRecords();
  }

  Future<void> deleteAllPracticeRecords(String questionId) async {
    _practiceRecords.removeWhere((r) => r['question_id'] == questionId);
    _savePracticeRecords();
  }

  // ========== 收藏 ==========

  Future<bool> isFavorited(String questionId) async {
    await _ensureLoaded();
    return _favoriteIds.contains(questionId);
  }

  Future<void> toggleFavorite(String questionId) async {
    await _ensureLoaded();
    if (_favoriteIds.contains(questionId)) {
      _favoriteIds.remove(questionId);
    } else {
      _favoriteIds.add(questionId);
    }
    _savePersisted();
  }

  // ========== 用户信息 ==========

  Future<Map<String, dynamic>> getUserInfo() async {
    await _ensureLoaded();
    return {
      'total_practice_count': _totalPracticeCount,
      'last_practice_date': _lastPracticeDate,
    };
  }

  Future<void> updateUserStats({int? addPractice, String? lastDate}) async {
    await _ensureLoaded();
    if (addPractice != null) _totalPracticeCount += addPractice;
    if (lastDate != null) _lastPracticeDate = lastDate;
    _savePersisted();
  }

  // ========== 设置 ==========

  Future<String> getSetting(String key) async {
    return _settings[key] ?? '';
  }

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    _savePersisted();
  }

  // ========== 待办清单 ==========

  bool _initialized = false;
  Future<void> init() async {
    if (_initialized) return;
    await _ensureLoaded();
    _initialized = true;
  }

  /// 从 localStorage 恢复用户数据
  void _loadPersisted() {
    try {
      final favs = storageGet('favorites');
      if (favs.isNotEmpty) {
        _favoriteIds.addAll((json.decode(favs) as List).cast<String>());
      }
      final count = storageGet('practice_count');
      if (count.isNotEmpty) _totalPracticeCount = int.tryParse(count) ?? 0;
      _lastPracticeDate = storageGet('last_practice_date');
      final settings = storageGet('settings');
      if (settings.isNotEmpty) {
        final decoded = json.decode(settings) as Map<String, dynamic>;
        _settings.addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
      }
      final records = storageGet('practice_records');
      if (records.isNotEmpty) {
        final decoded = (json.decode(records) as List).cast<Map<String, dynamic>>();
        _practiceRecords.addAll(decoded);
      }
    } catch (_) {}
  }

  void _savePersisted() {
    try {
      storageSet('favorites', json.encode(_favoriteIds.toList()));
      storageSet('practice_count', _totalPracticeCount.toString());
      storageSet('last_practice_date', _lastPracticeDate);
      storageSet('settings', json.encode(_settings));
    } catch (_) {}
  }

  void _savePracticeRecords() {
    try {
      final data = _practiceRecords.map((r) => {
        'id': r['id'] ?? '',
        'question_id': r['question_id'] ?? '',
        'user_answer': r['user_answer'] ?? '',
        'score': r['score'] ?? 0,
        'score_breakdown': r['score_breakdown'] ?? '',
        'suggestions': r['suggestions'] ?? '',
        'scoring_mode': r['scoring_mode'] ?? '',
        'practice_mode': r['practice_mode'] ?? '',
        'ai_answer': r['ai_answer'] ?? '',
        'ai_analysis': r['ai_analysis'] ?? '',
        'created_at': r['created_at'] ?? '',
      }).toList();
      storageSet('practice_records', json.encode(data));
    } catch (_) {}
  }
}
