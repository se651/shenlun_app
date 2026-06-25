/// 数据库助手 — 初始化 shenlun.db，提供查询接口
/// Native 端：sqflite + SQLite 文件
/// Web 端：内存 JSON 数据库（sqflite 不可用）
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart' show Database, openDatabase, getDatabasesPath, ConflictAlgorithm;
import 'package:path/path.dart' as p;
import '../services/web_db.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._();

  Database? _db;
  bool _initAttempted = false;
  final WebDatabase _webDb = WebDatabase();

  Future<Database?> get database async {
    if (_db != null) return _db;
    if (_initAttempted) return null;
    _initAttempted = true;
    if (kIsWeb) {
      await _webDb.init();
      return null; // Web 端返回 null，调用方会走 _webDb
    }
    _db = await _initDb();
    return _db;
  }

  Future<Database?> _initDb() async {
    if (kIsWeb) return null; // Web 不支持 sqflite，走静态降级
    try {
      // 使用 sqflite 原生数据库路径（Android: /data/data/<pkg>/databases/）
      // 比 getApplicationDocumentsDirectory 更可靠，不会被系统清理
      final dbDir = await getDatabasesPath();
      final dbPath = p.join(dbDir, 'shenlun.db');
      final markerPath = p.join(dbDir, '.db_v3_initialized');

      // 标记文件不存在 → 首次安装（或手动删除了标记 → 更新题库）
      if (!await File(markerPath).exists()) {
        // 备份旧设置
        List<Map<String, dynamic>> oldSettings = [];
        if (await File(dbPath).exists()) {
          try {
            final oldDb = await openDatabase(dbPath, readOnly: true);
            try { oldSettings = await oldDb.query('settings'); } catch (_) {}
            await oldDb.close();
          } catch (_) {}
        }

        // 拷贝内置题库
        final data = await rootBundle.load('assets/shenlun.db');
        await File(dbPath).writeAsBytes(data.buffer.asUint8List());

        // 迁移旧设置
        if (oldSettings.isNotEmpty) {
          try {
            final db = await openDatabase(dbPath);
            for (final row in oldSettings) {
              await db.insert('settings', row, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await db.close();
          } catch (_) {}
        }

        // 创建标记文件（只有写入成功才标记）
        await File(markerPath).writeAsString('1');
      }

      return await openDatabase(dbPath);
    } catch (e) {
      // Web / unsupported platform — return null
      return null;
    }
  }

  // ========== 题目查询 ==========
  Future<List<String>> getQuestionTypes() async {
    final db = await database; if (db == null) return ['概括归纳', '综合分析', '提出对策', '应用文写作', '文章论述（大作文）'];
    final r = await db.rawQuery('SELECT DISTINCT question_type FROM questions WHERE is_deleted=0');
    return r.map((e) => e['question_type'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getQuestions({
    String? questionType,
    List<String>? questionTypes,
    int? year,
    String? region,
    int limit = 20,
    int offset = 0,
    String? filterRegion,
    bool byPaper = false,
    String? examCategory,
    String? orderBy,
  }) async {
    if (kIsWeb) return _webDb.getQuestions(questionType: questionType, year: year, region: region, limit: limit, offset: offset);
    final db = await database;
    if (db == null) return [];
    final where = <String>['is_deleted = 0'];
    final args = <dynamic>[];
    if (questionType != null && questionType != '全部题型') {
      if (questionType == '应用文' || questionType == '应用文写作') {
        where.add("question_type LIKE '%应用文%'");
      } else if (questionType == '文章论述（大作文）') {
        where.add("(question_type LIKE '%大作文%' OR question_type LIKE '%文章论述%')");
      } else {
        where.add('question_type = ?');
        args.add(questionType);
      }
    } else if (questionTypes != null && questionTypes.isNotEmpty) {
      final clauses = <String>[];
      for (final t in questionTypes) {
        if (t == '应用文写作') {
          clauses.add("question_type LIKE '%应用文%'");
        } else if (t == '文章论述（大作文）') {
          clauses.add("(question_type LIKE '%大作文%' OR question_type LIKE '%文章论述%')");
        } else {
          clauses.add('question_type = ?');
          args.add(t);
        }
      }
      where.add('(${clauses.join(' OR ')})');
    }
    if (examCategory != null) {
      where.add('exam_category = ?');
      args.add(examCategory);
    }
    final useRegion = filterRegion ?? region;
    if (year != null) {
      where.add('year = ?');
      args.add(year);
    }
    if (useRegion != null && useRegion != '全部') {
      if (useRegion == '国考') {
        where.add("region = '国家'");
      } else if (useRegion == '省考') {
        where.add("region IS NOT NULL AND region != '国家' AND region != ''");
      } else {
        where.add('region = ?');
        args.add(useRegion);
      }
    } else if (region != null) {
      if (region == '国考') {
        where.add("region = '国家'");
      } else if (region == '省考') {
        where.add("region IS NOT NULL AND region != '国家'");
      } else {
        where.add('region = ?');
        args.add(region);
      }
    }
    return db.rawQuery('''
      SELECT q.*, pr.last_practice
      FROM questions q
      LEFT JOIN (SELECT question_id, MAX(created_at) as last_practice FROM practice_records GROUP BY question_id) pr
        ON q.id = pr.question_id
      WHERE ${where.join(' AND ')}
      ORDER BY CASE WHEN pr.last_practice IS NULL THEN 0 ELSE 1 END,
               pr.last_practice ASC,
               q.year DESC
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);
  }

  // ========== 关键字搜索（搜材料，同时查 questions 和 paper_questions） ==========
  Future<List<Map<String, dynamic>>> searchQuestions(
    String keyword, {
    String? questionType,
    String? region,
  }) async {
    if (kIsWeb) return _webDb.searchQuestions(keyword, questionType: questionType);
    final db = await database;
    if (db == null) return [];
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    /// 构建 WHERE 子句（复用 SQL 字符串，用于两个子查询）
    String buildWhere(String tableAlias) {
      final parts = <String>['${tableAlias}is_deleted = 0'];
      if (region != null && region.isNotEmpty && region != '全部') {
        if (region == '国考') {
          parts.add("${tableAlias}region = '国家'");
        } else if (region == '省考') {
          parts.add("${tableAlias}region IS NOT NULL AND ${tableAlias}region != '国家'");
        }
      }
      if (questionType != null && questionType != '全部题型') {
        if (questionType == '应用文' || questionType == '应用文写作') {
          parts.add("${tableAlias}question_type LIKE '%应用文%'");
        } else if (questionType == '文章论述（大作文）') {
          parts.add("(${tableAlias}question_type LIKE '%大作文%' OR ${tableAlias}question_type LIKE '%文章论述%')");
        } else {
          final escaped = questionType.replaceAll("'", "''");
          parts.add("${tableAlias}question_type = '$escaped'");
        }
      }
      return parts.join(' AND ');
    }

    final qWhere = buildWhere('q.');
    final pqWhere = buildWhere('pq.');
    final escapedKw = kw.replaceAll("'", "''");

    return db.rawQuery('''
      SELECT id, question_type, title, content, year, region,
             exam_type, exam_subtype, exam_category, word_limit,
             reference_answer, is_deleted, NULL as paper_id, NULL as paper_title
      FROM questions q
      WHERE $qWhere AND q.content LIKE '%$escapedKw%'

      UNION ALL

      SELECT id, question_type, title, content, year, region,
             exam_type, exam_subtype, exam_category, word_limit,
             reference_answer, is_deleted, paper_id, paper_title
      FROM paper_questions pq
      WHERE $pqWhere AND pq.content LIKE '%$escapedKw%'

      ORDER BY year DESC
    ''');
  }

  Future<Map<String, dynamic>?> getQuestionById(String id) async {
    if (kIsWeb) return _webDb.getQuestionById(id);
    final db = await database; if (db == null) return null;
    final results =
        await db.query('questions', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> getQuestionCount() async {
    if (kIsWeb) return _webDb.getQuestionCount();
    final db = await database; if (db == null) return 640;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM questions WHERE is_deleted=0');
    return result.first['c'] as int;
  }

  // ========== 规范词查询 ==========
  Future<List<Map<String, dynamic>>> getWords({String? category}) async {
    if (kIsWeb) return _webDb.getWords(category: category);
    final db = await database; if (db == null) return [];
    if (category != null) {
      return db.query('high_freq_words', where: 'category = ?', whereArgs: [category]);
    }
    return db.query('high_freq_words');
  }

  Future<int> getWordCount() async {
    if (kIsWeb) return _webDb.getWordCount();
    final db = await database; if (db == null) return 1006;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM high_freq_words');
    return result.first['c'] as int? ?? 1006;
  }

  Future<List<String>> getWordCategories() async {
    if (kIsWeb) return _webDb.getWordCategories();
    final db = await database; if (db == null) return [];
    final result =
        await db.rawQuery('SELECT DISTINCT category FROM high_freq_words ORDER BY category');
    return result.map((r) => r['category'] as String).toList();
  }

  // ========== 题型统计 ==========
  Future<Map<String, int>> getQuestionTypeStats() async {
    if (kIsWeb) return _webDb.getQuestionTypeStats();
    final db = await database; if (db == null) return {};
    final result = await db.rawQuery(
        'SELECT question_type, COUNT(*) as c FROM questions WHERE is_deleted=0 GROUP BY question_type');
    return {for (var r in result) r['question_type'] as String: r['c'] as int};
  }

  Future<Map<String, int>> getQuestionTypeStatsByRegion(String region) async {
    if (kIsWeb) return _webDb.getQuestionTypeStatsByRegion(region);
    final db = await database; if (db == null) return {};
    final regionWhere = region == '国考' ? "region = '国家'" : "region IS NOT NULL AND region != '国家'";
    final result = await db.rawQuery(
        'SELECT question_type, COUNT(*) as c FROM questions WHERE is_deleted=0 AND $regionWhere GROUP BY question_type');
    return {for (var r in result) r['question_type'] as String: r['c'] as int};
  }

  // ========== 练习记录 ==========
  Future<void> savePracticeRecord(Map<String, dynamic> record) async {
    if (kIsWeb) { await _webDb.savePracticeRecord(record); return; }
    final db = await database; if (db == null) return;
    await db.insert('practice_records', record,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPracticeHistory({int limit = 50}) async {
    if (kIsWeb) return _webDb.getPracticeHistory(limit: limit);
    final db = await database; if (db == null) return [];
    return db.query('practice_records', orderBy: 'created_at DESC', limit: limit);
  }

  Future<void> updatePracticeRecordAiAnswer(String questionId, String aiAnswer) async {
    if (kIsWeb) return;
    final db = await database; if (db == null) return;
    try {
      final rows = await db.rawQuery('SELECT id FROM practice_records WHERE question_id = ? ORDER BY id DESC LIMIT 1', [questionId]);
      if (rows.isNotEmpty) {
        await db.update('practice_records', {'ai_answer': aiAnswer}, where: 'id = ?', whereArgs: [rows.first['id']]);
      }
    } catch (_) {}
  }

  Future<void> deletePracticeRecord(String id) async {
    if (kIsWeb) { await _webDb.deletePracticeRecord(id); return; }
    final db = await database; if (db == null) return;
    await db.delete('practice_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllPracticeRecords(String questionId) async {
    if (kIsWeb) { await _webDb.deleteAllPracticeRecords(questionId); return; }
    final db = await database; if (db == null) return;
    await db.delete('practice_records', where: 'question_id = ?', whereArgs: [questionId]);
  }

  // ========== 收藏 ==========
  Future<bool> isFavorited(String questionId) async {
    if (kIsWeb) return _webDb.isFavorited(questionId);
    final db = await database; if (db == null) return false;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM favorites WHERE question_id = ?', [questionId]);
    return (r.first['c'] as int? ?? 0) > 0;
  }

  Future<void> toggleFavorite(String questionId) async {
    if (kIsWeb) { await _webDb.toggleFavorite(questionId); return; }
    final db = await database; if (db == null) return;
    final exist = await db
        .query('favorites', where: 'question_id = ?', whereArgs: [questionId]);
    if (exist.isNotEmpty) {
      await db.delete('favorites', where: 'question_id = ?', whereArgs: [questionId]);
    } else {
      await db.insert('favorites', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'question_id': questionId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // ========== 用户信息 ==========
  Future<Map<String, dynamic>> getUserInfo() async {
    if (kIsWeb) return _webDb.getUserInfo();
    final db = await database; if (db == null) return {};
    final result = await db.query('user_info', limit: 1);
    return result.isNotEmpty ? result.first : {};
  }

  Future<void> updateUserStats({int? addPractice, String? lastDate}) async {
    if (kIsWeb) { await _webDb.updateUserStats(addPractice: addPractice, lastDate: lastDate); return; }
    final db = await database; if (db == null) return;
    if (addPractice != null) {
      await db.rawUpdate(
          'UPDATE user_info SET total_practice_count = total_practice_count + ?',
          [addPractice]);
    }
    if (lastDate != null) {
      await db.rawUpdate('UPDATE user_info SET last_practice_date = ?', [lastDate]);
    }
  }

  // ========== 套卷库（paper_questions 表）==========
  
  /// 获取所有套卷列表（分组）
  Future<List<Map<String, dynamic>>> getPaperList({
    String? region,
    String? examCategory,
  }) async {
    final db = await database; if (db == null) return [];
    final where = <String>['is_deleted = 0'];
    final args = <dynamic>[];
    if (region != null && region != '全部') {
      if (region == '国考') { where.add("region = '国家'"); }
      else if (region == '省考') { where.add("region != '国家'"); }
      else { where.add('region = ?'); args.add(region); }
    }
    if (examCategory != null) { where.add('exam_category = ?'); args.add(examCategory); }
    return db.rawQuery('''
      SELECT paper_id, paper_title, year, region, exam_type, exam_subtype, exam_category,
             COUNT(*) as question_count, GROUP_CONCAT(question_type) as types
      FROM paper_questions
      WHERE ${where.join(' AND ')}
      GROUP BY paper_id
      ORDER BY year DESC, region
    ''', args);
  }

  /// 获取某套卷的所有题目
  Future<List<Map<String, dynamic>>> getPaperQuestions(String paperId) async {
    final db = await database; if (db == null) return [];
    return db.query('paper_questions',
      where: 'paper_id = ? AND is_deleted = 0',
      whereArgs: [paperId],
      orderBy: 'question_index',
    );
  }

  /// 设置套卷题答案
  Future<void> setPaperQuestionAnswer(String id, String answer) async {
    final db = await database; if (db == null) return;
    await db.update('paper_questions', {'reference_answer': answer}, where: 'id = ?', whereArgs: [id]);
  }

  /// 根据 ID 获取单道套卷题
  Future<Map<String, dynamic>?> getPaperQuestionById(String id) async {
    final db = await database; if (db == null) return null;
    final results = await db.query('paper_questions', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  // ========== 套卷答题历史 ==========
  Future<List<Map<String, dynamic>>> getPaperAnswerHistory(String paperId) async {
    final json = await getSetting('paper_answers_$paperId');
    if (json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }

  Future<void> savePaperAnswerHistory(String paperId, List<Map<String, dynamic>> history) async {
    await setSetting('paper_answers_$paperId', jsonEncode(history));
  }

  /// 套卷题型统计
  Future<Map<String, int>> getPaperTypeStats() async {
    final db = await database; if (db == null) return {};
    final result = await db.rawQuery(
        'SELECT question_type, COUNT(*) as c FROM paper_questions WHERE is_deleted=0 GROUP BY question_type');
    return {for (var r in result) r['question_type'] as String: r['c'] as int};
  }

  Future<Map<String, int>> getPaperTypeStatsByRegion(String region) async {
    final db = await database; if (db == null) return {};
    final regionWhere = region == '国考' ? "region = '国家'" : "region != '国家'";
    final result = await db.rawQuery(
        'SELECT question_type, COUNT(*) as c FROM paper_questions WHERE is_deleted=0 AND $regionWhere GROUP BY question_type');
    return {for (var r in result) r['question_type'] as String: r['c'] as int};
  }

  // ========== 套卷历史 ==========
  Future<List<String>> getPaperHistory() async {
    final json = await getSetting('paper_history');
    if (json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) { return []; }
  }

  Future<void> addPaperToHistory(String paperId) async {
    final history = await getPaperHistory();
    history.remove(paperId);
    history.insert(0, paperId);
    await setSetting('paper_history', jsonEncode(history));
  }

  Future<void> removePaperFromHistory(String paperId) async {
    final history = await getPaperHistory();
    history.remove(paperId);
    await setSetting('paper_history', jsonEncode(history));
  }

  Future<bool> isPaperCompleted(String paperId) async {
    final history = await getPaperHistory();
    return history.contains(paperId);
  }

  /// 收藏套卷
  Future<List<String>> getPaperFavorites() async {
    final json = await getSetting('paper_favorites');
    if (json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) { return []; }
  }

  Future<void> togglePaperFavorite(String paperId) async {
    final favs = await getPaperFavorites();
    if (favs.contains(paperId)) {
      favs.remove(paperId);
    } else {
      favs.insert(0, paperId);
    }
    await setSetting('paper_favorites', jsonEncode(favs));
  }

  Future<bool> isPaperFavorited(String paperId) async {
    final favs = await getPaperFavorites();
    return favs.contains(paperId);
  }

  Future<List<Map<String, dynamic>>> getPaperListByIds(List<String> paperIds) async {
    final db = await database; if (db == null) return [];
    if (paperIds.isEmpty) return [];
    final placeholders = paperIds.map((_) => '?').join(',');
    return db.rawQuery('''
      SELECT paper_id, paper_title, year, region, exam_subtype, exam_category,
             COUNT(*) as question_count, GROUP_CONCAT(question_type) as types
      FROM paper_questions
      WHERE paper_id IN ($placeholders) AND is_deleted = 0
      GROUP BY paper_id
    ''', paperIds);
  }

  // ========== 设置 ==========
  Future<String> getSetting(String key) async {
    if (kIsWeb) return _webDb.getSetting(key);
    final db = await database; if (db == null) return '';
    final result =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return result.isNotEmpty ? result.first['value'] as String : '';
  }

  Future<void> setSetting(String key, String value) async {
    if (kIsWeb) { await _webDb.setSetting(key, value); return; }
    final db = await database; if (db == null) return;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
